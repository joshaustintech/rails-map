# frozen_string_literal: true

require "json"
require "optparse"

# Static navigation evidence from a Rails source tree.
module RailsMap
  VIEW_EXTENSIONS = %w[html.erb turbo_stream.erb json.jbuilder html.builder text.erb].freeze
  # Shared path and naming rules for source scanners.
  class Source
    def initialize(root)
      @root = File.expand_path(root)
    end

    def root
      @root
    end

    def files(directory)
      Dir.glob(File.join(@root, directory, "**", "*.rb")).sort
    end

    def relative(path)
      path.delete_prefix(@root + "/")
    end

    def evidence(path, line)
      { "path" => relative(path), "line" => line }
    end

    def self.camel(value)
      value.gsub("/", "::").split("::").map { |part| part.split("_").map(&:capitalize).join }.join("::")
    end

    def self.existing_paths(paths)
      paths.select { |path| File.file?(path) }
    end

    def render_pattern(path, target)
      slug = relative(path).delete_prefix("app/controllers/").delete_suffix("_controller.rb")
      base = RenderTarget.new(target).base(slug)
      view_glob(base)
    end

    def view_glob(base)
      File.join(@root, "#{base}.{#{VIEW_EXTENSIONS.join(",")}}")
    end
  end

  # Source lines and names for one controller file.
  ControllerFile = Struct.new(:path, :controller, :lines) do
    def action_at(index, source)
      path = self.path
      source_lines = lines
      action_name = source_lines[index][/^\s*def\s+([\w!?]+)/, 1]
      body = ControllerScanner.action_body(source_lines, index)
      ControllerAction.new(path, index + 1, controller, route_controller(source),
        action_name, body, self.class.body_line_numbers(index, body))
    end

    def route_controller(source)
      source.relative(path).delete_prefix("app/controllers/").delete_suffix("_controller.rb")
    end

    def self.body_line_numbers(index, body)
      body.each_index.map { |offset| index + offset + 2 }
    end
  end
  # One action and the source facts used to find its related views.
  ControllerAction = Struct.new(:path, :line, :controller, :route_controller, :action, :body, :body_lines) do
    def to_row(source)
      { "controller" => controller, "route_controller" => route_controller, "action" => action,
        "source" => source.evidence(path, line), "models" => ControllerScanner.model_names(body) }
    end

    def conventional_paths(source)
      directory = source.relative(path).delete_prefix("app/controllers/").delete_suffix("_controller.rb")
      Dir.glob(source.view_glob("app/views/#{directory}/#{action}")).sort
    end

    def render_pattern(source, target)
      source.render_pattern(path, target)
    end

    def view_candidate(view_path, line, confidence)
      ViewCandidate.new(controller, action, view_path, path, line, confidence)
    end

    def render_lines
      body.each_with_index.map do |line, offset|
        source = line
        source += body[offset + 1].to_s if line.rstrip.end_with?(",")
        [line, body_lines[offset], source]
      end
    end
  end
  # Resolves a literal render target into its view directory.
  RenderTarget = Struct.new(:value) do
    def base(slug)
      return value.delete_prefix("/") if value.start_with?("/")

      "app/views/#{value.include?("/") ? value : slug + "/" + value}"
    end
  end
  # Evidence and confidence for one view candidate.
  ViewCandidate = Struct.new(:controller, :action, :path, :source_path, :line, :confidence) do
    def to_row(source)
      { "controller" => controller, "action" => action, "path" => source.relative(path),
        "confidence" => confidence, "evidence" => source.evidence(source_path, line) }
    end
  end
  # Controller action and source line for one render statement.
  RenderCall = Struct.new(:action, :line)
  # One line in the Rails route file.
  RouteLine = Struct.new(:path, :line, :text, :option_text, :inline_context) do
    LITERAL_ROUTE = /^\s*(get|post|put|patch|delete|match)\s+(?:["']([^"']*)["']|:([a-z_]+))\s*(?:=>\s*|,.*\bto:\s*)["']([A-Za-z0-9_:\/]+)#([A-Za-z0-9_]+)["']/
    EXPLICIT_OPTIONS = %w[to controller action via as on].freeze
    RESOURCE_OPTIONS = %w[controller path param only except as].freeze

    def with_text(value)
      RouteLine.new(path, line, value, option_text, inline_context)
    end

    def route_context(path, module_path)
      return RouteContext.new(nil, "dynamic_scope", path, module_path, nil) if dynamic_scope?

      RouteScope.scope_context(option_text, path, module_path)
    end

    def read
      static_reading || resource_reading || fallback_reading
    end

    def static_reading
      route_line_class = self.class
      return route_line_class.route_reading(root_target) if root?
      return RouteReading.new(:dynamic, nil) if dynamic?
      return RouteReading.new(:routes, match_targets) if match_route?
      return route_line_class.route_reading(literal_target) if literal?
    end

    def self.route_reading(target)
      RouteReading.new(:route, target)
    end

    def resource_reading
      return unless resource?

      declaration = resource_declaration
      return RouteReading.new(:dynamic, nil) unless declaration

      RouteReading.new(:resource, declaration)
    end

    def fallback_reading
      kind = route_declaration? ? :dynamic : :other
      RouteReading.new(kind, nil)
    end

    def targetless_member_route?
      text.match?(/^\s*(get|post|put|patch|delete|match)\b/) &&
        !text.match?(/\b(?:if|unless)\b/) &&
        !option_text.match?(/\b(?:to|controller|action)\s*:/) &&
        !option_text.match?(/=>\s*["'][^"']*#[A-Za-z_]/)
    end

    def root_target
      controller, action = text.match(/^\s*root\s+(?:to:\s*)?["']([A-Za-z0-9_:\/]+)#([A-Za-z0-9_]+)["']/).captures
      RouteTarget.new("GET", "/", controller, action, "direct")
    end

    def literal_target
      captures = literal_route_match.captures
      verb, path, action_name, controller, action = captures
      path ||= RouteLine.symbol_route_path(action_name, text)
      RouteTarget.new(verb.upcase, path, controller, action, "direct")
    end

    def match_route?
      text.match?(/^\s*match\b/)
    end

    def match_targets
      MatchRouteTargets.new(literal_route_match, option_text).call
    end

    def self.symbol_route_path(action, source)
      suffix = source.match?(/\bon:\s*:member\b/) ? "/:id/#{action}" : "/#{action}"
      suffix
    end

    def self.block_header?(text)
      text.match?(/^\s*scope\b/) && text.include?(",")
    end

    def self.scope_block?(text)
      text.gsub(/\s+/, " ").match?(/^\s*(scope|namespace)\b.*\bdo\b/)
    end

    def self.dynamic_context_kind(text)
      return unless text.match?(/\bdo\b|^\s*(?:if|unless)\b/)
      return "devise_scope" if text.match?(/^\s*devise_scope\b/)
      return "dynamic_condition" if text.match?(/^\s*(?:if|unless)\b/)
      return "unsupported_scope" if text.match?(/\.(?:each|each_with_index)\b/)

      "generic"
    end

    def self.resource_header(text, line)
      return text if text.match?(/^\s*resources?\s+:\w+.*\bdo\b/)
      return unless line.text.match?(/^\s*resources?\s+:\w+/)
      options = line.option_text
      return unless options.match?(/\bdo\b/)

      options.split(/\bdo\b/, 2).first.gsub(/\s+/, " ") + " do"
    end

    def self.resource_context(text, parent, scope)
      source = new(nil, nil, text, text)
      return if source.dynamic_resource_options?

      source.resource_context(nil, parent&.resource, scope)
    end

    def inline_route
      self.class.inline_route(text)
    end

    def self.inline_route(text)
      match = text.match(/^\s*(member|collection)\s*\{\s*(.*?)\s*\}\s*$/)
      [match[1], match[2]] if match
    end

    def self.member_kind(block, line)
      kind = block.kind
      kind = line.text[/\bon:\s*:(member|collection)\b/, 1] || "resource" if kind == "resource" && line
      kind if %w[member collection resource].include?(kind)
    end

    def self.closing_block?(text)
      text.match?(/^\s*end\b/)
    end

    def self.continuation_lines(lines, index)
      first = lines[index]
      return [] unless opens_continuation?(first)

      following_lines(lines, index + 1, first[/\A\s*/].length)
    end

    def self.opens_continuation?(line)
      line.rstrip.match?(/,\s*$|=>\s*$|\(\s*$|\[\s*$|\{\s*$/)
    end

    def self.following_lines(lines, start, indentation)
      lines.drop(start).take_while { |line| continuation_line?(line, indentation) }
    end

    def self.continuation_line?(line, indentation)
      !line.strip.empty? && line[/\A\s*/].length > indentation
    end

    def route_scope?
      self.class.scope_block?(option_text)
    end

    def unsupported_scope_options?
      return false unless route_scope?

      options = option_text.scan(/\b([a-z_]+):/).flatten
      (options - %w[path module as]).any?
    end

    def dynamic_scope?
      return false unless route_scope?

      scope_values.any? { |value| !self.class.static_scope_value?(value) }
    end

    def scope_values
      option_text.scan(/\b(?:path|module):[ \t]*(.*?)(?=,\s*[a-z_]+:|\s+do\b|\n|$)/).flatten
    end

    def self.static_scope_value?(value)
      value = value.strip
      return false if value.include?('#{')

      value.match?(/\A(?:nil|true|false|:[a-z_]+|"[^"]*"|'[^']*')\z/)
    end

    def resource_declaration
      name = text[/^\s*resources?\s+:([a-z_]+)/, 1]
      controller = option_text[/\bcontroller:[ \t]*["']([^"']+)["']/, 1]
      path = option_text[/\bpath:[ \t]*["']([^"']+)["']/, 1]
      return if dynamic_resource_options?

      [ResourceDeclaration.new(self, name, controller, path), resource_actions]
    end

    def dynamic_resource_options?
      %w[controller path only except].any? do |name|
        next false unless option_text.match?(/\b#{name}:/)

        !option_text.match?(/\b#{name}:[ \t]*(?:["'][^"']*["']|%i?\[[^]]*\]|\[[^]]*\]|:[a-z_]+)/)
      end
    end

    def resource_actions
      selected_resource_actions - excluded_resource_actions
    end

    def selected_resource_actions
      selected = option_values("only")
      selected ? selected.scan(/[a-z_]+/) : RouteScanner::RESOURCE_ACTIONS.keys
    end

    def excluded_resource_actions
      excluded = option_values("except")
      excluded ? excluded.scan(/[a-z_]+/) : []
    end

    def option_values(name)
      match = option_text.match(/\b#{name}:\s*(?:%i\[([^\]]*)\]|\[([^\]]*)\]|:([a-z_]+))/)
      captures = match.captures if match
      captures.compact.first if captures
    end

    def dynamic?
      return false if text.match?(/^\s*Rails\.application\.routes\.draw\s+do\b/)

      dynamic_generator? || route_declaration? && (interpolated_value? || dynamic_target?)
    end

    def dynamic_generator?
      text.match?(/^\s*(mount|draw|devise_for|devise_scope)\b/)
    end

    def interpolated_value?
      route_options = option_text.split(/,\s*(?:as|constraints|format|defaults):/, 2).first
      route_options.match?(/["'][^"']*#\{[^}]*\}/)
    end

    def dynamic_target?
      text.match?(/\b(?:to|root)\s*[:=]>?\s*(redirect|proc|lambda)\s*\(/)
    end

    def condition?
      text.match?(/^\s*(?:if|unless)\b/)
    end

    def dynamic_assignment?
      text.match?(/^\s*[a-z_]\w*\s*=\s*[A-Z]?[A-Za-z_][\w.]*\[/)
    end

    def root?
      text.match?(/^\s*root\s+(?:to:\s*)?["']([A-Za-z0-9_:\/]+)#([A-Za-z0-9_]+)["']/)
    end

    def literal?
      literal_route_match
    end

    def literal_route_match
      option_text.gsub(/\s+/, " ").match(LITERAL_ROUTE)
    end

    def unsupported_options?
      unsupported_option_lines.any?
    end

    def unsupported_option_lines
      RouteOptionLineScanner.new(option_text, line, allowed_options).call
    end

    def allowed_options
      resource? ? RESOURCE_OPTIONS : EXPLICIT_OPTIONS
    end

    def scope_uncertainty
      return "dynamic_route" if condition? || dynamic_assignment?
      return generator_uncertainty if unsupported_generator_block? || iteration_block?
      return unless route_scope?
      return "dynamic_route" if dynamic_scope?
      return "unsupported_route_scope" if unsupported_scope_options?
    end

    def generator_uncertainty
      text.match?(/^\s*direct\b/) ? "dynamic_route" : "unsupported_route_generator"
    end

    def unsupported_generator_block?
      text.match?(/^\s*(?:authenticate|authenticated|direct)\b.*\bdo\b/) ||
        text.match?(/^\s*constraints(?!:)\b.*\bdo\b/)
    end

    def iteration_block?
      text.match?(/\.each(?:_with_index)?\b.*(?:\bdo\b|\{)/)
    end

    def inline_iteration_route?
      iteration_block? && text.match?(/\b(?:get|post|put|patch|delete|match)\b.*#\{/)
    end

    def resource_context(resource, parent, scope)
      resource ||= text[/^\s*resources?\s+:([a-z_]+).*\bdo\b/, 1]
      return unless resource

      controller = option_text[/\bcontroller:\s*["']([^"']+)["']/, 1]
      RouteContext.new(resource, "resource", resource_path(resource, parent, scope),
        scope.module_prefix, controller)
    end

    def resource_path(resource, parent, scope)
      prefix = RouteScope.resource_prefix(scope.path_prefix, parent)
      segment = option_text[/\bpath:\s*["']([^"']+)["']/, 1] || resource
      RouteScope.append_path(prefix, segment)
    end

    def route_declaration?
      text.match?(/^\s*(get|post|put|patch|delete|match|root|resources?)\b/)
    end

    def member_route_issue
      "unsupported_route_option" if route_declaration? && unsupported_options?
    end

    def resource?
      text.match?(/^\s*resources?\s+:([a-z_]+)(?:\s*,\s*only:\s*\[([^\]]+)\])?/)
    end
  end
  # Converts a literal match route into one row for each declared HTTP verb.
  class MatchRouteTargets
    def initialize(match, options)
      @match = match
      @options = options
      @verbs = verbs
    end

    def call
      return [] unless @match && @verbs

      path, controller, action = @match.captures.values_at(1, 3, 4)
      @verbs.split.map { |verb| RouteTarget.new(verb.upcase, path, controller, action, "direct") }
    end

    private

    def verbs
      @options[/\bvia\s*(?::|=>)\s*%i?\[([^]]+)\]/, 1]
    end
  end
  # Finds unsupported route options and their source lines.
  class RouteOptionLineScanner
    def initialize(text, first_line, allowed)
      @text, @first_line, @allowed = text, first_line, allowed
    end

    def call
      return [] if @text.include?("**{")

      scan_lines(@text.lines, 0, 0)
    end

    def scan_lines(lines, depth, offset)
      return [] if lines.empty?

      source = lines.shift
      issue_line = unsupported_line(source, offset, depth)
      next_depth = self.class.brace_delta(source, depth)
      [issue_line].compact + scan_lines(lines, next_depth, offset + 1)
    end

    def unsupported_line(source, offset, depth)
      scanner = self.class
      names = scanner.option_names(source, depth)
      return unless names.any? { |name| !@allowed.include?(name) }

      @first_line + offset + scanner.value_offset(source)
    end

    def self.option_names(source, depth)
      return [] unless depth.zero?

      text = source.gsub(/#\{[^}]*\}/, "").split("{", 2).first
      text = text.gsub(/redirect\s*\([^)]*\)/, "redirect")
      keyword_options(text) + symbol_hashrocket_options(text) + string_hashrocket_options(text)
    end

    def self.brace_delta(source, depth)
      code = source.gsub(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/, "")
      [depth + code.count("{") - code.count("}"), 0].max
    end

    def self.keyword_options(text)
      text.scan(/\b([a-z_]+):/).flatten
    end

    def self.symbol_hashrocket_options(text)
      text.scan(/:\s*([a-z_]+)\s*=>/).flatten
    end

    def self.string_hashrocket_options(text)
      text.scan(/["']([^"']*)["']\s*=>/).flatten
    end

    def self.value_offset(source)
      source.match?(/["'][^"']*["']\s*=>\s*$/) ? 1 : 0
    end
  end
  # Parsed meaning of one route source line.
  RouteReading = Struct.new(:kind, :value) do
    def dynamic?
      kind == :dynamic
    end
  end
  # One route line paired with the parsed route statement.
  RouteDeclaration = Struct.new(:line, :reading) do
    def warning?
      line.unsupported_options? && %i[resource route routes].include?(reading.kind)
    end

    def route?
      reading.kind == :route
    end

    def resource?
      reading.kind == :resource
    end

    def value
      reading.value
    end

    def to_a
      [line, *reading.to_a]
    end

    def suppressed?(contexts)
      (contexts.contains_kind?("devise_scope") && line.root?) ||
        contexts.contains_kind?("dynamic_scope") ||
        (contexts.contains_kind?("unsupported_resource") && reading.kind != :other) ||
        (line.targetless_member_route? && contexts.current(line))
    end
  end
  # Route prefixes inherited by one resource declaration.
  RouteScope = Struct.new(:path_prefix, :module_prefix) do
    def self.append_path(prefix, segment)
      suffix = segment.to_s.delete_prefix("/")
      return prefix if suffix.empty?

      prefix == "/" ? "/#{suffix}" : "#{prefix}/#{suffix}"
    end

    def self.singular(name)
      name.to_s.sub(/ies\z/, "y").sub(/s\z/, "")
    end

    def self.append_module(prefix, segment)
      [prefix, segment].reject(&:empty?).join("/")
    end

    def self.scope_context(text, path_prefix, module_prefix)
      return unless RouteLine.scope_block?(text)

      scope = RouteScope.new(path_prefix, module_prefix)
      namespace = text[/^\s*namespace\s+:([a-z0-9_]+)/, 1]
      return namespace_context(text, namespace, scope) if namespace

      regular_scope_context(text, scope)
    end

    def self.namespace_context(text, namespace, scope)
      path = scope_value(text, "path") || namespace
      RouteContext.new(namespace, "namespace", append_path(scope.path_prefix, path),
        append_module(scope.module_prefix, namespace), scope_value(text, "controller"))
    end

    def self.regular_scope_context(text, scope)
      RouteContext.new(nil, scope_kind, append_path(scope.path_prefix, scope_path(text)),
        scope_module(scope.module_prefix, text), scope_value(text, "controller"))
    end

    def self.scope_kind
      "scope"
    end

    def self.scope_path(text)
      value = text[/\bpath:\s*["']([^"']+)["']/, 1] || text[/^\s*scope\s+["']([^"']+)["']/, 1]
      return "" if value&.include?("\#{")

      value.to_s
    end

    def self.scope_module(prefix, text)
      append_module(prefix, scope_value(text, "module").to_s)
    end

    def self.scope_value(text, name)
      text[/\b#{name}:\s*["']([^"']+)["']/, 1]
    end

    def self.resource_prefix(path, parent)
      return path unless parent

      append_path(path, ":#{singular(parent)}_id")
    end
  end
  # Static facts for one route result.
  RouteTarget = Struct.new(:verb, :path, :controller, :action, :confidence) do
    def within(path_prefix, module_prefix)
      route_path = scoped_path(path_prefix)
      route_controller = scoped_controller(module_prefix)
      RouteTarget.new(verb, route_path, route_controller, action, confidence)
    end

    def scoped_path(prefix)
      return path if prefix == "/"
      return prefix if path.empty? || path == "/"

      path.start_with?("/") ? "#{prefix}#{path}" : "#{prefix}/#{path}"
    end

    def scoped_controller(prefix)
      return controller if prefix.empty? || controller.start_with?("#{prefix}/")

      "#{prefix}/#{controller}"
    end

    def to_row(source_line, source)
      normalized_path = path.start_with?("/") ? path : "/#{path}"
      normalized_path = normalized_path.delete_suffix("/") unless normalized_path == "/"
      { "verb" => verb, "path" => normalized_path, "controller" => controller,
        "action" => action, "confidence" => confidence,
        "evidence" => source.evidence(source_line.path, source_line.line) }
    end
  end
  # One resources declaration and its source line.
  ResourceDeclaration = Struct.new(:source_line, :name, :controller, :path) do
    def rows_for(action, source, scope)
      definition = RouteScanner::RESOURCE_ACTIONS[action]
      return [] unless definition

      route_rows(definition, action, scope).map { |target| target.to_row(source_line, source) }
    end

    def route_rows(definition, action, scope)
      verbs, suffix = definition
      base_path = resource_path(scope)
      controller = resource_controller(scope)
      verbs.map { |verb| RouteTarget.new(verb, "#{base_path}#{suffix}", controller, action, "conventional") }
    end

    def resource_path(scope)
      prefix = scope.path_prefix
      segment = path || name
      RouteScope.append_path(prefix, segment)
    end

    def resource_controller(scope)
      module_prefix = scope.module_prefix
      explicit_controller = controller
      if explicit_controller
        return explicit_controller if explicit_controller.start_with?(module_prefix)

        return [module_prefix, explicit_controller].reject(&:empty?).join("/")
      end

      [module_prefix, name].reject(&:empty?).join("/")
    end
  end
  # Resource and path kind active for a member or collection route.
  RouteContext = Struct.new(:resource, :kind, :path_prefix, :module_prefix, :controller_name) do
    def path(action)
      "#{path_prefix}/#{action}"
    end

    def controller
      return controller_name if controller_name

      [module_prefix, resource].reject(&:empty?).join("/")
    end

    def resource_block?
      kind == "resource"
    end
  end
  # Tracks static member and collection blocks while reading route lines.
  class RouteContextStack
    def initialize
      @blocks = [RouteContext.new(nil, "root", "/", "")]
      @pending = PendingRouteBlock.new
    end

    def current(line = nil)
      kind = RouteLine.member_kind(@blocks.last, line)
      return unless kind && (resource = resource_context)

      path = current_resource_path(kind)
      RouteContext.new(resource.resource, kind, path, module_path, resource.controller_name)
    end

    def contains_kind?(kind)
      @blocks.any? { |block| block.kind == kind }
    end

    def route_path
      @blocks.last.path_prefix
    end

    def module_path
      @blocks.last.module_prefix
    end

    def prefix_for_resource
      RouteScope.resource_prefix(route_path, resource_context&.resource)
    end

    def update(line)
      line = @pending.collect(line)
      text = line.text
      return if @pending.active?
      return @blocks.pop if RouteLine.closing_block?(text) && @blocks.length > 1

      @pending.start(text) unless push_resource(line) || push_scope(line) || push_dynamic(text)
    end

    private

    def push_resource(line)
      header = RouteLine.resource_header(line.text, line)
      return unless header

      push_resource_context(header)
      true
    end

    def push_resource_context(header)
      scope = RouteScope.new(route_path, module_path)
      context = RouteLine.resource_context(header, resource_context, scope)
      @blocks << (context || RouteContext.new(nil, "unsupported_resource", route_path, module_path, nil))
    end

    def push_scope(line)
      kind = line.text[/^\s*(member|collection)\s+do\b/, 1]
      resource = resource_context
      return push_route_scope(line) unless resource && kind

      push_member_scope(resource, kind)
    end

    def push_member_scope(resource, kind)
      path = kind == "member" ? RouteScope.append_path(route_path, ":id") : route_path
      @blocks << RouteContext.new(resource.resource, kind, path, module_path, resource.controller_name)
      true
    end

    def push_route_scope(line)
      scope = line.route_context(route_path, module_path)
      @blocks << scope if scope
      scope
    end

    def current_resource_path(kind)
      suffix = { ["resource", "member"] => ":id" }.fetch([@blocks.last.kind, kind], "")
      RouteScope.append_path(route_path, suffix)
    end

    def push_dynamic(text)
      return if text.match?(/^\s*[a-z_]+:/)

      kind = RouteLine.dynamic_context_kind(text)
      return unless kind

      @blocks << RouteContext.new(nil, kind, route_path, module_path, nil)
    end

    def resource_context
      @blocks.reverse.find { |item| item.kind == "resource" }
    end

  end
  # Joins multi-line route block headers until their `do` token appears.
  class PendingRouteBlock
    def initialize
      @text = nil
      @active = false
    end

    def collect(line)
      combined = [@text, line.text].compact.join(" ")
      complete = @active && combined.match?(/\bdo\b/)
      @text, @active = complete ? [nil, false] : [combined, true] if @active
      line.with_text(combined)
    end

    def active?
      @active
    end

    def start(text)
      return unless RouteLine.block_header?(text)

      @text = text
      @active = true
    end
  end
  # Reads verb and action names inside a member or collection block.
  class MemberRoute
    def self.rows(line, context, source)
      return [] if explicit_target?(line)

      route_row(line, context, source)
    end

    def self.explicit_target?(line)
      line.text.match?(/to:|=>/)
    end

    def self.route_row(line, context, source)
      verb, actions = route_parts(line.text)
      return [] unless verb && actions.any?

      actions.map do |action|
        target = RouteTarget.new(verb.upcase, context.path(action), context.controller, action, "direct")
        target.to_row(line, source)
      end
    end

    def self.route_parts(text)
      match = text.match(/^\s*(get|post|put|patch|delete)\s+(.+)/)
      return [] unless match

      [match[1], match[2].scan(/:([a-z_]+)|["']([^"']+)["']/).map { |pair| pair.compact.first }]
    end
  end
  # Adds route rows declared inside a resource member or collection block.
  class MemberRouteEmitter
    def self.rows(line, flow)
      context = context_for(line, flow)
      return [] unless context

      report_issue(line, flow)
      MemberRoute.rows(line, context, flow.source)
    end

    def self.context_for(line, flow)
      contexts = flow.contexts
      return if blocked?(contexts)

      line.inline_context || contexts.current(line)
    end

    def self.report_issue(line, flow)
      issue = line.member_route_issue
      flow.uncertainty.call(line, issue) if issue
    end

    def self.blocked?(contexts)
      contexts.contains_kind?("unsupported_scope") || contexts.contains_kind?("dynamic_scope")
    end
  end
  # Route declaration and one of its requested actions.
  # Source location and text for one model declaration.
  ModelLine = Struct.new(:path, :line_number, :model, :text) do
    def association_match
      text.match(/\A[ \t]*(has_many|has_one|belongs_to|has_and_belongs_to_many)\s*\(?\s*:(\w+)/)
    end

    def association_macro?
      !text.lstrip.start_with?("#") && text.match?(/\b(?:has_many|has_one|belongs_to|has_and_belongs_to_many)\b/)
    end

    def through_kind
      return "none" unless text.include?("through:")
      return "static" if text.match?(/through:\s*:\w+/)

      "dynamic"
    end

    def association_row(source, match, resolution)
      { "model" => model, "name" => match[2], "target" => resolution.target,
        "confidence" => resolution.confidence, "evidence" => source.evidence(path, line_number),
        "_through" => text[/\bthrough:\s*:(\w+)/, 1],
        "_source" => text[/\bsource:\s*:(\w+)/, 1] || text[/\bsource:\s*["'](\w+)["']/, 1] }
    end
  end
  # Target and confidence from one static association declaration.
  AssociationResolution = Struct.new(:target, :confidence, :dynamic)
  # Removes graph-only keys from an association result.
  class AssociationRow
    def self.clean(record)
      record.delete("_through")
      record.delete("_source")
    end
  end
  # Resolves a through association from known associations in its model catalog.
  class ThroughAssociationGraph
    def initialize(records)
      @records = records
      @index = records.to_h { |record| [[record["model"], record["name"]], record] }
      @unresolved = []
    end

    def resolve
      resolve_records
      clean_records
      @unresolved
    end

    private

    def resolve_records
      changed = true
      rounds = 0
      record_count = @records.length
      while changed && rounds < record_count
        changed = resolve_round(record_count)
        rounds += 1
      end
    end

    def resolve_round(record_count)
      changed = false
      index = 0
      while index < record_count
        changed = process(@records[index]) || changed
        index += 1
      end
      changed
    end

    def clean_records
      index = 0
      while index < @records.length
        record = @records[index]
        mark_unresolved(record) if record["_through"] && !record["target"]
        AssociationRow.clean(record)
        index += 1
      end
    end

    def resolve_declaration(record)
      return false unless record["_through"]

      source_row = source_association(record, source_name(record))
      return false unless source_row && source_row["target"]

      self.class.update_target(record, source_row)
    end

    def source_name(record)
      record["_source"] || self.class.singular(record["name"])
    end

    def process(record)
      resolve_declaration(record)
    end

    def source_association(record, name)
      through = @index[[record["model"], record["_through"]]]
      @index[[through && through["target"], name]]
    end

    def self.update_target(record, source_row)
      previous_target = record["target"]
      target = source_row["target"]
      record["target"] = target
      record["confidence"] = source_row["confidence"]
      previous_target != target
    end

    def mark_unresolved(record)
      @unresolved << { "kind" => "dynamic_association_target", "evidence" => record["evidence"] }
    end

    def self.singular(name)
      name.sub(/ies\z/, "y").sub(/s\z/, "")
    end
  end
  # CLI command, target, and unparsed options from the initial arguments.
  CommandLine = Struct.new(:arguments) do
    def command
      arguments[0]
    end

    def target
      arguments[1] if command == "inspect"
    end

    def valid_command?
      ["map", "inspect"].include?(command)
    end

    def valid_target?
      return true unless command == "inspect"

      value = target
      value && value.include?("#")
    end

    def remaining
      arguments.drop(command == "inspect" ? 2 : 1)
    end

    def consume
      [target, remaining]
    end
  end

  # Finds public controller actions and their view candidates.
  class ControllerScanner
    attr_reader :actions, :views, :unresolved

    def initialize(source)
      @source = source
      @actions = []
      @views = []
      @unresolved = []
    end

    def scan
      directory = "app/controllers"
      paths = @source.files(directory)
      controller_paths = paths.grep(/_controller\.rb\z/)
      controller_paths.each { |path| scan_file(path) }
    end

    private

    def scan_file(path)
      source_file = ControllerFile.new(path, controller_name(path), File.readlines(path))
      public_actions = true
      source_file.lines.each_with_index do |line, index|
        public_actions = self.class.visibility(line, public_actions)
        add_action(source_file, index) if public_actions && line.match?(/^\s*def\s+(?!self\.)[\w!?]+/)
      end
    end

    def self.visibility(line, current)
      value = line.strip
      return true if value == "public"
      return false if value == "private" || value == "protected"

      current
    end

    def controller_name(path)
      part = @source.relative(path).delete_prefix("app/controllers/").delete_suffix(".rb")
      Source.camel(part).sub(/Controller\z/, "") + "Controller"
    end

    def add_action(source_file, index)
      action = source_file.action_at(index, @source)
      @actions << action.to_row(@source)
      add_views(action)
    end

    def self.action_body(lines, index)
      collect_body(lines, index + 1, 1)
    end

    def self.collect_body(lines, index, depth)
      body = []
      while index < lines.length && depth > 0
        line = lines[index]
        depth = body_depth(line, depth, body)
        index += 1
      end
      body
    end

    def self.body_depth(line, depth, body)
      stripped = line.sub(/#.*$/, "").strip
      next_value = next_body_depth(stripped, depth)
      body << line unless next_value.zero?
      next_value
    end

    def self.next_body_depth(line, depth)
      return depth == 1 ? 0 : depth - 1 if line.match?(/^end\b/)

      depth + (block_start?(line) ? 1 : 0)
    end

    def self.block_start?(line)
      line.match?(/\A(?:if|unless|case|begin|class|module|def|while|until|for)(?:\s|\z)/) ||
        line.match?(/\bbegin\b/) || line.match?(/\bdo(?:\s*\|[^|]*\|)?\s*(?:#.*)?\z/)
    end

    def add_views(action)
      initial_count = @views.length
      add_explicit_views(action)
      add_conventional(action) unless explicit_views_added?(initial_count)
    end

    def add_explicit_views(action)
      action.render_lines.each do |line, source_line, source|
        explicit_view(RenderCall.new(action, source_line), line, source)
      end
    end

    def explicit_views_added?(initial_count)
      @views.length > initial_count
    end

    def add_conventional(action)
      action.conventional_paths(@source).each do |view_path|
        candidate = action.view_candidate(view_path, action.line, "conventional")
        @views << candidate.to_row(@source)
      end
    end

    def explicit_view(render_call, line, source)
      return unless self.class.render_call?(line)

      handle_render(render_call, source)
    end

    def self.render_call?(line)
      line.match?(/\brender\b/) && !line.match?(/^\s*#/)
    end

    def handle_render(render_call, line)
      scanner = self.class
      target = scanner.render_target(line)
      return render_files(render_call, target) if target
      return unless scanner.dynamic_render?(line)

      record_dynamic_render(render_call)
    end

    def self.dynamic_render?(line)
      return false if line.match?(/\brender\s*\(?\s*(?:#.*)?$/)
      return true if line.match?(/\b[A-Z]\w*(?:::\w+)*\.render\s*\(/)

      !line.match?(/\brender\b[\s\S]*\b(?:json|plain|html|body|file|inline)\s*:/)
    end

    def record_dynamic_render(render_call)
      evidence = @source.evidence(render_call.action.path, render_call.line)
      @unresolved << { "kind" => "dynamic_render", "evidence" => evidence }
    end

    def self.render_target(line)
      target = line[/\brender\s+(?:action:\s*)?["']([^"']+)["']/, 1] ||
        line[/\brender\s+(?:template|partial):\s*["']([^"']+)["']/, 1] ||
        line[/\brender\s+(?:action:\s*)?:([a-z_][a-z0-9_]*)\b/i, 1] ||
        line[/\brender\s+(?:template|partial):\s*:([a-z_][a-z0-9_]*)\b/i, 1] ||
        line[/\brender\s*\(\s*["']([^"']+)["']/, 1]
      target unless target&.include?('#{')
    end

    def render_files(render_call, target)
      action = render_call.action
      Dir.glob(action.render_pattern(@source, target)).sort.each do |view_path|
        candidate = action.view_candidate(view_path, render_call.line, "direct")
        @views << candidate.to_row(@source)
      end
    end

    def self.model_names(lines)
      source = masked_source(lines)
      names = source.scan(/\b[A-Z][A-Za-z0-9]*(?:::[A-Z][A-Za-z0-9]*)*\b/)
      components = names.join(" ").scan(/\b[A-Z][A-Za-z0-9]*\b/)
      (names + components).uniq
    end

    def self.masked_source(lines)
      source = lines.map { |line| masked_line(line) }.join
      source.gsub(/#.*$/, "")
    end

    def self.masked_line(line)
      interpolations = line.scan(/#\{([^}]*)\}/).flatten.join(" ")
      code = line.gsub(/#\{[^}]*\}/, "")
      strip_strings(code) + strip_strings(interpolations)
    end

    def self.strip_strings(source)
      source.gsub(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/, "")
    end
  end

  # One rewritten inline route and its inherited context.
  InlineRoute = Struct.new(:line, :context)
  # Builds the route line and scope used for inline member declarations.
  class InlineRouteContext
    def self.from(source_line, parent)
      return unless parent

      kind, text = source_line.inline_route
      inline_context = context(kind, parent)
      InlineRoute.new(route_line(source_line, text, inline_context), inline_context)
    end

    def self.route_line(source_line, text, inline_context)
      RouteLine.new(source_line.path, source_line.line, text, text, inline_context)
    end

    def self.context(kind, parent)
      prefix = parent.path_prefix
      path = kind == "member" ? RouteScope.append_path(prefix, ":id") : prefix
      RouteContext.new(parent.resource, kind, path, parent.module_prefix, parent.controller_name)
    end
  end
  # Expands one resource declaration under the current route scope.
  class ResourceRouteEmitter
    def initialize(source, contexts, routes)
      @source, @contexts, @routes = source, contexts, routes
    end

    def call(declaration, actions)
      scope = RouteScope.new(@contexts.prefix_for_resource, @contexts.module_path)
      actions.each { |action| @routes.concat(declaration.rows_for(action, @source, scope)) }
    end
  end
  # Records uncertainty evidence from route declarations.
  class RouteUncertaintyReporter
    def initialize(source, unresolved)
      @source, @unresolved = source, unresolved
    end

    def call(source_line, kind = "dynamic_route", line = source_line.line)
      @unresolved << { "kind" => kind, "evidence" => @source.evidence(source_line.path, line) }
    end

    def scope(line)
      kind = line.scope_uncertainty
      call(line, kind) if kind
      return unless line.inline_iteration_route?

      call(line)
      call(line, "unsupported_route_option")
    end

    def dynamic(declaration)
      line = declaration.line
      explicit_route = line.route_declaration? && !line.resource?
      unsupported_options(line) if explicit_route
      call(line)
    end

    def unsupported_options(line)
      line.unsupported_option_lines.each { |number| call(line, "unsupported_route_option", number) }
    end
  end
  # Holds the public route result arrays.
  RouteScanResult = Struct.new(:routes, :unresolved)
  # Applies evidence and context changes for one ordinary route line.
  RouteLineFlow = Struct.new(:uncertainty, :contexts, :source, :routes) do
    def call(line)
      uncertainty.scope(line)
      routes.concat(MemberRouteEmitter.rows(line, self))
      RouteDeclaration.new(line, line.read)
    end
  end
  # Finds literal and conventional routes, and marks dynamic route declarations.
  class RouteScanner
    RESOURCE_ACTIONS = {
      "index" => [%w[GET], ""], "create" => [%w[POST], ""], "new" => [%w[GET], "/new"],
      "show" => [%w[GET], "/:id"], "edit" => [%w[GET], "/:id/edit"],
      "update" => [%w[PATCH PUT], "/:id"], "destroy" => [%w[DELETE], "/:id"]
    }.freeze

    def initialize(source)
      @source = source
      @result = RouteScanResult.new([], [])
      @contexts = RouteContextStack.new
      @uncertainty = RouteUncertaintyReporter.new(@source, @result.unresolved)
    end

    def routes
      @result.routes
    end

    def unresolved
      @result.unresolved
    end

    def scan
      path = File.join(@source.root, "config/routes.rb")
      return unless File.file?(path)

      scan_file(path, File.readlines(path))
    end

    private

    def scan_line(source_line)
      return scan_inline_route(source_line) if source_line.inline_route

      declaration = RouteLineFlow.new(@uncertainty, @contexts, @source, routes).call(source_line)
      route_reading(declaration)
      @contexts.update(source_line)
    end

    def scan_inline_route(source_line)
      inline = InlineRouteContext.from(source_line, @contexts.current(source_line))
      scan_line(inline.line) if inline
    end

    def scan_file(path, lines)
      lines.each_with_index do |line, index|
        option_text = [line, *RouteLine.continuation_lines(lines, index)].join
        scan_line(RouteLine.new(path, index + 1, line, option_text))
      end
    end

    def route_reading(declaration)
      return if declaration.suppressed?(@contexts)

      return @uncertainty.dynamic(declaration) if declaration.reading.dynamic?

      if declaration.warning?
        @uncertainty.unsupported_options(declaration.line)
        return emit_reading(declaration)
      end

      emit_route_reading(declaration)
    end

    def emit_route_reading(declaration)
      dynamic_condition = @contexts.contains_kind?("dynamic_condition")
      return if dynamic_condition && declaration.reading.kind != :other

      emit_reading(declaration)
    end

    def emit_reading(declaration)
      line, kind, value = declaration.to_a
      return add(line, value) if kind == :route
      return value.each { |target| add(line, target) } if kind == :routes
      return ResourceRouteEmitter.new(@source, @contexts, routes).call(*value) if kind == :resource
    end

    def add(source_line, target)
      context = source_line.inline_context || @contexts.current(source_line)
      path = context ? context.path_prefix : @contexts.route_path
      scoped = target.within(path, @contexts.module_path)
      routes << scoped.to_row(source_line, @source)
    end

    def uncertain(source_line, kind = "dynamic_route")
      @uncertainty.call(source_line, kind)
    end

    def uncertain_at(source_line, line, kind)
      @uncertainty.call(source_line, kind, line)
    end

  end

  # Finds model files and statically declared associations.
  class ModelScanner
    attr_reader :models, :associations, :unresolved

    ASSOCIATION_MACROS = %w[has_many has_one belongs_to has_and_belongs_to_many].freeze

    def initialize(source)
      @source = source
      @models = []
      @associations = []
      @unresolved = []
    end

    def scan
      directory = "app/models"
      paths = @source.files(directory)
      paths.each do |path|
        scan_file(path) unless path.include?("/concerns/")
      end
      @unresolved.concat(ThroughAssociationGraph.new(@associations).resolve)
    end

    private

    def scan_file(path)
      lines = File.readlines(path)
      name = model_name(path)
      @models << { "name" => name, "source" => @source.evidence(path, 1) }
      lines.each_with_index do |line, index|
        scan_association(ModelLine.new(path, index + 1, name, self.class.association_text(lines, index, line)))
      end
    end

    def self.association_text(lines, index, first_line)
      return first_line unless first_line.match?(/\A[ \t]*(?:has_many|has_one|belongs_to|has_and_belongs_to_many)\b/)

      indentation = first_line[/\A */].length
      first_line + continuation_lines(lines, index, indentation).join
    end

    def self.continuation_lines(lines, index, indentation)
      lines[(index + 1)..].take_while { |line| continuation_line?(line, indentation) }
    end

    def self.continuation_line?(line, indentation)
      line.strip.empty? || line[/\A */].length > indentation
    end

    def model_name(path)
      name = @source.relative(path).delete_prefix("app/models/").delete_suffix(".rb")
      Source.camel(name)
    end

    def scan_association(source_line)
      match = source_line.association_match
      return association(source_line, match) if match
      return unless source_line.association_macro?

      note_unresolved(source_line, "dynamic_association")
    end

    def association(source_line, match)
      line = source_line.text
      resolution = resolve_association(line, match)
      record = source_line.association_row(@source, match, resolution)
      @associations << record
      note_association_issue(source_line, resolution)
    end

    def note_association_issue(source_line, resolution)
      kind = source_line.through_kind
      return note_dynamic_path(source_line) if kind == "dynamic"
      return unless kind == "none"

      note_unresolved(source_line, "dynamic_association_target") if resolution.dynamic
    end

    def resolve_association(line, match)
      self.class.resolve(line, match)
    end

    def self.resolve(line, match)
      return dynamic_resolution if dynamic_association?(line)

      class_name = association_class_name(line)
      return explicit_resolution(class_name) if class_name

      inferred_resolution(match)
    end

    def self.dynamic_association?(line)
      line.include?("through:") || line.include?("polymorphic:") || line.match?(/class_name:\s*(?!["'])\S/)
    end

    def self.inferred_target(macro, name)
      belongs = macro == "belongs_to" || macro == "has_one"
      Source.camel(belongs ? name : name.sub(/ies\z/, "y").sub(/s\z/, ""))
    end

    def self.association_class_name(line)
      line[/class_name:\s*["']([^"']+)["']/, 1]
    end

    def self.dynamic_resolution
      AssociationResolution.new(nil, "unresolved", true)
    end

    def self.explicit_resolution(class_name)
      AssociationResolution.new(class_name, "direct", false)
    end

    def self.inferred_resolution(match)
      AssociationResolution.new(inferred_target(match[1], match[2]), "conventional", false)
    end

    def note_unresolved(source_line, kind)
      @unresolved << { "kind" => kind, "evidence" => @source.evidence(source_line.path, source_line.line_number) }
    end

    def note_dynamic_path(source_line)
      note_unresolved(source_line, "dynamic_association_target")
      note_unresolved(source_line, "dynamic_association_path")
    end
  end

  # Joins scanner results into the public, versioned JSON document.
  class Document
    def initialize(source, controllers, routes, models)
      @source = source
      @controllers = controllers
      @routes = routes
      @models = models
    end

    def build(target)
      document(target)
    end

    private

    def document(target)
      selected = selected_actions(target)
      views = matching_views(selected)
      models, names = selected_models(selected, target)
      { "schema_version" => 1, "actions" => selected, "routes" => matching_routes(selected),
        "views" => views, "models" => models,
        "associations" => selected_associations(names, target),
        "unresolved" => target ? related_unresolved(selected, views, models) : unresolved_rows }
    end

    def selected_actions(target)
      DocumentSelection.select(normalize_actions, target)
    end

    def selected_model_names(actions)
      actions.flat_map { |action| action["models"] + view_models(action) }.uniq
    end

    def normalize_actions
      rows = @controllers.actions.map { |row| self.class.normalize_action(row, known_models) }
      rows.sort_by { |row| row.values_at("controller", "action") }
    end

    def known_models
      @models.models.map { |model| model["name"] }
    end

    def self.normalize_action(row, known)
      controller, route_controller, action, source, names = row.values_at("controller", "route_controller", "action", "source", "models")
      { "controller" => controller, "route_controller" => route_controller, "action" => action,
        "source" => source, "models" => names.uniq.select { |name| known.include?(name) }.sort }
    end

    def view_models(action)
      paths = related_view_paths(action)
      Source.existing_paths(paths).flat_map { |path| ViewModelScanner.names(path) }
    end

    def related_view_paths(action)
      @controllers.views.select do |view|
        controller, view_action = view.values_at("controller", "action")
        controller == action["controller"] && view_action == action["action"]
      end.map { |view| File.join(@source.root, view.values_at("path")[0]) }
    end

    def matching_routes(actions)
      keys = DocumentSelection.route_keys(actions)
      request = RowQuery.new(keys, %w[controller action], %w[path verb controller action])
      RowSelection.match(@routes.routes, request)
    end

    def matching_views(actions)
      keys = DocumentSelection.view_keys(actions)
      request = RowQuery.new(keys, %w[controller action], %w[controller action path])
      RowSelection.match(@controllers.views, request)
    end

    def selected_models(actions, target)
      names = selected_model_names(actions)
      request = RowQuery.new(nil, nil, %w[name], "name", names, target)
      [RowSelection.related(@models.models, request), names]
    end

    def selected_associations(names, target)
      request = RowQuery.new(nil, nil, %w[model name], "model", names, target)
      RowSelection.related(@models.associations, request)
    end

    def unresolved_rows
      UnresolvedIssues.order(UnresolvedIssues.all(@controllers, @routes, @models))
    end

    def related_unresolved(actions, views, models)
      paths = DocumentSelection.issue_paths(actions, views, models)
      all_rows = UnresolvedIssues.all(@controllers, @routes, @models)
      UnresolvedIssues.order(UnresolvedIssues.related(all_rows, paths))
    end
  end

  # Reads model constants from Ruby code inside a view template.
  class ViewModelScanner
    def self.names(path)
      source_fragments(path).flat_map { |source| ControllerScanner.model_names(source.lines) }.uniq
    end

    def self.source_fragments(path)
      source = File.read(path)
      fragments = source.scan(/<%(?!#)(?:=)?(.*?)%>/m).flatten
      return fragments unless fragments.empty?

      [source]
    end
  end

  # Filters and orders unresolved evidence for output documents.
  class UnresolvedIssues
    def self.all(controllers, routes, models)
      controllers.unresolved + routes.unresolved + models.unresolved
    end

    def self.related(rows, paths)
      rows.select { |row| paths.include?(row.dig("evidence", "path")) }
    end

    def self.order(rows)
      rows.uniq.sort_by do |row|
        evidence = row.values_at("evidence")[0]
        [evidence["path"], evidence["line"], row.values_at("kind")[0]]
      end
    end
  end

  # Builds lookup keys from normalized actions.
  class DocumentSelection
    def self.select(actions, target)
      return actions unless target

      actions.select { |row| "#{row['controller']}##{row['action']}" == target }
    end

    def self.route_keys(actions)
      actions.map { |row| [row["route_controller"], row["action"]] }
    end

    def self.view_keys(actions)
      actions.map { |row| [row["controller"], row["action"]] }
    end

    def self.issue_paths(actions, views, models)
      tagged_rows = tagged_rows_for(actions, "source") + tagged_rows_for(views, "evidence") +
        tagged_rows_for(models, "source")
      tagged_rows.map { |row, field| row.dig(field, "path") } + ["config/routes.rb"]
    end

    def self.tagged_rows_for(rows, field)
      rows.map { |row| [row, field] }
    end
  end

  # Applies the same key and sort rules to each kind of document row.
  RowQuery = Struct.new(:keys, :fields, :sort_fields, :filter_field, :names, :target)
  # Selects and orders document rows from shared query rules.
  class RowSelection
    def self.match(rows, request)
      matching = rows.select { |row| request.keys.include?(row.values_at(*request.fields)) }
      matching.sort_by { |row| row.values_at(*request.sort_fields) }
    end

    def self.related(rows, request)
      selected = rows.select do |row|
        !request.target || request.names.include?(row[request.filter_field])
      end
      selected.sort_by { |row| row.values_at(*request.sort_fields) }
    end
  end

  # Coordinates the independent source scanners.
  class SpinelScanner
    def initialize(root)
      @source = Source.new(root)
    end

    def map(target = nil)
      ScannerSet.new(@source).document(target)
    end
  end

  # Holds the three independent scanners for one source tree.
  class ScannerSet
    attr_reader :controllers, :routes, :models

    def initialize(source)
      @source = source
      @controllers = ControllerScanner.new(source)
      @routes = RouteScanner.new(source)
      @models = ModelScanner.new(source)
    end

    def scan
      @controllers.scan
      @routes.scan
      @models.scan
    end

    def document(target)
      scan
      Document.new(@source, @controllers, @routes, @models).build(target)
    end
  end

  # Validates CLI arguments and writes the navigation document.
  class Command
    def initialize(arguments)
      @arguments = arguments
      @root = Dir.pwd
      @json = false
      @target = nil
    end

    def run
      execute
    rescue OptionParser::ParseError => error
      warn error.message
      2
    end

    def execute
      return 2 unless read_command
      return 2 unless valid_inputs?

      write_result(@target)
    end

    private

    def usage
      warn "usage: rails-map map|inspect [Controller#action] [--root PATH] [--json]"
      2
    end

    def invalid_target
      warn "inspect requires Controller#action"
      2
    end

    def read_command
      line = CommandLine.new(@arguments)
      return usage unless line.valid_command?
      return invalid_target unless line.valid_target?

      @target, @arguments = line.consume

      true
    end

    def parse_options
      parser = OptionParser.new
      add_root_option(parser)
      add_json_option(parser)
      parser.parse!(@arguments)
      true
    end

    def add_root_option(parser)
      parser.on("--root PATH") { |value| @root = value }
    end

    def add_json_option(parser)
      parser.on("--json") { @json = true }
    end

    def valid_inputs?
      return false unless parse_options
      return false unless valid_arguments?

      valid_root?
    end

    def valid_arguments?
      return true if @arguments.empty?

      warn "unexpected argument: #{@arguments.first}"
      false
    end

    def valid_root?
      return true if File.directory?(@root)

      warn "root is not a directory: #{@root}"
      false
    end

    def write_result(target)
      output = SpinelScanner.new(@root).map(target)
      return missing_action(target) if target && output["actions"].empty?

      puts(@json ? JSON.generate(output) : JSON.pretty_generate(output))
      0
    end

    def missing_action(target)
      warn "action not found: #{target}"
      1
    end
  end

  def self.main(arguments)
    Command.new(arguments).run
  end
end

exit RailsMap.main(ARGV)
