require "json"
require "minitest/autorun"
require "open3"
require_relative "cli_test_support"

# Checks explicit layouts and action-scoped render uncertainty at the CLI.
class RenderNavigationTest < Minitest::Test
  include CliTestSupport

  def test_literal_layout_and_response_options_are_not_dynamic_views
    assert_empty CliTestSupport.dynamic_render_lines(inspect_action("Admin::UsersController#response"))
    assert_empty CliTestSupport.dynamic_render_lines(inspect_action("Admin::UsersController#layout_only"))
  end

  def test_dynamic_renders_are_scoped_to_the_selected_action
    assert_equal [8], CliTestSupport.dynamic_render_lines(inspect_action("Admin::UsersController#dynamic"))
    result = inspect_action("Admin::UsersController#mixed_render")
    assert_equal [21], CliTestSupport.dynamic_render_lines(result)
    assert_equal ["app/views/shared/user.html.erb"], result.fetch("views").map { |row| row.fetch("path") }
  end

  def test_project_map_keeps_each_dynamic_render
    output, _error, status = run_cli("map")
    assert status.success?
    assert_equal [8, 21], CliTestSupport.dynamic_render_lines(JSON.parse(output))
  end

  private

end
