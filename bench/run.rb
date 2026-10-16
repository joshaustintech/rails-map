#!/usr/bin/env ruby

require "json"
require "open3"
require "optparse"
require "rbconfig"

ROOT = File.expand_path("..", __dir__)
LOCK = File.join(__dir__, "repositories.lock")
REFERENCE = File.join(ROOT, "bin/rails-map-reference")
COMPILED = File.join(ROOT, "build/rails-map")
RUNS = 30

options = { baseline_only: false, record_baseline: false }
OptionParser.new do |parser|
  parser.banner = "Usage: ruby bench/run.rb [--baseline-only]"
  parser.on("--baseline-only", "Measure CRuby + Prism only") { options[:baseline_only] = true }
  parser.on("--record-baseline", "Write fresh CRuby + Prism medians to bench/baseline.json") do
    options[:baseline_only] = true
    options[:record_baseline] = true
  end
end.parse!

def fail_with(message)
  warn "rails-map benchmark: #{message}"
  exit 1
end

def read_repositories(lock_path, corpus_root)
  File.readlines(lock_path, chomp: true).filter_map do |line|
    next if line.empty? || line.start_with?("#")

    name, _url, sha, _paths, target = line.split("|", 5).map(&:strip)
    root = File.join(corpus_root, name)
    fail_with("missing checkout #{root}") unless File.directory?(root)

    actual = `git -C #{Shellwords.escape(root)} rev-parse HEAD 2>/dev/null`.strip
    fail_with("#{name} is at #{actual}, expected #{sha}") unless actual == sha
    fail_with("#{name} lock entry needs Controller#action target") if target.to_s.empty?

    [name, root, target]
  end
end

def canonical_json(text)
  JSON.generate(sort_hashes(JSON.parse(text)))
rescue JSON::ParserError => error
  fail_with("CLI did not emit valid JSON: #{error.message}")
end

def sort_hashes(value)
  case value
  when Hash
    value.keys.sort.each_with_object({}) { |key, result| result[key] = sort_hashes(value.fetch(key)) }
  when Array
    value.map { |item| sort_hashes(item) }.sort_by { |item| JSON.generate(item) }
  else
    value
  end
end

def invoke(command, root)
  output, = timed_process(command, root)

  canonical_json(output)
end

def timed_process(command, root)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  output, error, status = Open3.capture3(*command, "--root", root, "--json")
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  fail_with("#{command.join(' ')} failed (#{status.exitstatus}): #{error}") unless status.success?

  [output, elapsed, error]
end

def measure(command, root, expected, warmup_output)
  fail_with("warm-up output differs from expected output") unless canonical_json(warmup_output) == expected
  timings = Array.new(RUNS) do
    output, elapsed, = timed_process(command, root)
    fail_with("semantic output differs between implementations") unless canonical_json(output) == expected

    elapsed
  end
  sorted = timings.sort
  (sorted[(RUNS - 1) / 2] + sorted[RUNS / 2]) / 2 * 1000.0
end

def locked_commits(lock_path)
  File.readlines(lock_path, chomp: true).filter_map do |line|
    next if line.empty? || line.start_with?("#")

    name, _url, sha = line.split("|", 4).map(&:strip)
    [name, sha]
  end.to_h
end

def spinel_version
  return ENV.fetch("SPINEL_VERSION") if ENV.key?("SPINEL_VERSION")

  command = ENV.fetch("SPINEL", "spinel")
  output, _error, status = Open3.capture3(command, "--version")
  status.success? ? output.lines.first.to_s.strip : "unknown"
end

def save_baseline(results, commits)
  baseline = {
    "measured_on" => Date.today.iso8601,
    "warmup_runs" => 1,
    "timed_runs" => RUNS,
    "compile_time_excluded" => true,
    "versions" => {
      "cruby" => RUBY_VERSION,
      "prism" => Prism::VERSION,
      "spinel" => spinel_version
    },
    "repositories" => results.to_h do |name, commands|
      repo = { "commit" => commits.fetch(name) }
      commands.each do |command, measurements|
        repo["#{command}_cruby_prism_median_ms"] = measurements.fetch("cruby_prism_median_ms")
      end
      [name, repo]
    end
  }
  File.write(File.join(__dir__, "baseline.json"), JSON.pretty_generate(baseline) + "\n")
end

require "shellwords"
require "date"
require "prism"
corpus = ENV.fetch("RAILS_MAP_CORPUS", File.join(ROOT, "bench/corpus"))
repositories = read_repositories(LOCK, corpus)
fail_with("no locked repositories") if repositories.empty?
fail_with("compiled CLI missing at #{COMPILED}") if !options[:baseline_only] && !File.executable?(COMPILED)

puts "CRuby #{RUBY_VERSION}; Prism #{Prism::VERSION}; Spinel #{spinel_version}"
puts "Runs: 1 warm-up + #{RUNS} timed process runs; JSON parsing and compile time excluded"
puts "Corpus: #{corpus}"

results = {}
repositories.each do |name, root, target|
  results[name] = {}
  { "map" => ["map"], "inspect" => ["inspect", target] }.each do |label, arguments|
    reference_command = [RbConfig.ruby, REFERENCE, *arguments]
    reference_output = invoke(reference_command, root)
    reference_median = measure(reference_command, root, reference_output, reference_output)
    if options[:baseline_only]
      results[name][label] = { "cruby_prism_median_ms" => reference_median.round(3) }
      puts "#{name} #{label}: CRuby+Prism median #{reference_median.round(3)} ms"
      next
    end

    compiled_command = [COMPILED, *arguments]
    compiled_output = invoke(compiled_command, root)
    fail_with("#{name} #{label}: compiled output differs from CRuby + Prism") unless compiled_output == reference_output

    compiled_median = measure(compiled_command, root, reference_output, compiled_output)
    ratio = compiled_median / reference_median
    results[name][label] = {
      "cruby_prism_median_ms" => reference_median.round(3),
      "spinel_median_ms" => compiled_median.round(3),
      "spinel_to_reference_ratio" => ratio.round(4)
    }
    puts "#{name} #{label}: reference #{reference_median.round(3)} ms; Spinel #{compiled_median.round(3)} ms; ratio #{ratio.round(4)}"
    fail_with("#{name} #{label}: Spinel must be at most 90% of reference median") if ratio > 0.9
  end
end

puts JSON.pretty_generate(results)
save_baseline(results, locked_commits(LOCK)) if options[:record_baseline]
