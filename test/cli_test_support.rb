require "json"
require "open3"

# Shares compiled CLI setup and action inspection between navigation tests.
module CliTestSupport
  private

  def run_cli(*arguments, root: fixture)
    Open3.capture3(File.join(root_path, "build/rails-map"), *arguments, "--root", root, "--json")
  end

  def inspect_action(target)
    output, error, status = run_cli("inspect", target)
    assert status.success?, error
    JSON.parse(output)
  end

  def root_path
    File.expand_path("..", __dir__)
  end

  def fixture
    File.join(root_path, "fixtures/rails61")
  end

  def self.dynamic_render_lines(result)
    result.fetch("unresolved").select { |issue| issue.fetch("kind") == "dynamic_render" }
      .map { |issue| issue.dig("evidence", "line") }
  end
end
