require "prism"

module RailsMap
  # Provides the source facts shared by the reference catalogs.
  module SourceSupport
    IRREGULAR_ASSOCIATIONS = { "children" => "child", "feet" => "foot", "geese" => "goose", "men" => "man",
      "mice" => "mouse", "people" => "person", "teeth" => "tooth", "women" => "woman" }.freeze
    UNCOUNTABLE_ASSOCIATIONS = %w[equipment information rice money species series].freeze
    # Collects syntax nodes used by static navigation analysis.
    class Collector < Prism::Visitor
      # Collects only the syntax nodes used by the static catalogs.
      attr_reader :nodes

      def initialize
        @nodes = []
      end

      def visit_call_node(node)
        @nodes << node
        super
      end

      def visit_def_node(node)
        @nodes << node
        super
      end

      def visit_constant_read_node(node)
        @nodes << node
        super
      end

      def visit_constant_path_node(node)
        @nodes << node
        super
      end
    end

    def self.collect(root)
      collector = Collector.new
      root.accept(collector)
      collector.nodes
    end

    def self.parse(path)
      source = File.read(path)
      [source, Prism.parse(source)]
    end

    def self.evidence(root, path, line)
      { "path" => relative_path(root, path), "line" => line }
    end

    def self.relative_path(root, path)
      path.delete_prefix("#{root}/")
    end

    def self.files(root, directory)
      Dir.glob(File.join(root, directory, "**", "*.rb")).sort
    end

    def self.sorted(records, &key)
      records.sort_by(&key)
    end

    def self.unresolved_key(record)
      record.fetch("evidence").values_at("path", "line") + [record.fetch("kind")]
    end

    def self.models(records)
      sorted(records) { |record| record.fetch("name") }
    end

    def self.associations(records)
      sorted(records) { |record| record.values_at("model", "name") }
    end

    def self.ordered_unresolved(records)
      sorted(records, &method(:unresolved_key))
    end

    def self.static_value(node)
      case node
      when Prism::StringNode, Prism::SymbolNode then node.unescaped
      when Prism::TrueNode then true
      when Prism::FalseNode then false
      when Prism::ArrayNode then node.elements.map { |item| static_value(item) }
      end
    end

    def self.arguments(call)
      call.arguments&.arguments || []
    end

    def self.positional_arguments(call)
      arguments(call).reject do |argument|
        argument.is_a?(Prism::KeywordHashNode) || argument.is_a?(Prism::HashNode)
      end
    end

    def self.keyword_options(call)
      hash = options_hash(call)
      hash ? option_pairs(hash.elements) : {}
    end

    def self.option_pairs(elements)
      elements.each_with_object({}) do |element, options|
        next unless element.is_a?(Prism::AssocNode)

        key = static_value(element.key)
        options[key] = static_value(element.value) if key
      end
    end

    def self.option_node(call, name)
      hash = options_hash(call)
      hash&.elements&.find do |element|
        element.is_a?(Prism::AssocNode) && static_value(element.key) == name
      end
    end

    def self.option_value(call, name)
      node = option_node(call, name)
      static_value(node.value) if node
    end

    def self.non_string_option?(call, name)
      node = option_node(call, name)
      !!node && !static_value(node.value).is_a?(String)
    end

    def self.unknown_polymorphic?(call)
      node = option_node(call, "polymorphic")
      node && static_value(node.value) != false && !option_value(call, "source_type").is_a?(String)
    end

    def self.association_issues(record, static_path)
      evidence = record.fetch("evidence")
      target_issues = { "unresolved" => [issue("dynamic_association_target", evidence)] }
      path_issues = { false => [issue("dynamic_association_path", evidence)] }
      target_issues.fetch(record.fetch("confidence"), []) + path_issues.fetch(static_path, [])
    end

    def self.issue(kind, evidence)
      { "kind" => kind, "evidence" => evidence }
    end

    def self.dynamic_options?(call)
      hash = options_hash(call)
      hash&.elements&.any? { |element| element.is_a?(Prism::AssocSplatNode) } || false
    end

    def self.unresolved(root, kind, *location)
      path, line = location.length == 1 ? location.first.values_at("path", "line") : location
      { "kind" => kind, "evidence" => evidence(root, path, line) }
    end

    def self.camelize(value)
      value.split("/").map { |part| part.split("_").map(&:capitalize).join }.join("::")
    end

    def self.singularize_association(value)
      return value if UNCOUNTABLE_ASSOCIATIONS.include?(value)
      return IRREGULAR_ASSOCIATIONS.fetch(value) if IRREGULAR_ASSOCIATIONS.key?(value)

      singular_suffix(value)
    end

    def self.singular_suffix(value)
      return "#{value[0...-3]}y" if value.end_with?("ies")
      return value[0...-1] if value.end_with?("s") && !value.end_with?("ss")
      value
    end

    def self.class_name(value)
      value.delete_prefix("::") if value.is_a?(String)
    end

    def self.normalize_path(value)
      normalized = "/#{value}".gsub(%r{/+}, "/")
      normalized == "/" ? normalized : normalized.sub(%r{/$}, "")
    end

    def self.options_hash(call)
      call.arguments&.arguments&.find do |argument|
        argument.is_a?(Prism::KeywordHashNode) || argument.is_a?(Prism::HashNode)
      end
    end
  end
end
