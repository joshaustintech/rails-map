require "json"
require "prism"
require_relative "source_support"
require_relative "model_catalog"
require_relative "controller_catalog"
require_relative "route_catalog"

module RailsMap
  # Combines the development catalogs into one stable navigation document.
  class Reference
    def initialize(root)
      @root = File.realpath(root)
    end

    def result(target = nil)
      snapshot = NavigationSnapshot.read(@root)
      selection = target ? ActionSelection.new(snapshot, target) : ProjectSelection.new(snapshot)
      ResultDocument.new(rows: selection.rows).to_h
    end
  end

  # Holds the complete catalog output before an optional target filter.
  class NavigationSnapshot < Struct.new(:root, :actions, :views, :routes, :models, :associations, :unresolved,
                                         keyword_init: true)
    def self.read(root)
      models, associations, model_issues = ModelCatalog.new(root).call
      actions, views, controller_issues = ControllerCatalog.new(root, model_names(models)).call
      routes, route_issues = RouteCatalog.new(root).call
      new(root: root, actions: actions, views: views, routes: routes, models: models, associations: associations,
        unresolved: model_issues + controller_issues + route_issues)
    end

    def self.model_names(models)
      models.map { |model| model.fetch("name") }
    end
  end

  # Builds a result for an unfiltered project map.
  class ProjectSelection
    def initialize(snapshot)
      @snapshot = snapshot
    end

    def rows
      actions = @snapshot.actions
      filter = ActionFilter.new(actions)
      SelectedRows.new(actions: actions, routes: filter.routes(@snapshot.routes),
        views: filter.views(@snapshot.views), models: @snapshot.models,
        associations: @snapshot.associations, unresolved: @snapshot.unresolved)
    end
  end

  # Selects only rows connected to one controller action.
  class ActionSelection
    def initialize(snapshot, target)
      @snapshot, @target = snapshot, target
      @actions = matching_actions
      @filter = ActionFilter.new(@actions)
    end

    def rows
      SelectedRows.new(actions: @actions, routes: selected_routes, views: selected_views,
        models: selected_models, associations: selected_associations, unresolved: selected_issues)
    end

    private

    def matching_actions
      controller, action = @target.split("#", 2)
      @snapshot.actions.select { |row| row.values_at("controller", "action") == [controller, action] }
    end

    def selected_routes
      @filter.routes(@snapshot.routes)
    end

    def selected_views
      @filter.views(@snapshot.views)
    end

    def selected_models
      names = action_model_names + ReferencedModels.in_views(@snapshot.root, selected_views)
      @snapshot.models.select { |model| names.include?(model.fetch("name")) }
    end

    def action_model_names
      @actions.flat_map { |action| action.fetch("models") }.uniq
    end

    def selected_associations
      names = selected_models.map { |model| model.fetch("name") }
      @snapshot.associations.select { |association| names.include?(association.fetch("model")) }
    end

    def selected_issues
      paths = ReferencePaths.in(@actions, selected_views, selected_models)
      @snapshot.unresolved.select { |issue| paths.include?(issue.dig("evidence", "path")) }
    end
  end

  # Filters route and view rows by selected action keys.
  class ActionFilter
    def initialize(actions)
      @actions = actions
    end

    def routes(rows)
      filter(rows, "route_controller", "controller")
    end

    def views(rows)
      filter(rows, "controller", "controller")
    end

    private

    def filter(rows, action_key, row_key)
      keys = @actions.map { |action| action.values_at(action_key, "action") }
      rows.select { |row| keys.include?(row.values_at(row_key, "action")) }
    end
  end

  # Collects model constants referenced by selected view templates.
  class ReferencedModels
    def self.in_views(root, views)
      paths = views.filter_map do |view|
        path = File.join(root, view.fetch("path"))
        path if File.file?(path)
      end
      paths.flat_map { |path| in_file(path) }.uniq
    end

    def self.in_file(path)
      erb_code(path).flat_map { |source| constants(source) }.uniq
    end

    def self.erb_code(path)
      source = File.read(path)
      fragments = source.scan(/<%(?!#)(?:=)?(.*?)%>/m).flatten
      fragments.empty? ? [source] : fragments
    end

    def self.constants(source)
      parsed = Prism.parse(source)
      SourceSupport.collect(parsed.value).filter_map do |node|
        node.name.to_s if node.is_a?(Prism::ConstantReadNode)
      end
    end
  end

  # Collects source paths used to scope uncertainty to an action.
  class ReferencePaths
    def self.in(actions, views, models)
      (paths(actions, "source") + paths(views, "evidence") + paths(models, "source") + ["config/routes.rb"]).uniq
    end

    def self.paths(rows, field)
      rows.map { |row| row.dig(field, "path") }
    end
  end

  # Holds the rows that appear in the output document.
  class SelectedRows < Struct.new(:actions, :routes, :views, :models, :associations, :unresolved, keyword_init: true)
  end

  # Emits the stable JSON object key order and unresolved row order.
  class ResultDocument < Struct.new(:rows, keyword_init: true)
    def to_h
      {
        "schema_version" => 1,
        "actions" => rows.actions,
        "routes" => rows.routes,
        "views" => rows.views,
        "models" => rows.models,
        "associations" => rows.associations,
        "unresolved" => ordered_issues
      }
    end

    private

    def ordered_issues
      ReferenceOrdering.issues(rows.unresolved)
    end
  end

  # Sorts and removes duplicate uncertainty rows.
  class ReferenceOrdering
    def self.issues(rows)
      rows.uniq.sort_by { |row| row.fetch("evidence").values_at("path", "line") + [row.fetch("kind")] }
    end
  end
end
