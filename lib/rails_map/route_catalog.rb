require "prism"
require_relative "source_support"

module RailsMap
  # Reads static Rails route declarations.
  class RouteCatalog
    def initialize(root)
      @root = File.realpath(root)
    end

    def call
      RouteFile.new(@root).call
    end
  end

  # Holds route parsing results and their source evidence.
  class RouteFile
    def initialize(root)
      @root = root
      @path = File.join(root, "config/routes.rb")
      @routes = []
      @issues = []
    end

    def call
      return [[], []] unless File.file?(@path)

      visit_routes
      sorted_result
    end

    def add(route)
      @routes << route.merge("evidence" => SourceSupport.evidence(@root, @path, route.delete("line")))
    end

    def issue(kind, line)
      @issues << SourceSupport.unresolved(@root, kind, @path, line)
    end

    private

    def visit_routes
      syntax = parse_syntax
      RouteDynamicAssignmentScanner.new(self).call(syntax)
      RouteWalker.new(self).walk(syntax.statements, RouteScope.empty)
    end

    def parse_syntax
      parsed = Prism.parse(File.read(@path))
      parsed.errors.each { |error| issue("syntax_error", error.location.start_line) }
      parsed.value
    end

    def sorted_result
      [sorted_routes, sorted_issues]
    end

    def sorted_routes
      @routes.sort_by(&RouteOrdering.method(:key))
    end

    def sorted_issues
      @issues.uniq.sort_by { |issue| RouteSyntax.issue_key(issue) }
    end
  end

  # Adds source evidence as a deterministic tie-break for duplicate routes.
  class RouteOrdering
    def self.key(route)
      route.values_at("path", "verb", "controller", "action", "confidence") +
        route.fetch("evidence").values_at("path", "line")
    end
  end

  # Stores route path and controller scope values.
  class RouteScope
    def self.empty
      { "path" => "", "module" => "", "nested_param" => nil,
        "member_path" => nil, "resource_controller" => nil }
    end

    def self.path(scope, value)
      RouteSyntax.path(scope["path"], value)
    end

    def self.with(scope, values)
      scope.merge(values)
    end
  end

  # Provides small Prism and route syntax operations.
  class RouteSyntax
    TABLES = {
      verbs: { "get" => ["GET"], "post" => ["POST"], "put" => ["PUT"], "patch" => ["PATCH"], "delete" => ["DELETE"] },
      actions: {
        "resources" => { "index" => ["GET", ""], "create" => ["POST", ""], "new" => ["GET", "/new"], "show" => ["GET", "/:id"], "edit" => ["GET", "/:id/edit"], "update" => ["PATCH", "/:id"], "destroy" => ["DELETE", "/:id"] },
        "resource" => { "create" => ["POST", ""], "new" => ["GET", "/new"], "show" => ["GET", ""], "edit" => ["GET", "/edit"], "update" => ["PATCH", ""], "destroy" => ["DELETE", ""] }
      },
      blocks: { "member" => "/:id", "collection" => "", "new" => "/new" },
      route_names: %w[get post put patch delete match root resources resource namespace scope mount concern concerns devise_for devise_scope direct]
    }.freeze

    def self.statements(node)
      node&.respond_to?(:body) ? node.body : []
    end

    def self.arguments(node)
      SourceSupport.arguments(node)
    end

    def self.value(node)
      SourceSupport.static_value(node)
    end

    def self.options(node)
      arguments(node).flat_map { |argument| option_pairs(argument) }.to_h
    end

    def self.option_pairs(argument)
      elements = argument.is_a?(Prism::KeywordHashNode) || argument.is_a?(Prism::HashNode) ? argument.elements : [argument]
      elements.filter_map { |entry| [value(entry.key).to_s, value(entry.value)] if entry.is_a?(Prism::AssocNode) }
    end

    def self.first(node)
      value(arguments(node).first)
    end

    def self.explicit_path_and_target(node)
      pair = route_pair(arguments(node).first)
      return pair if pair

      [node.name.to_s == "root" ? "/" : first(node), target(node)]
    end

    def self.route_pair(argument)
      return unless route_hash?(argument)

      association_pair(argument.elements)
    end

    def self.route_hash?(argument)
      argument.is_a?(Prism::KeywordHashNode) || argument.is_a?(Prism::HashNode)
    end

    def self.association_pair(entries)
      entries.each do |entry|
        pair = pair_values(entry)
        return pair if pair
      end
      nil
    end

    def self.pair_values(association)
      return unless association.is_a?(Prism::AssocNode)

      key = association.key
      path, target = value(key), value(association.value)
      [path, target] if route_path?(key, path, target)
    end

    def self.route_path?(key, path, target)
      path_key = key.is_a?(Prism::StringNode) ||
        (key.is_a?(Prism::SymbolNode) && !%w[to controller action via as on].include?(path))
      path_key &&
        path.is_a?(String) && target.is_a?(String) && target.include?("#")
    end

    def self.target(node)
      options = options(node)
      options["to"] || arguments(node).filter_map { |item| value(item) if item.is_a?(Prism::StringNode) }.find { |item| item.include?("#") }
    end

    def self.path(left, right)
      SourceSupport.normalize_path([left, right].compact.reject(&:empty?).join("/"))
    end

    def self.module_path(left, right)
      [left, right].compact.reject(&:empty?).join("/")
    end

    def self.controller(prefix, name)
      [prefix, name].compact.reject(&:empty?).join("/")
    end

    def self.action(generator, name)
      TABLES[:actions][generator][name]
    end

    def self.explicit_verbs(name, via)
      return ["GET"] if name == "root"
      return TABLES[:verbs][name] unless name == "match"

      match_verbs(via)
    end

    def self.match_verbs(via)
      return unless via

      methods = list(via).map { |verb| verb.to_s.upcase }
      methods.uniq if methods.all? { |verb| supported_verb?(verb) }
    end

    def self.supported_verb?(verb)
      (TABLES[:verbs].values.flatten + %w[HEAD OPTIONS]).include?(verb)
    end

    def self.actions(generator)
      TABLES[:actions][generator].keys
    end

    def self.list(value)
      value.is_a?(Array) ? value : [value]
    end

    def self.singular(name)
      name.sub(/ies\z/, "y").sub(/s\z/, "")
    end

    def self.route_call?(node)
      TABLES[:route_names].include?(node.name.to_s)
    end

    def self.dynamic?(node)
      !node.is_a?(Prism::NilNode) && value(node).is_a?(NilClass)
    end

    def self.dynamic_line(node)
      return dynamic_line(node.body) if node.is_a?(Prism::ParenthesesNode)

      node.location.start_line
    end

    def self.issue_key(issue)
      [issue.dig("evidence", "path"), issue.dig("evidence", "line"), issue["kind"]]
    end

    def self.report_extra_options(output, call, allowed)
      (call.options.keys - allowed).each do |key|
        output.issue("unsupported_route_option", option_line(call.node, key))
      end
    end

    def self.option_line(node, name)
      association = option_association(node, name)
      association ? association.value.location.start_line : node.location.start_line
    end

    def self.option_association(node, name)
      entries = arguments(node).flat_map { |argument| route_hash?(argument) ? argument.elements : [] }
      entries.find { |entry| entry.is_a?(Prism::AssocNode) && value(entry.key).to_s == name }
    end
  end

  # Reports dynamic local values used by route declarations.
  class RouteDynamicAssignmentScanner < Prism::Visitor
    def initialize(output)
      @output = output
      @writes = []
      @reads = []
    end

    def call(node)
      visit(node)
      report_dynamic_values
    end

    def visit_local_variable_write_node(node)
      @writes << node
      super
    end

    def visit_local_variable_read_node(node)
      @reads << node.name
      super
    end

    private

    def report_dynamic_values
      @writes.each { |node| report_if_dynamic(node) if @reads.include?(node.name) }
    end

    def report_if_dynamic(node)
      expression = node.value
      return unless RouteSyntax.dynamic?(expression)

      @output.issue("dynamic_route", RouteSyntax.dynamic_line(expression))
    end
  end

  # Walks nested route blocks with a static scope.
  class RouteWalker
    HANDLERS = {
      "draw" => :visit_draw,
      "namespace" => :visit_scope,
      "scope" => :visit_scope,
      "resources" => :visit_resource,
      "resource" => :visit_resource,
      "get" => :visit_explicit, "post" => :visit_explicit, "put" => :visit_explicit,
      "patch" => :visit_explicit, "delete" => :visit_explicit, "match" => :visit_explicit,
      "root" => :visit_explicit,
      "member" => :visit_block, "collection" => :visit_block, "new" => :visit_block,
      "mount" => :visit_dynamic, "concern" => :visit_dynamic, "concerns" => :visit_dynamic,
      "devise_for" => :visit_dynamic, "devise_scope" => :visit_dynamic, "direct" => :visit_dynamic
    }.freeze

    attr_reader :output, :explicit, :resources

    def initialize(output)
      @output = output
      @explicit = ExplicitRouteReader.new(output)
      @resources = ResourceRouteReader.new(output)
    end

    def walk(nodes, scope)
      RouteSyntax.statements(nodes).each { |node| visit(RouteCall.new(node, scope)) }
    end

    private

    def visit(call)
      return self.class.visit_call(call, self) if call.node.is_a?(Prism::CallNode)

      visit_dynamic(call)
    end

    def visit_dynamic(call)
      calls = embedded(call.node)
      return if calls.empty?

      @output.issue("dynamic_route", call.line)
      calls.each { |node| visit(RouteCall.new(node, call.scope)) }
    end

    def embedded(node)
      node.compact_child_nodes.flat_map do |child|
        child.is_a?(Prism::CallNode) ? (RouteSyntax.route_call?(child) ? [child] : []) : embedded(child)
      end
    end

    def self.visit_call(call, walker)
      handler = HANDLERS.fetch(call.name, :visit_unknown)
      public_send(handler, call, walker)
    end

    def self.visit_explicit(call, walker)
      walker.explicit.call(call)
    end

    def self.visit_dynamic(call, walker)
      walker.output.issue("dynamic_route", call.line)
    end

    def self.visit_draw(call, walker)
      node = call.node
      block = node.block
      return walker.output.issue("dynamic_route", call.line) unless block && RouteSyntax.arguments(node).empty?

      walker.walk(block.body, call.scope)
    end

    def self.visit_scope(call, walker)
      scope = scoped_values(call, walker.output)
      walker.walk(call.node.block.body, scope) if scope
    end

    def self.scoped_values(call, output)
      definition = RouteScopeInput.from(call)
      return dynamic_scope(call, output) unless definition.valid?

      output.issue("unsupported_route_scope", call.line) unless definition.supported?
      definition.apply(call.scope)
    end

    def self.dynamic_scope(call, output)
      output.issue("dynamic_route", call.line)
      nil
    end

    def self.visit_resource(call, walker)
      scope = walker.resources.call(call)
      block = call.node.block
      walker.walk(block.body, scope) if scope && block
    end

    def self.visit_block(call, walker)
      block = call.node.block
      walker.walk(block.body, block_scope(call)) if block
    end

    def self.block_scope(call)
      scope = call.scope
      name = call.name
      prefix = name == "member" ? (scope["member_path"] || "/:id") : RouteSyntax::TABLES[:blocks][name]
      RouteScope.with(scope, "path" => RouteScope.path(scope, prefix))
    end

    def self.visit_unknown(call, walker)
      block = call.node.block
      return unless block

      walker.output.issue("unsupported_route_generator", call.line)
      walker.walk(block.body, call.scope)
    end

    def issue_dynamic(call)
      @output.issue("dynamic_route", call.line)
      nil
    end
  end

  # Carries a route call and its inherited scope.
  class RouteCall
    attr_reader :node, :scope, :options

    def initialize(node, scope)
      @node, @scope = node, scope
      @options = node.is_a?(Prism::CallNode) ? RouteSyntax.options(node) : {}
    end

    def line
      return node.location.start_line unless node.is_a?(Prism::CallNode)

      node.message_loc.start_line
    end

    def name
      node.name.to_s
    end

    def explicit_verbs
      RouteSyntax.explicit_verbs(name, options["via"])
    end

    def explicit_path_and_target
      RouteSyntax.explicit_path_and_target(node)
    end
  end

  # Holds the static values from a route scope declaration.
  RouteScopeInput = Struct.new(:options, :name, :route_name, :path_dynamic, :module_dynamic, keyword_init: true) do
    def self.from(call)
      node = call.node
      new(options: call.options, name: RouteSyntax.first(node), route_name: call.name,
          path_dynamic: dynamic_path?(node), module_dynamic: dynamic_module?(node))
    end

    def self.dynamic_path?(node)
      expression = SourceSupport.option_node(node, "path")&.value || positional_name(node)
      expression && RouteSyntax.dynamic?(expression)
    end

    def self.dynamic_module?(node)
      expression = SourceSupport.option_node(node, "module")&.value
      expression && RouteSyntax.dynamic?(expression)
    end

    def self.positional_name(node)
      RouteSyntax.arguments(node).find { |argument| !RouteSyntax.route_hash?(argument) }
    end

    def path
      options.fetch("path", name || "")
    end

    def module_name
      value = options.fetch("module", route_name == "namespace" ? name : "")
      value == false ? "" : value
    end

    def valid?
      valid_namespace? && !path_dynamic && !module_dynamic && static_scope_values?
    end

    def supported?
      (options.keys - %w[path module as]).empty?
    end

    def apply(scope)
      RouteScope.with(scope, "path" => RouteScope.path(scope, path.to_s),
                             "module" => RouteSyntax.module_path(scope["module"], module_name.to_s))
    end

    private

    def static_scope_values?
      (path.is_a?(String) || path.is_a?(NilClass)) && module_name.is_a?(String)
    end

    def valid_namespace?
      route_name != "namespace" || name.is_a?(String)
    end
  end

  # Expands conventional resource declarations.
  class ResourceRouteReader
    def initialize(output)
      @output = output
    end

    def call(call)
      definition = build(call)
      return unless definition

      emit(definition)
      definition.nested_scope
    end

    private

    def build(call)
      reader = self.class
      values = reader.resource_values(call)
      return issue(call) unless values

      reader.definition(@output, call, values)
    end

    def self.resource_values(call)
      name = RouteSyntax.first(call.node)
      options = call.options
      values = [name, options, options.fetch("path", name), options.fetch("controller", name)]
      values if values.values_at(0, 2, 3).all? { |value| value.is_a?(String) }
    end

    def self.definition(output, call, values)
      name, options, path, controller = values
      actions = selected_actions(call, output)
      return unless actions

      definition_for(output, call, [name, options, path, controller, actions])
    end

    def self.definition_for(output, call, values)
      name, options, path, controller, actions = values
      RouteSyntax.report_extra_options(output, call, %w[controller path param only except as])
      base = resource_path(call, path)
      controller = RouteSyntax.controller(call.scope["module"], controller)
      ResourceDefinition.new(call:, name:, options:, actions:, base:, controller:)
    end

    def self.selected_actions(call, output)
      options = call.options
      name = call.name
      actions = permitted_actions(name, options) unless invalid_options?(options)
      return actions if actions && valid_actions?(name, actions)

      output.issue("dynamic_route", call.line)
    end

    def self.invalid_options?(options)
      only, except = options.values_at("only", "except")
      options.key?("concerns") || invalid?(options, "only", only) || invalid?(options, "except", except)
    end

    def self.permitted_actions(name, options)
      actions = RouteSyntax.actions(name)
      actions = RouteSyntax.list(options["only"]) if options.key?("only")
      actions -= RouteSyntax.list(options["except"]) if options.key?("except")
      actions
    end

    def self.valid_actions?(name, actions)
      actions.all? { |action| RouteSyntax.action(name, action) }
    end

    def self.invalid?(options, key, value)
      valid = value.is_a?(String) || value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
      options.key?(key) && !valid
    end

    def self.resource_path(call, path)
      scope = call.scope
      nested_param = scope["nested_param"]
      parent = nested_param && ":#{nested_param}"
      RouteSyntax.path(scope["path"], RouteSyntax.path(parent.to_s, path))
    end

    def emit(definition)
      definition.actions.each { |action| self.class.emit_action(@output, definition, action) }
    end

    def self.emit_action(output, definition, action)
      verb, suffix = RouteSyntax.action(definition.call.name, action)
      methods = action == "update" ? ["PATCH", "PUT"] : [verb]
      methods.each { |method| output.add(definition.route(method, suffix, action)) }
    end

    def issue(call)
      @output.issue("dynamic_route", call.line)
      nil
    end
  end

  # Reads explicit controller targets and HTTP verbs.
  class ExplicitRouteReader
    def initialize(output)
      @output = output
    end

    def call(call)
      RouteSyntax.report_extra_options(@output, call, %w[to controller action via as on])
      definition = build(call)
      return unless definition

      emit_routes(call, definition)
    end

    private

    def build(call)
      reader = self.class
      values = reader.route_values(call)
      return invalid_definition(call) unless values

      definition(call, values)
    end

    def definition(call, values)
      path, target, controller, action = values
      controller = resolve_controller(call, target, controller)
      path = RouteSyntax.path(self.class.prefix(call), path)
      ExplicitDefinition.new(call:, path:, controller:, action:)
    end

    def emit_routes(call, definition)
      definitions = ExplicitDefinition.expanded(call, definition)
      verbs(call).each { |verb| emit_definitions(definitions, verb) }
    end

    def emit_definitions(definitions, verb)
      definitions.each { |route| @output.add(route.route(verb)) }
    end

    def self.route_values(call)
      path, target = call.explicit_path_and_target
      return unless path.is_a?(String)

      controller, action = target_parts(call, path, target)
      [path, target, controller, action] if controller && action
    end

    def resolve_controller(call, target, controller)
      return controller if self.class.inherited?(call, target)

      RouteSyntax.controller(call.scope["module"], controller)
    end

    def self.target_parts(call, path, target)
      return unless valid_on?(call)
      target_controller_action(target) || controller_action(call.options) || resource_action(call, path)
    end

    def self.target_controller_action(target)
      target.split("#", 2) if target.is_a?(String) && target.include?("#")
    end

    def self.resource_action(call, path)
      controller = call.scope["resource_controller"]
      [controller, path.split("/").last] if controller
    end

    def self.controller_action(options)
      controller, action = options.values_at("controller", "action")
      [controller, action] if controller && action
    end

    def verbs(call)
      result = call.explicit_verbs
      result || issue(call)
    end

    def self.valid_on?(call)
      options = call.options
      return true unless options.key?("on")

      call.scope["resource_controller"] && %w[member collection new].include?(options["on"].to_s)
    end

    def self.inherited?(call, target)
      options = call.options
      !target && !(options["controller"] && options["action"]) && call.scope["resource_controller"]
    end

    def self.prefix(call)
      scope = call.scope
      suffix = on_prefix(scope, call.options["on"])
      RouteSyntax.path(scope["path"], suffix)
    end

    def self.on_prefix(scope, option)
      case option.to_s
      when "member" then scope["member_path"]
      when "new" then "/new"
      else ""
      end
    end

    def issue(call)
      @output.issue("dynamic_route", call.line)
      []
    end

    def invalid_definition(call)
      @output.issue("dynamic_route", call.line)
      nil
    end
  end

  # Holds conventional route details until each action is emitted.
  ResourceDefinition = Struct.new(:call, :name, :options, :actions, :base, :controller, keyword_init: true) do
    def route(verb, suffix, action)
      { "line" => call.line, "verb" => verb, "path" => RouteSyntax.path(base, suffix),
        "controller" => controller, "action" => action, "confidence" => "conventional" }
    end

    def nested_scope
      scope = call.scope
      return scope unless call.node.block

      param = options.fetch("param", "id")
      scope.merge("path" => base, "nested_param" => "#{RouteSyntax.singular(name)}_#{param}",
                  "member_path" => "/:#{param}", "resource_controller" => controller)
    end
  end

  # Holds an explicit route until its verbs are emitted.
  ExplicitDefinition = Struct.new(:call, :path, :controller, :action, keyword_init: true) do
    def self.expanded(call, base)
      arguments = RouteSyntax.arguments(call.node)
      return [base] unless extra_actions?(call.scope, arguments)

      [base] + extra_routes(call, base, arguments)
    end

    def self.extra_actions?(scope, arguments)
      scope["resource_controller"] && arguments.length > 1
    end

    def self.extra_routes(call, base, arguments)
      scope = call.scope
      arguments.drop(1).filter_map do |argument|
        action = RouteSyntax.value(argument)
        next unless action.is_a?(String)

        new(call:, path: RouteSyntax.path(scope["path"], action), controller: base.controller, action:)
      end
    end

    def route(verb)
      { "line" => call.line, "verb" => verb, "path" => path, "controller" => controller,
        "action" => action, "confidence" => "direct" }
    end
  end
end
