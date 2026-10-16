require "json"
require "minitest/autorun"
require "open3"

# Checks the compiled command boundary and user-visible errors.
class CliTest < Minitest::Test
  def test_inspect_returns_json_for_known_action
    output, error, status = run_cli("inspect", "UsersController#show")

    assert status.success?, error
    assert_equal 1, JSON.parse(output).fetch("schema_version")
  end

  def test_invalid_root_returns_error
    _output, error, status = run_cli("map", root: File.join(fixture, "missing"))

    assert_equal 2, status.exitstatus
    assert_includes error, "root is not a directory"
  end

  def test_namespaced_action_maps_explicit_view_and_dynamic_render
    output, error, status = run_cli("inspect", "Admin::UsersController#show")
    assert_namespaced_navigation(output, error, status)
  end

  def test_inspect_rejects_missing_and_malformed_targets
    assert_inspect_error("MissingController#show", 1, "action not found")
    assert_inspect_error("UsersController", 2, "inspect requires Controller#action")
  end

  def test_parenthesized_response_render_is_not_dynamic_but_layout_is
    response = inspect_action("Admin::UsersController#response")
    layout = inspect_action("Admin::UsersController#layout_only")
    test_class = self.class

    assert_equal [false, true], [test_class.dynamic_render_lines(response).include?(13),
                                 test_class.dynamic_render_lines(layout).include?(16)]
  end

  def test_association_words_in_comments_are_ignored
    result = inspect_action("UsersController#show")

    refute_includes result.fetch("associations").map { |row| row.fetch("name") }, "ghosts"
  end

  def test_conditional_route_is_unresolved_at_its_condition
    result = JSON.parse(run_cli("map").first)
    assert result.fetch("unresolved").any? do |entry|
      entry.fetch("kind") == "dynamic_route" && entry.dig("evidence", "line") == 6
    end
    refute_includes result.fetch("routes").map { |route| route.fetch("path") }, "/conditional"
  end

  private

  def run_cli(*arguments, root: fixture)
    Open3.capture3(File.join(self.root, "build/rails-map"), *arguments, "--root", root, "--json")
  end

  def inspect_action(target)
    output, error, status = run_cli("inspect", target)
    assert status.success?, error
    JSON.parse(output)
  end

  def self.dynamic_render_lines(result)
    result.fetch("unresolved").select { |issue| issue.fetch("kind") == "dynamic_render" }
      .map { |issue| issue.dig("evidence", "line") }
  end

  def root
    File.expand_path("..", __dir__)
  end

  def fixture
    File.join(root, "fixtures/rails61")
  end

  def assert_namespaced_navigation(output, error, status)
    result = JSON.parse(output)
    assert status.success?, error
    assert_navigation_rows(result)
    assert_dynamic_render(result)
  end

  def assert_navigation_rows(result)
    assert_includes result.fetch("routes").map { |route| route.fetch("controller") }, "admin/users"
    assert_equal "app/views/shared/user.html.erb", result.fetch("views").first.fetch("path")
  end

  def assert_dynamic_render(result)
    assert_includes result.fetch("unresolved").map { |issue| issue.fetch("kind") }, "dynamic_render"
  end

  def assert_inspect_error(target, exit_code, message)
    _output, error, status = run_cli("inspect", target)
    assert_equal exit_code, status.exitstatus
    assert_includes error, message
  end
end
