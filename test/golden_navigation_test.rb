require "json"
require "minitest/autorun"
require "open3"

# Checks CLI navigation evidence against small offline tasks.
class GoldenNavigationTest < Minitest::Test
  def test_navigation_tasks
    tasks.each { |task| assert_task(task) }
  end

  private

  def tasks
    JSON.parse(File.read(File.join(root, "fixtures/navigation_tasks.json"))).fetch("tasks")
  end

  def assert_task(task)
    assert_expectations(run_task(task), task)
  end

  def run_task(task)
    command, target = task.values_at("command", "target")
    output, error, status = Open3.capture3(File.join(root, "build/rails-map"),
      *(command == "map" ? ["map"] : ["inspect", target]), "--root",
      File.join(root, "fixtures/rails61"), "--json")
    assert status.success?, error
    JSON.parse(output)
  end

  def assert_expectations(result, task)
    self.class.requirements(task).each do |requirement, expected|
      assert_requirement(result, requirement, expected)
    end
  end

  def assert_requirement(result, requirement, expected)
    collection, fields, values = requirement.values_at("collection", "fields", "values")
    actual = result.fetch(collection).any? { |row| row.values_at(*fields) == values }
    assert_equal expected, actual, "#{expected ? "missing" : "unexpected"} #{values} in #{collection}"
  end

  def root
    File.expand_path("..", __dir__)
  end

  def self.requirements(task)
    required, forbidden = task.values_at("requires", "forbids")
    requirements = required.map { |requirement| [requirement, true] } +
      (forbidden || []).map { |requirement| [requirement, false] }
    requirements
  end
end
