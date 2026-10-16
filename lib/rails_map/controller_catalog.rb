require_relative "source_support"

module RailsMap
  # Carries controller action, view, and uncertainty rows from one file.
  class ControllerRows < Struct.new(:actions, :views, :unresolved, keyword_init: true)
    def self.combine(scans)
      actions = scans.flat_map(&:actions)
      views = scans.flat_map(&:views)
      [SourceSupport.sorted(actions, &method(:action_key)),
        SourceSupport.sorted(views, &method(:view_key)), scans.flat_map(&:unresolved)]
    end

    def self.action_key(row)
      row.values_at("controller", "action")
    end

    def self.view_key(row)
      row.values_at("controller", "action", "path")
    end
  end

  # Finds public controller actions and their navigation evidence.
  class ControllerCatalog
    def initialize(root, model_names)
      @root = File.realpath(root)
      @model_names = model_names
    end

    def call
      ControllerRows.combine(controller_files.map { |path| ControllerFile.new(@root, @model_names, path).call })
    end

    private

    def controller_files
      SourceSupport.files(@root, "app/controllers").select { |path| path.end_with?("_controller.rb") }
    end
  end

  # Analyzes one controller source file.
  class ControllerFile
    def initialize(root, model_names, path)
      @root, @model_names, @path = root, model_names, path
    end

    def call
      source, parsed = SourceSupport.parse(@path)
      actions = actions_in(parsed, ActionVisibility.public_lines(source))
      view_scans = actions.map(&:view_scan)
      ControllerRows.new(actions: actions.map(&:to_h), views: view_scans.flat_map(&:first),
        unresolved: view_scans.flat_map(&:last) + syntax_errors(parsed))
    end

    private

    def actions_in(parsed, public_lines)
      SourceSupport.collect(parsed.value).filter_map do |node|
        next unless node.is_a?(Prism::DefNode) && !node.receiver && public_lines.include?(node.location.start_line)

        ControllerAction.new(@root, @model_names, @path, node)
      end
    end

    def syntax_errors(parsed)
      parsed.errors.map do |error|
        SourceSupport.unresolved(@root, "syntax_error", @path, error.location.start_line)
      end
    end
  end

  # Reads the public and private declarations that control Rails actions.
  class ActionVisibility
    VISIBILITY = { "public" => true, "private" => false, "protected" => false }.freeze

    def self.public_lines(source)
      visibility = new
      source.lines.each_with_index.filter_map { |line, index| visibility.action_line(line, index) }
    end

    def initialize
      @visible = true
    end

    def action_line(line, index)
      update_visibility(line.strip)
      index + 1 if @visible && line.match?(/^\s*def\s+\w+/)
    end

    private

    def update_visibility(value)
      @visible = VISIBILITY.fetch(value, @visible)
    end
  end

  # Describes one controller action and its source-level model references.
  class ControllerAction
    def initialize(root, model_names, path, node)
      @context = ControllerContext.new(root: root, model_names: model_names, path: path)
      @node = node
    end

    def to_h
      { "controller" => @context.controller, "route_controller" => @context.route_controller,
        "action" => @node.name.to_s, "source" => @context.evidence(@node.location.start_line),
        "models" => model_names }
    end

    def view_scan
      ViewCatalog.new(@context.root, to_h, @node, @context.path).call
    end

    private

    def model_names
      SourceSupport.collect(@node).filter_map do |node|
        name = self.class.constant_name(node)
        name if @context.model_names.include?(name)
      end.uniq.sort
    end

    def self.constant_name(node)
      return node.full_name.to_s if node.is_a?(Prism::ConstantPathNode)
      return node.name.to_s if node.is_a?(Prism::ConstantReadNode)

      nil
    end
  end

  # Supplies source and controller names to one action.
  class ControllerContext < Struct.new(:root, :model_names, :path, keyword_init: true)
    def controller
      ControllerNaming.from_path(root, path).first
    end

    def route_controller
      ControllerNaming.from_path(root, path).last
    end

    def evidence(line)
      SourceSupport.evidence(root, path, line)
    end
  end

  # Converts controller filenames to Rails constant and route names.
  class ControllerNaming
    def self.from_path(root, path)
      relative = path.delete_prefix("#{root}/app/controllers/")
      route = relative.delete_suffix("_controller.rb")
      ["#{SourceSupport.camelize(route.delete_suffix(".rb"))}Controller", route]
    end
  end

  # Finds explicit and conventional templates for one action.
  class ViewCatalog
    EXTENSIONS = %w[html.erb turbo_stream.erb json.jbuilder html.builder text.erb].freeze

    def initialize(root, action, method_node, source_path)
      @root, @action, @method_node, @source_path = root, action, method_node, source_path
    end

    def call
      explicit, issues = explicit_views
      [explicit.empty? ? implicit_views : explicit, issues]
    end

    private

    def explicit_views
      scans = render_calls.map { |node| render_scan(node) }
      [scans.flat_map(&:first), scans.flat_map(&:last)]
    end

    def render_calls
      SourceSupport.collect(@method_node).select { |node| RenderCall.call?(node) }
    end

    def render_scan(node)
      render = RenderCall.new(node)
      target = render.target
      return [rows_for(target, node.location.start_line), []] if target
      return [[], [dynamic_render(node)]] if render.dynamic?

      [[], []]
    end

    def rows_for(target, line)
      base = target.delete_prefix("/")
      base = "#{@action.fetch("route_controller")}/#{base}" unless base.include?("/")
      EXTENSIONS.filter_map { |extension| view_record("#{base}.#{extension}", line, "direct") }
    end

    def implicit_views
      base = "#{@action.fetch("route_controller")}/#{@action.fetch("action")}"
      EXTENSIONS.filter_map do |extension|
        path = "app/views/#{base}.#{extension}"
        view_record(path, @action.fetch("source").fetch("line"), "conventional")
      end
    end

    def view_record(path, line, confidence)
      return unless File.file?(File.join(@root, "app/views/#{path.delete_prefix("app/views/")}"))

      { "controller" => @action.fetch("controller"), "action" => @action.fetch("action"),
        "path" => path.start_with?("app/views/") ? path : "app/views/#{path}",
        "confidence" => confidence, "evidence" => SourceSupport.evidence(@root, @source_path, line) }
    end

    def dynamic_render(node)
      SourceSupport.unresolved(@root, "dynamic_render", @source_path, node.location.start_line)
    end
  end

  # Reads the statically useful parts of one render call.
  class RenderCall
    RESPONSE_OPTIONS = %w[json plain html body file inline].freeze

    def initialize(node)
      @node = node
      @options = SourceSupport.keyword_options(node)
      @arguments = SourceSupport.arguments(node)
    end

    def self.call?(node)
      node.is_a?(Prism::CallNode) && node.name == :render
    end

    def target
      target_option || positional_target unless response_only?
    end

    def dynamic?
      return true if view_option?
      return false if response_only?

      !@arguments.empty?
    end

    private

    def target_option
      @options["template"] || @options["partial"] if view_option?
    end

    def positional_target
      value = SourceSupport.static_value(@arguments.first)
      value if value.is_a?(String)
    end

    def view_option?
      @options.key?("template") || @options.key?("partial")
    end

    def response_only?
      @options.keys.any? { |key| RESPONSE_OPTIONS.include?(key) }
    end
  end
end
