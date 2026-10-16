require "json"
require "minitest/autorun"
require "open3"
require_relative "cli_test_support"

# Checks the compiled command boundary and user-visible errors.
class CliTest < Minitest::Test
  include CliTestSupport

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

  def assert_namespaced_navigation(output, error, status)
    result = JSON.parse(output)
    assert status.success?, error
    assert_navigation_rows(result)
    assert_empty CliTestSupport.dynamic_render_lines(result)
  end

  def assert_navigation_rows(result)
    assert_includes result.fetch("routes").map { |route| route.fetch("controller") }, "admin/users"
    assert_equal "app/views/shared/user.html.erb", result.fetch("views").first.fetch("path")
  end

  def assert_inspect_error(target, exit_code, message)
    _output, error, status = run_cli("inspect", target)
    assert_equal exit_code, status.exitstatus
    assert_includes error, message
  end
end
