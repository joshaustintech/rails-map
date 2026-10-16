require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/rails_map/reference"
require_relative "../lib/rails_map/model_catalog"

# Checks the public reference document and static association evidence.
class ReferenceTest < Minitest::Test
  def test_maps_route_view_model_association_and_dynamic_route
    with_fixture do |root|
      ReferenceTestSupport.assert_navigation(self, RailsMap::Reference.new(root).result("UsersController#show"))
    end
  end

  def test_marks_dynamic_route_sources_unresolved
    with_fixture do |root|
      ReferenceTestSupport.assert_dynamic_route(self, RailsMap::Reference.new(root).result)
    end
  end

  def test_keeps_routes_in_canonical_order
    with_fixture do |root|
      routes = RailsMap::Reference.new(root).result.fetch("routes")
      ReferenceTestSupport.assert_route_order(self, routes)
    end
  end

  def test_repeats_identical_results
    with_fixture do |root|
      ReferenceTestSupport.assert_repeatable(self, root)
    end
  end

  def test_reads_model_constants_from_erb_code
    with_fixture do |root|
      path = File.join(root, "app/views/users/show.html.erb")
      File.write(path, "<%# HiddenModel %>\n<% label = 'TextModel' %>\n<%= User.find(1) %>\n")

      assert_equal ["User"], RailsMap::ReferencedModels.in_file(path)
    end
  end

  def test_resolves_static_associations_and_marks_unknown_targets
    with_fixture do |root|
      ReferenceTestSupport.assert_associations(self, root, association_source)
    end
  end

  private

  def with_fixture
    root = Dir.mktmpdir("rails-map-")
    FileUtils.cp_r(File.join(__dir__, "../fixtures/rails61/."), root)
    yield root
  ensure
    FileUtils.remove_entry(root) if root && Dir.exist?(root)
  end

  def association_source
    <<~RUBY
      class Links
        has_many :people
        has_many :children
        has_many :articles, class_name: "::Writing::Article"
        has_many :tags, through: :taggings
        has_many :subscribers, through: :subscriptions, source: :user
        has_many :memberships, through: dynamic_path
        has_many :members, class_name: dynamic_class
        belongs_to :attachable, polymorphic: true
        has_one :primary_contact, { class_name: "Contacts::Primary" }
      end
    RUBY
  end
end

# Holds stateless assertions and fixture operations.
module ReferenceTestSupport
  def self.assert_navigation(test, result)
    assert_route(test, result.fetch("routes").first)
    assert_navigation_content(test, result)
    assert_dynamic_route(test, result)
  end

  def self.assert_navigation_content(test, result)
    test.assert_equal "app/views/users/show.html.erb", result.fetch("views").first.fetch("path")
    test.assert_equal ["User"], result.fetch("models").map { |model| model.fetch("name") }
    test.assert_equal "Post", relation(result.fetch("associations"), "posts").fetch("target")
  end

  def self.assert_route(test, route)
    test.assert_equal ["GET", "/users/:id"], route.values_at("verb", "path")
  end

  def self.assert_dynamic_route(test, result)
    kinds = result.fetch("unresolved").map { |issue| issue.fetch("kind") }
    test.assert_includes kinds, "dynamic_route"
  end

  def self.assert_route_order(test, routes)
    actual = routes.map { |route| route.values_at("path", "verb", "controller", "action") }
    expected = [
      ["/admin/users/:id", "GET", "admin/users", "show"],
      ["/health", "GET", "health", "show"],
      ["/health", "GET", "health", "show"],
      ["/users/:id", "GET", "users", "show"],
      ["/users/:id", "PATCH", "users", "update"],
      ["/users/:id", "PUT", "users", "update"]
    ]
    test.assert_equal expected.sort, actual
  end

  def self.assert_repeatable(test, root)
    documents = 2.times.map { JSON.generate(RailsMap::Reference.new(root).result) }
    test.assert_equal documents.first, documents.last
  end

  def self.assert_associations(test, root, source)
    prepare_association_fixture(root, source)
    models, relations, issues = catalog_rows(root)
    assert_model(test, models)
    assert_targets(test, relations)
    assert_unknown_issue_count(test, issues)
  end

  def self.prepare_association_fixture(root, source)
    write_model(root, source)
    write_through_models(root)
  end

  def self.catalog_rows(root)
    RailsMap::ModelCatalog.new(root).call
  end

  def self.assert_model(test, models)
    name = models.find { |model| model.fetch("name") == "User" }.fetch("name")
    test.assert_equal "User", name
  end

  def self.assert_targets(test, relations)
    assert_direct_targets(test, relations)
    assert_unknown_targets(test, relations)
  end

  def self.assert_unknown_issue_count(test, issues)
    counts = issues.group_by { |issue| issue.fetch("kind") }.transform_values(&:count)
    test.assert_equal [5, 2], counts.values_at("dynamic_association_target", "dynamic_association_path")
  end

  def self.assert_direct_targets(test, relations)
    test.assert_equal "Person", relation(relations, "people").fetch("target")
    test.assert_equal "Child", relation(relations, "children").fetch("target")
    test.assert_equal "Writing::Article", relation(relations, "articles").fetch("target")
    test.assert_equal "Contacts::Primary", relation(relations, "primary_contact").fetch("target")
    assert_through_targets(test, relations)
  end

  def self.assert_through_targets(test, relations)
    test.assert_equal "Tag", relation(relations, "tags").fetch("target")
    test.assert_equal "User", relation(relations, "subscribers").fetch("target")
    test.assert_equal "User", relation(relations, "following").fetch("target")
  end

  def self.assert_unknown_targets(test, relations)
    test.assert_nil relation(relations, "members").fetch("target")
    test.assert_nil relation(relations, "attachable").fetch("target")
  end

  def self.relation(relations, name)
    relations.find { |item| item.fetch("name") == name }
  end

  def self.write_model(root, source)
    File.write(File.join(root, "app/models/links.rb"), source)
  end

  def self.write_through_models(root)
    File.write(File.join(root, "app/models/tagging.rb"), "class Tagging\n  belongs_to :tag\nend\n")
    File.write(File.join(root, "app/models/subscription.rb"), "class Subscription\n  belongs_to :user, class_name: \"User\"\nend\n")
    File.write(File.join(root, "app/models/relationship.rb"), "class Relationship\n  belongs_to :followed, class_name: \"User\"\nend\n")
    append_links_through_declarations(root)
  end

  def self.append_links_through_declarations(root)
    path = File.join(root, "app/models/links.rb")
    source = File.read(path).sub("has_many :tags, through: :taggings", "has_many :taggings, class_name: \"Tagging\"\n        has_many :tags, through: :taggings")
    source.sub!("has_many :subscribers, through: :subscriptions, source: :user",
      "has_many :subscriptions, class_name: \"Subscription\"\n        has_many :subscribers, through: :subscriptions, source: :user")
    source << "\nclass User\n  has_many :active_relationships, class_name: \"Relationship\"\n  has_many :following, through: :active_relationships, source: :followed\nend\n"
    File.write(path, source)
  end
end
