require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/rails_map/route_catalog"

# Checks static paths, targets, nesting, and uncertainty reports.
class RouteCatalogTest < Minitest::Test
  def test_reads_conventional_namespaced_and_nested_routes
    RouteCatalogTestSupport.assert_conventional(self)
  end

  def test_reads_explicit_routes_and_marks_dynamic_routes
    RouteCatalogTestSupport.assert_explicit(self)
  end

  def test_marks_dynamic_scope_values_and_skips_routes_with_unknown_prefixes
    routes, issues = RouteCatalogTestSupport.read(<<~'RUBY')
      Rails.application.routes.draw do
        scope path: "#{prefix}/:name" do
          get "activity", to: "groups#show"
        end
      end
    RUBY

    assert_empty routes
    RouteCatalogTestSupport.assert_issue(self, issues, ["dynamic_route", 2])
  end

  def test_marks_dynamic_local_values_at_their_assignment
    _, issues = RouteCatalogTestSupport.read(<<~'RUBY')
      Rails.application.routes.draw do
        prefix = if Rails.env.production?
          Rails.configuration.relative_url_root
        else
          "/"
        end
        get "#{prefix}/health", to: "health#show"
      end
    RUBY

    RouteCatalogTestSupport.assert_issue(self, issues, ["dynamic_route", 2])
  end

  def test_points_to_generator_and_option_source_lines
    _, issues = RouteCatalogTestSupport.read(<<~'RUBY')
      Rails.application.routes.draw do
        {
          "home" => "pages#show"
        }.each do |path, target|
          get path, to: target
        end
        root to: "pages#show",
             constraints: RequestConstraint.new("home")
      end
    RUBY

    rows = issues.map { |issue| [issue.fetch("kind"), issue.dig("evidence", "line")] }
    assert_includes rows, ["unsupported_route_generator", 4]
    assert_includes rows, ["unsupported_route_option", 8]
  end
end

# Keeps route examples and their assertions outside test methods.
module RouteCatalogTestSupport
  def self.assert_issue(test, issues, expected)
    rows = issues.map { |issue| [issue.fetch("kind"), issue.dig("evidence", "line")] }
    test.assert_includes rows, expected
  end

  def self.assert_conventional(test)
    routes, unresolved = read(<<~RUBY)
      Rails.application.routes.draw do
        namespace :admin do
          resources :users, only: [:show] do
            resources :posts, only: [:index]
            get :search, on: :collection
            member do
              get :preview, to: "users#preview"
              get :following, :followers
            end
          end
        end
      end
    RUBY
    assert_rows(test, routes, {
      keys: %w[controller action path],
      expected: "conventional"
    })
    test.assert_empty(unresolved)
  end

  def self.assert_explicit(test)
    routes, unresolved = read(<<~RUBY)
      Rails.application.routes.draw do
        scope path: "/api", module: :v1 do
          get "/users/:id", to: "users#show"
          get "/legacy" => "legacy#show"
          get "old-users", :to => "users#index"
          get "users", controller: "users", action: :index
          match "search", to: "search#index", via: [:get, :post]
          get ENV.fetch("PATH"), to: "pages#show"
        end
        scope "admin", module: :admin do
          root "dashboard#show"
        end
        root "pages#home"
        if Rails.env.production?
          get "health", to: "health#show"
        end
      end
    RUBY
    assert_rows(test, routes, {
      keys: %w[verb path controller action],
      expected: "explicit"
    })
    assert_search_verbs(test, routes)
    assert_dynamic_issue_count(test, unresolved)
  end

  def self.assert_rows(test, routes, specification)
    rows = routes.map { |route| route.values_at(*specification[:keys]) }
    expected = JSON.parse(File.read(File.join(File.expand_path("..", __dir__), "fixtures/route_catalog_expectations.json")))
      .fetch(specification[:expected])
    expected.each { |row| test.assert_includes(rows, row) }
  end

  def self.assert_search_verbs(test, routes)
    matches = routes.select { |route| route["path"] == "/api/search" }
    test.assert_equal 2, matches.length
  end

  def self.assert_dynamic_issue_count(test, issues)
    count = issues.count { |issue| issue["kind"] == "dynamic_route" }
    test.assert_equal 2, count
  end

  def self.read(source)
    with_root do |root|
      File.write(File.join(root, "config/routes.rb"), source)
      RailsMap::RouteCatalog.new(root).call
    end
  end

  def self.with_root
    root = Dir.mktmpdir("rails-map-routes-")
    FileUtils.mkdir_p(File.join(root, "config"))
    yield root
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end
end
