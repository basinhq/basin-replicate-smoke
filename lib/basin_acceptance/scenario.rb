module BasinAcceptance
  SqlAction = Struct.new(:provider, :sql, keyword_init: true)
  Fixture = Struct.new(:provider, :name, :file, :generator, keyword_init: true)
  RowComparison = Struct.new(
    :source_provider,
    :source_sql,
    :sink_provider,
    :sink_sql,
    :streaming,
    keyword_init: true
  )
  QueryExpectation = Struct.new(:provider, :sql, :rows, keyword_init: true)
  ContinuousGate = Struct.new(
    :actions,
    :query,
    :status,
    :wait_for_exit,
    keyword_init: true
  )

  class ContinuousGateBuilder
    def initialize
      @actions = []
      @query = nil
      @status = nil
      @wait_for_exit = false
    end

    def before_sql(provider, sql)
      @actions << SqlAction.new(provider: provider.to_sym, sql: sql)
    end

    def wait_status(caught_up: nil, journal_depth: nil, received: nil, acknowledged: nil)
      @status = {
        caught_up: caught_up,
        journal_depth: journal_depth,
        received: received,
        acknowledged: acknowledged
      }.compact
    end

    def wait_query(provider, sql, rows:)
      @query = QueryExpectation.new(
        provider: provider.to_sym,
        sql: sql,
        rows: rows
      )
    end

    def wait_for_exit
      @wait_for_exit = true
    end

    def build
      ContinuousGate.new(
        actions: @actions.freeze,
        query: @query,
        status: @status&.freeze,
        wait_for_exit: @wait_for_exit
      )
    end
  end

  class Command
    attr_reader :interface, :arguments, :config, :expected_exit,
                :minimum_errors, :maximum_errors, :error_codes, :error_paths,
                :protocol_version, :status_state, :once_status, :before_actions,
                :discovery_expectation, :readiness, :gates, :shutdown_signal,
                :wait_timeout_seconds, :query_rows, :missing_at_source,
                :measured_rows

    def initialize(arguments, config, interface: :cli)
      @interface = interface
      @arguments = arguments.map(&:to_s).freeze
      @config = config
      @expected_exit = 0
      @minimum_errors = nil
      @maximum_errors = nil
      @error_codes = []
      @error_paths = []
      @protocol_version = nil
      @status_state = nil
      @once_status = nil
      @before_actions = []
      @discovery_expectation = nil
      @readiness = nil
      @gates = []
      @shutdown_signal = "TERM"
      @wait_timeout_seconds = 20.0
      @query_rows = nil
      @missing_at_source = []
      @measured_rows = nil
      @replay_identically = false
    end

    def expect_exit(code)
      @expected_exit = Integer(code)
    end

    def expect_error_count(at_least: nil, at_most: nil)
      @minimum_errors = Integer(at_least) unless at_least.nil?
      @maximum_errors = Integer(at_most) unless at_most.nil?
    end

    def expect_error_codes(*codes)
      @error_codes.concat(codes.map(&:to_s))
    end

    def expect_error_paths(*paths)
      @error_paths.concat(paths.map(&:to_s))
    end

    def expect_protocol_version(version)
      @protocol_version = Integer(version)
    end

    def expect_status_state(state)
      @status_state = state.to_s
    end

    def expect_once(status)
      @once_status = status.to_s
    end

    def expect_query_rows(rows)
      @query_rows = JSON.parse(JSON.generate(rows))
    end

    # Declares how many rows this CLI invocation processes so reports can
    # calculate throughput. Placeholders are rendered by the scenario context.
    def measure_rows(rows)
      @measured_rows = rows.to_s
    end

    # After the run, read `status --json` and require this collection to appear
    # under `missing_at_source` (a covered table dropped upstream that the pipeline
    # parked while still selected). Namespace and name are rendered with the
    # scenario bindings; call once per expected collection.
    def expect_missing_at_source(namespace:, name:)
      @missing_at_source << {namespace: namespace.to_s, name: name.to_s}
    end

    def before_sql(provider, sql)
      @before_actions << SqlAction.new(provider: provider.to_sym, sql: sql)
    end

    def before_sql_batches(provider, count:)
      count.times do |index|
        before_sql provider, yield(index, count)
      end
    end

    def expect_discovery(source:, collections:, selection:)
      @discovery_expectation = {
        source: source.to_s,
        collections: collections.map do |collection|
          {
            namespace: collection.fetch(:namespace).to_s,
            name: collection.fetch(:name).to_s,
            key: collection.fetch(:key).map(&:to_s),
            eligible: collection.fetch(:eligible),
            warnings: collection[:warnings]&.map(&:to_s),
            native_types: collection[:native_types]&.transform_keys(&:to_s)
          }
        end,
        selection: selection.map(&:to_s)
      }
    end

    def ready_when(provider, sql, rows:)
      @readiness = QueryExpectation.new(
        provider: provider.to_sym,
        sql: sql,
        rows: rows
      )
    end

    def gate(&block)
      builder = ContinuousGateBuilder.new
      builder.instance_eval(&block)
      @gates << builder.build
    end

    def shutdown_with(signal)
      @shutdown_signal = signal.to_s
    end

    def wait_timeout(seconds)
      @wait_timeout_seconds = Float(seconds)
      raise Error, "wait timeout must be positive" unless @wait_timeout_seconds.positive?
    end

    def replay_identically
      @replay_identically = true
    end

    def replay_identically?
      @replay_identically
    end
  end

  Scenario = Struct.new(
    :name,
    :tier,
    :wall_seconds,
    :rss_bytes,
    :directory,
    :services,
    :fixtures,
    :row_comparisons,
    :query_expectations,
    :commands,
    :skip_file,
    :skip_reason,
    keyword_init: true
  )

  class ScenarioBuilder
    VALID_TIERS = %i[smoke standard extended optional].freeze

    def initialize(name, directory)
      @name = name
      @directory = directory
      @tier = nil
      @wall_seconds = nil
      @rss_bytes = nil
      @services = []
      @fixtures = []
      @row_comparisons = []
      @query_expectations = []
      @commands = []
      @skip_file = nil
      @skip_reason = nil
    end

    def tier(value)
      value = value.to_sym
      raise Error, "#{@name}: unknown tier #{value}" unless VALID_TIERS.include?(value)

      @tier = value
    end

    def budget(wall:, rss_mb: nil)
      @wall_seconds = Float(wall)
      raise Error, "#{@name}: wall budget must be positive" unless @wall_seconds.positive?

      return if rss_mb.nil?

      rss_mb = Float(rss_mb)
      raise Error, "#{@name}: RSS budget must be positive" unless rss_mb.positive?

      @rss_bytes = (rss_mb * 1024 * 1024).to_i
    end

    def scale_budget(rss_mb: nil)
      budget wall: Context.scale_wall_seconds, rss_mb: rss_mb
    end

    def requires(*services)
      @services.concat(services.map(&:to_sym))
    end

    # Skip the scenario, rather than fail it, when a fixture built outside the
    # repository is not present. The path is resolved inside the runner
    # container, so it names the mounted fixture location.
    def skip_unless_file(path, reason:)
      @skip_file = path.to_s
      @skip_reason = reason.to_s
    end

    def fixture(provider, name)
      provider = provider.to_sym
      name = name.to_s
      unless name.match?(/\A[a-z][a-z0-9-]*\z/)
        raise Error, "#{@name}: invalid fixture name #{name.inspect}"
      end

      root = File.expand_path("../..", @directory)
      file = File.join(root, "fixtures", "sql", provider.to_s, "#{name}.sql")
      generator = File.join(root, "fixtures", "generators", name)
      generator = nil unless File.file?(generator)
      @fixtures << Fixture.new(
        provider: provider,
        name: name,
        file: file,
        generator: generator
      )
    end

    def expect_rows(source:, sink:, streaming: false)
      @row_comparisons << RowComparison.new(
        source_provider: source.fetch(0).to_sym,
        source_sql: source.fetch(1),
        sink_provider: sink.fetch(0).to_sym,
        sink_sql: sink.fetch(1),
        streaming: streaming
      )
    end

    def expect_query(provider, sql, rows:)
      @query_expectations << QueryExpectation.new(
        provider: provider.to_sym,
        sql: sql,
        rows: rows
      )
    end

    def cli(*arguments, config: nil, &block)
      command = Command.new(arguments, config)
      command.instance_eval(&block) if block
      @commands << command
    end

    def protocol(config:, &block)
      command = Command.new([], config, interface: :protocol)
      command.instance_eval(&block) if block
      @commands << command
    end

    def continuous(config:, &block)
      command = Command.new(
        ["run", "--heartbeat-interval", "0"],
        config,
        interface: :continuous
      )
      command.instance_eval(&block) if block
      @commands << command
    end

    def build
      raise Error, "#{@name}: tier is required" if @tier.nil?
      raise Error, "#{@name}: wall budget is required" if @wall_seconds.nil?
      raise Error, "#{@name}: at least one CLI command is required" if @commands.empty?

      @fixtures.each do |fixture|
        next if File.file?(fixture.file)

        raise Error, "#{@name}: unknown #{fixture.provider} fixture #{fixture.name.inspect}"
      end

      Scenario.new(
        name: @name,
        tier: @tier,
        wall_seconds: @wall_seconds,
        rss_bytes: @rss_bytes,
        directory: @directory,
        services: @services.uniq.freeze,
        fixtures: @fixtures.freeze,
        row_comparisons: @row_comparisons.freeze,
        query_expectations: @query_expectations.freeze,
        commands: @commands.freeze,
        skip_file: @skip_file,
        skip_reason: @skip_reason
      )
    end
  end

  class ScenarioFile
    def self.load(path)
      loader = new(path)
      loader.instance_eval(File.read(path), path, 1)
      loader.result
    rescue SystemCallError, SyntaxError => error
      raise Error, "cannot load #{path}: #{error.message}"
    end

    def initialize(path)
      @path = path
      @result = nil
    end

    def scenario(name, &block)
      raise Error, "#{@path}: defines more than one scenario" unless @result.nil?

      builder = ScenarioBuilder.new(name, File.dirname(@path))
      builder.instance_eval(&block)
      @result = builder.build
    end

    def result
      raise Error, "#{@path}: does not define a scenario" if @result.nil?

      @result
    end
  end
end
