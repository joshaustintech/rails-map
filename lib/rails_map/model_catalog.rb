require "prism"
require_relative "source_support"

module RailsMap
  # Carries records collected from one or more model files.
  class CatalogRows < Struct.new(:models, :associations, :unresolved, keyword_init: true)
    def self.ordered(rows)
      models = SourceSupport.models(rows.flat_map(&:models))
      resolved, issues = AssociationGraph.new(rows.flat_map(&:associations)).resolve
      [models, SourceSupport.associations(resolved),
        SourceSupport.ordered_unresolved(rows.flat_map(&:unresolved) + issues)]
    end
  end

  # Resolves `through` associations after every model declaration is known.
  class AssociationGraph
    def initialize(records)
      @records = records
      @by_key = records.to_h { |record| [[record.fetch("model"), record.fetch("name")], record] }
      @resolved = {}
      @resolving = []
    end

    def resolve
      records = @records.map { |record| resolve_record(record) }
      [PublicAssociationRows.new(records).call, AssociationIssueCatalog.new(records).call]
    end

    private

    def resolve_record(record)
      key = record.values_at("model", "name")
      return @resolved[key] if @resolved.key?(key)
      return AssociationRecord.unresolved(record) if @resolving.include?(key)
      return remember(key, record) unless record["_through"]

      resolve_through(key, record)
    end

    def resolve_through(key, record)
      @resolving << key
      resolved = through_record(record)
      @resolving.pop
      remember(key, resolved)
    end

    def through_record(record)
      through = through_association(record)
      return AssociationRecord.unresolved(record) unless through
      target = source_target(record, resolve_record(through))
      AssociationRecord.with_target(record, target)
    end

    def through_association(record)
      @by_key[AssociationKeys.through(record)]
    end

    def source_target(record, through)
      name = record["_source"] || SourceSupport.singularize_association(record.fetch("name"))
      association = @by_key[AssociationKeys.source(through, name)]
      association ? resolve_record(association) : AssociationRecord.unresolved(record)
    end

    def remember(key, record)
      @resolved[key] = record
    end
  end

  # Creates model and association lookup keys for a through declaration.
  class AssociationKeys
    def self.through(record)
      [record.fetch("model"), record.fetch("_through")]
    end

    def self.source(through, name)
      [through["target"], name]
    end
  end

  # Applies public target changes to association records.
  class AssociationRecord
    def self.unresolved(record)
      record.merge("target" => nil, "confidence" => "unresolved")
    end

    def self.with_target(record, target)
      return unresolved(record) unless target["target"]

      record.merge("target" => target.fetch("target"), "confidence" => target.fetch("confidence"))
    end
  end

  # Builds public association rows without graph-only metadata.
  class PublicAssociationRows
    def initialize(records)
      @records = records
    end

    def call
      @records.map { |record| self.class.public_row(record) }
    end

    def self.public_row(record)
      record.reject { |key, _| key.start_with?("_") }
    end
  end

  # Reports unresolved targets and dynamic through paths after graph resolution.
  class AssociationIssueCatalog
    def initialize(records)
      @records = records
    end

    def call
      @records.flat_map { |record| self.class.issues_for(record) }
    end

    private

    def self.issues_for(record)
      static_path = !record.fetch("_dynamic_path", false)
      SourceSupport.association_issues(record, static_path)
    end
  end

  # Groups model declarations and their static association targets.
  class ModelCatalog
    def initialize(root)
      @root = File.realpath(root)
    end

    def call
      CatalogRows.ordered(model_files.map { |path| ModelFile.new(@root, path).call })
    end

    private

    def model_files
      SourceSupport.files(@root, "app/models").reject { |path| path.include?("/concerns/") }
    end

  end

  # Collects one model file and keeps its source errors with its declarations.
  class ModelFile
    def initialize(root, path)
      @root, @path = root, path
    end

    def call
      parsed = SourceSupport.parse(@path).last
      model = model_record
      declarations = association_declarations(parsed, model.fetch("name"))
      CatalogRows.new(models: [model], associations: declarations.filter_map(&:first),
        unresolved: declarations.flat_map(&:last) + syntax_errors(parsed))
    end

    private

    def model_record
      name = SourceSupport.camelize(SourceSupport.relative_path(@root, @path).delete_prefix("app/models/").delete_suffix(".rb"))
      { "name" => name, "source" => SourceSupport.evidence(@root, @path, 1) }
    end

    def association_declarations(parsed, model)
      SourceSupport.collect(parsed.value).filter_map do |node|
        next unless AssociationDeclaration.call?(node)

        AssociationDeclaration.new(@root, model, @path, node).result
      end
    end

    def syntax_errors(parsed)
      parsed.errors.map do |error|
        SourceSupport.unresolved(@root, "syntax_error", @path, error.location.start_line)
      end
    end
  end

  # Resolves one Rails association call without evaluating its arguments.
  class AssociationDeclaration
    KINDS = %w[belongs_to has_one has_many has_and_belongs_to_many].freeze

    def self.call?(node)
      node.is_a?(Prism::CallNode) && KINDS.include?(node.name.to_s)
    end

    def initialize(root, model, path, node)
      @root, @model, @path, @node = root, model, path, node
    end

    def result
      name = SourceSupport.static_value(SourceSupport.arguments(@node).first)
      return dynamic_name unless name.is_a?(String)

      target, confidence = target_for(name)
      declaration = record(name, target, confidence)
      [declaration, []]
    end

    private

    def dynamic_name
      [nil, SourceSupport.unresolved(@root, "dynamic_association", @path, @node.location.start_line)]
    end

    def record(name, target, confidence)
      { "model" => @model, "name" => name, "target" => target, "confidence" => confidence,
        "evidence" => SourceSupport.evidence(@root, @path, @node.location.start_line),
        "_through" => static_option("through"), "_source" => static_option("source"),
        "_dynamic_path" => SourceSupport.non_string_option?(@node, "through") }
    end

    def static_option(name)
      value = SourceSupport.option_value(@node, name)
      value if value.is_a?(String)
    end

    def target_for(name)
      return [nil, "unresolved"] if unknown_target?

      declared_target || conventional_target(name)
    end

    def declared_target
      class_name = SourceSupport.option_value(@node, "class_name")
      return [SourceSupport.class_name(class_name), "direct"] if class_name.is_a?(String)

      source_type = SourceSupport.option_value(@node, "source_type")
      [source_type, "direct"] if source_type.is_a?(String)
    end

    def conventional_target(name)
      source = SourceSupport.option_value(@node, "source") || name
      [SourceSupport.camelize(conventional_name(source)), "conventional"]
    end

    def conventional_name(name)
      %w[belongs_to has_one].include?(@node.name.to_s) ? name : SourceSupport.singularize_association(name)
    end


    def unknown_target?
      SourceSupport.dynamic_options?(@node) || SourceSupport.unknown_polymorphic?(@node) ||
        %w[class_name source source_type through].any? { |name| SourceSupport.non_string_option?(@node, name) }
    end

  end
end
