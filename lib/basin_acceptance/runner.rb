require "fileutils"
require "json"
require "securerandom"
require "tmpdir"

module BasinAcceptance
  class Runner
    Result = Struct.new(
      :failures,
      :wall_seconds,
      :peak_rss_bytes,
      :command_seconds,
      :command_rows,
      :artifact_dir,
      :skipped,
      :skip_reason,
      keyword_init: true
    ) do
      def passed?
        failures.empty?
      end

      def skipped?
        skipped == true
      end
    end

    def initialize(executable:, artifact_root:)
      @executable = executable
      @cli = Cli.new(executable)
      @artifact_root = File.expand_path(artifact_root)
    end

    def run(scenario)
      if scenario.skip_file && !File.exist?(scenario.skip_file)
        return Result.new(
          failures: [],
          wall_seconds: 0.0,
          peak_rss_bytes: 0,
          command_seconds: [],
          command_rows: [],
          artifact_dir: nil,
          skipped: true,
          skip_reason: scenario.skip_reason
        )
      end

      started = monotonic_time
      failures = []
      observations = []
      @running_process = nil
      work_dir = Dir.mktmpdir("basin-acceptance-#{scenario.name}-")
      context = Context.new(scenario, work_dir)
      providers = Providers.new(context)
      # Every command of this scenario runs against the resources the context
      # named, so the CLI environment is rebuilt for each scenario.
      @cli = Cli.new(@executable, environment: context.cli_environment)
      providers.prepare(scenario.services)

      Array(scenario.fixtures).each do |fixture|
        prepare_fixture(fixture, context, scenario, started) if fixture.generator
        sql = context.render(File.read(fixture.file))
        providers.execute(
          fixture.provider,
          sql,
          timeout: remaining_time(scenario, started)
        )
      end

      scenario.commands.each_with_index do |command, index|
        command.before_actions.each do |action|
          providers.execute(
            action.provider,
            context.render(action.sql),
            timeout: remaining_time(scenario, started)
          )
        end
        config_path = render_config(command, scenario, context, index)
        if command.interface == :continuous
          observation, command_failures = run_continuous(
            command,
            config_path,
            scenario,
            context,
            providers,
            started,
            "command #{index + 1}"
          )
          observations << observation unless observation.nil?
          failures.concat(command_failures)
          next
        end

        arguments, stdin_data = invocation(command, config_path, context)
        observation = @cli.run(
          arguments,
          timeout: remaining_time(scenario, started),
          stdin_data: stdin_data
        )
        observations << observation
        failures.concat(check(command, observation, "command #{index + 1}", context))
        failures.concat(
          check_missing_at_source(
            command,
            config_path,
            context,
            "command #{index + 1}",
            timeout: remaining_time(scenario, started)
          )
        )

        next unless command.replay_identically? && failures.empty?

        replay = @cli.run(
          arguments,
          timeout: remaining_time(scenario, started),
          stdin_data: stdin_data
        )
        observations << replay
        failures.concat(check(command, replay, "command #{index + 1} replay", context))
        if replay.exit_code != observation.exit_code || replay.stdout != observation.stdout
          failures << "command #{index + 1} replay did not produce identical exit and stdout"
        end
      end

      Array(scenario.row_comparisons).each_with_index do |comparison, index|
        if comparison.streaming
          failure = compare_streaming_rows(
            comparison,
            providers,
            context,
            timeout: remaining_time(scenario, started),
            index: index
          )
          failures << failure unless failure.nil?
          next
        end

        source_rows = providers.rows(
          comparison.source_provider,
          context.render(comparison.source_sql),
          timeout: remaining_time(scenario, started)
        )
        sink_rows = providers.rows(
          comparison.sink_provider,
          context.render(comparison.sink_sql),
          timeout: remaining_time(scenario, started)
        )
        next if source_rows == sink_rows

        failures << "row comparison #{index + 1} differed: source=#{source_rows.inspect} sink=#{sink_rows.inspect}"
      end

      Array(scenario.query_expectations).each_with_index do |expectation, index|
        actual = providers.rows(
          expectation.provider,
          context.render(expectation.sql),
          timeout: remaining_time(scenario, started)
        )
        next if actual == expectation.rows

        failures << "query expectation #{index + 1} differed: expected=#{expectation.rows.inspect} actual=#{actual.inspect}"
      end

      peak_rss_bytes = peak_rss_bytes(observations)
      if scenario.rss_bytes && peak_rss_bytes > scenario.rss_bytes
        failures << format(
          "peak CLI RSS was %.1f MiB, over the %.1f MiB ceiling",
          peak_rss_bytes.fdiv(1024 * 1024),
          scenario.rss_bytes.fdiv(1024 * 1024)
        )
      end

      artifact_dir = if failures.empty?
                       nil
                     else
                       retain_artifacts(scenario, work_dir, observations)
                     end
      Result.new(
        failures: failures,
        wall_seconds: monotonic_time - started,
        peak_rss_bytes: peak_rss_bytes,
        command_seconds: command_seconds(observations),
        command_rows: command_rows(scenario, context),
        artifact_dir: artifact_dir
      )
    rescue StandardError => error
      failures ||= []
      failures << "runner error: #{error.class}: #{error.message}"
      peak_rss_bytes = peak_rss_bytes(observations || [])
      artifact_dir = retain_artifacts(scenario, work_dir, observations || []) if work_dir
      Result.new(
        failures: failures,
        wall_seconds: monotonic_time - started,
        peak_rss_bytes: peak_rss_bytes,
        command_seconds: command_seconds(observations || []),
        command_rows: context ? command_rows(scenario, context) : [],
        artifact_dir: artifact_dir
      )
    ensure
      @running_process&.terminate
      @running_process = nil
      providers&.cleanup(scenario.services)
      FileUtils.remove_entry(work_dir) if work_dir && File.exist?(work_dir)
    end

    private

    def prepare_fixture(fixture, context, scenario, started)
      puts "Preparing fixture #{fixture.name} (downloads are checksummed and cached)..."
      generator = Cli.new(fixture.generator)
      result = generator.run(
        [context.work_dir, context.fetch("large_rows")],
        timeout: remaining_time(scenario, started),
        stream_output: true
      )
      if result.exit_code.zero? && !result.timed_out
        puts format("Fixture %s ready (%.1fs)", fixture.name, result.wall_seconds)
        return
      end

      raise Error,
            "fixture generator #{fixture.name} failed with exit #{result.exit_code}: #{result.stderr.strip}"
    end

    def run_continuous(command, config_path, scenario, context, providers, started, label)
      raise Error, "continuous command requires a config" if config_path.nil?

      arguments = command.arguments.map { |argument| context.render(argument) }
      arguments.concat(["-c", config_path])
      @running_process = @cli.start(arguments)
      failures = []

      if command.readiness
        outcome, detail = poll_process(
          @running_process,
          timeout: condition_timeout(command, scenario, started)
        ) do |poll_timeout|
          rows = providers.rows(
            command.readiness.provider,
            context.render(command.readiness.sql),
            timeout: poll_timeout
          )
          [rows == command.readiness.rows, rows]
        end
        early = continuous_poll_failure(outcome, detail, "#{label} readiness", failures)
        return finish_continuous(command, label, failures, early) unless early.nil?
      end

      command.gates.each_with_index do |gate, gate_index|
        gate.actions.each do |action|
          providers.execute(
            action.provider,
            context.render(action.sql),
            timeout: remaining_time(scenario, started)
          )
        end
        unless gate.query.nil?
          outcome, detail = poll_process(
            @running_process,
            timeout: condition_timeout(command, scenario, started)
          ) do |poll_timeout|
            rows = providers.rows(
              gate.query.provider,
              context.render(gate.query.sql),
              timeout: poll_timeout
            )
            [rows == gate.query.rows, rows]
          end
          early = continuous_poll_failure(
            outcome,
            detail,
            "#{label} gate #{gate_index + 1} query",
            failures
          )
          return finish_continuous(command, label, failures, early) unless early.nil?
        end

        if gate.wait_for_exit
          observation = @running_process.wait(
            timeout: remaining_time(scenario, started)
          )
          @running_process = nil
          failures.concat(check(command, observation, label, context))
          return [observation, failures]
        end
        next if gate.status.nil?

        outcome, detail = poll_process(
          @running_process,
          timeout: condition_timeout(command, scenario, started)
        ) do |poll_timeout|
          status = read_status(config_path, timeout: poll_timeout)
          [status_matches?(status, gate.status), status]
        end
        early = continuous_poll_failure(
          outcome,
          detail,
          "#{label} gate #{gate_index + 1}",
          failures
        )
        return finish_continuous(command, label, failures, early) unless early.nil?
      end

      @running_process.signal(command.shutdown_signal)
      observation = @running_process.wait(timeout: remaining_time(scenario, started))
      @running_process = nil
      failures.concat(check(command, observation, label, context))
      [observation, failures]
    end

    def poll_process(process, timeout:)
      deadline = monotonic_time + timeout
      last = nil
      loop do
        exited = process.wait(timeout: 0.001, terminate_on_timeout: false)
        return [:exited, exited] unless exited.nil?

        remaining = deadline - monotonic_time
        return [:timeout, last] unless remaining.positive?

        begin
          matched, last = yield([remaining, 1.0].min)
          return [:matched, last] if matched
        rescue Error => error
          last = error.message
        end
        sleep([0.05, remaining].min)
      end
    end

    def condition_timeout(command, scenario, started)
      [command.wait_timeout_seconds, remaining_time(scenario, started)].min
    end

    def continuous_poll_failure(outcome, detail, label, failures)
      return nil if outcome == :matched

      if outcome == :exited
        failures << "#{label}: process exited before the condition matched"
        return detail
      end

      failures << "#{label}: condition did not match; last observation=#{detail.inspect}"
      observation = @running_process.terminate
      @running_process = nil
      observation
    end

    def finish_continuous(command, label, failures, observation)
      @running_process = nil if observation && !@running_process&.running?
      failures.concat(check(command, observation, label, nil)) unless observation.nil?
      [observation, failures]
    end

    def read_status(config_path, timeout:)
      result = @cli.run(
        ["status", "--json", "-c", config_path],
        timeout: timeout
      )
      raise Error, "status exited #{result.exit_code}: #{result.stderr.strip}" unless result.exit_code.zero?

      JSON.parse(result.stdout)
    rescue JSON::ParserError => error
      raise Error, "status did not emit JSON: #{error.message}"
    end

    def check_missing_at_source(command, config_path, context, label, timeout:)
      expected = command.missing_at_source
      return [] if expected.empty?

      if config_path.nil?
        return ["#{label} expects missing_at_source but ran without a config"]
      end

      report = read_status(config_path, timeout: timeout)
      observed = Array(report["missing_at_source"]).map do |entry|
        {namespace: entry["namespace"], name: entry["name"]}
      end
      expected.filter_map do |collection|
        rendered = {
          namespace: context.render(collection[:namespace]),
          name: context.render(collection[:name])
        }
        next if observed.include?(rendered)

        "#{label} did not report #{rendered[:namespace]}.#{rendered[:name]} under " \
          "missing_at_source; observed #{observed.inspect}"
      end
    end

    def status_matches?(report, expected)
      expected.all? do |field, value|
        actual = case field
                 when :acknowledged, :received
                   report.dig("positions", field.to_s)
                 else
                   report[field.to_s]
                 end
        case value
        when :present then !actual.nil?
        when :absent then actual.nil?
        else actual == value
        end
      end
    end

    def invocation(command, config_path, context)
      return cli_invocation(command, config_path, context) if command.interface == :cli
      return protocol_invocation(config_path) if command.interface == :protocol

      raise Error, "unknown command interface: #{command.interface}"
    end

    def cli_invocation(command, config_path, context)
      arguments = command.arguments.map { |argument| context.render(argument) }
      arguments.concat(["-c", config_path]) if config_path
      [arguments, nil]
    end

    def protocol_invocation(config_path)
      raise Error, "protocol command requires a config" if config_path.nil?

      config = JSON.parse(File.read(config_path))
      frames = [
        envelope("hello", "hello", supported_versions: [1]),
        envelope("validate", "validate", config: config),
        envelope("status", "status"),
        envelope("stop", "stop")
      ]
      [[], frames.map { |frame| JSON.generate(frame) }.join("\n") + "\n"]
    end

    def envelope(id, type, payload = nil)
      frame = {protocol: 1, id: id, type: type}
      frame[:payload] = payload unless payload.nil?
      frame
    end

    def render_config(command, scenario, context, index)
      return nil if command.config.nil?

      source = File.join(scenario.directory, command.config)
      rendered = context.render(File.read(source))
      JSON.parse(rendered)
      target = File.join(context.work_dir, "config-#{index + 1}.json")
      File.write(target, rendered)
      target
    end

    def check(command, observation, label, context)
      failures = []
      if observation.timed_out
        failures << "#{label} exceeded its wall budget"
        return failures
      end
      if observation.exit_code != command.expected_exit
        failures << "#{label} exited #{observation.exit_code}, expected #{command.expected_exit}"
      end

      frames = json_frames(observation.stdout)
      errors = reported_errors(command, frames)
      if command.minimum_errors && errors.length < command.minimum_errors
        failures << "#{label} reported #{errors.length} errors, expected at least #{command.minimum_errors}"
      end
      if command.maximum_errors && errors.length > command.maximum_errors
        failures << "#{label} reported #{errors.length} errors, expected at most #{command.maximum_errors}"
      end
      codes = errors.filter_map { |error| error["code"] }
      paths = errors.filter_map { |error| error["path"] }
      (command.error_codes - codes).each do |code|
        failures << "#{label} did not report error code #{code}"
      end
      (command.error_paths - paths).each do |path|
        failures << "#{label} did not report error path #{path}"
      end
      if command.once_status
        actual = frames.find { |frame| frame.key?("once") }&.fetch("once")
        if actual != command.once_status
          failures << "#{label} reported once status #{actual.inspect}, expected #{command.once_status}"
        end
      end
      check_protocol(command, frames, failures, label) if command.interface == :protocol
      check_discovery(command, observation.stdout, failures, label, context)
      check_query(command, observation.stdout, failures, label)
      failures
    end

    def check_query(command, stdout, failures, label)
      expected = command.query_rows
      return if expected.nil?

      frames = stdout.lines.filter_map do |line|
        text = line.strip
        next if text.empty?

        JSON.parse(text)
      end
      rows = frames.filter_map do |frame|
        frame["row"] if frame["type"] == "row"
      end
      failures << "#{label} query rows differed: expected=#{expected.inspect} actual=#{rows.inspect}" unless rows == expected

      summaries = frames.filter { |frame| frame["type"] == "summary" }
      if summaries.length != 1
        failures << "#{label} emitted #{summaries.length} query summaries, expected 1"
        return
      end
      reported_rows = summaries.fetch(0).dig("summary", "rows")
      if reported_rows != rows.length
        failures << "#{label} query summary reported #{reported_rows.inspect} rows, observed #{rows.length}"
      end
    rescue JSON::ParserError => error
      failures << "#{label} did not emit query JSON Lines: #{error.message}"
    end

    def check_discovery(command, stdout, failures, label, context)
      expected = command.discovery_expectation
      return if expected.nil?

      report = JSON.parse(stdout)
      if report["source_kind"] != expected.fetch(:source)
        failures << "#{label} discovered source #{report['source_kind'].inspect}, expected #{expected.fetch(:source)}"
      end

      collections = report["collections"]
      unless collections.is_a?(Array)
        failures << "#{label} discovery report did not contain a collections array"
        return
      end

      expected_collections = expected.fetch(:collections)
      if collections.length != expected_collections.length
        failures << "#{label} discovered #{collections.length} collections, expected #{expected_collections.length}"
      end
      expected_collections.each do |collection|
        namespace = context.render(collection.fetch(:namespace))
        name = context.render(collection.fetch(:name))
        actual = collections.find do |candidate|
          candidate["namespace"] == namespace && candidate["name"] == name
        end
        if actual.nil?
          failures << "#{label} did not discover #{namespace}.#{name}"
          next
        end
        if actual["key"] != collection.fetch(:key)
          failures << "#{label} discovered key #{actual['key'].inspect} for #{namespace}.#{name}, expected #{collection.fetch(:key).inspect}"
        end
        if actual["capture_eligible"] != collection.fetch(:eligible)
          failures << "#{label} discovered capture_eligible=#{actual['capture_eligible'].inspect} for #{namespace}.#{name}, expected #{collection.fetch(:eligible)}"
        end
        unless collection[:warnings].nil?
          warnings = actual.fetch("warnings", []).filter_map { |warning| warning["code"] }
          if warnings != collection.fetch(:warnings)
            failures << "#{label} discovered warnings #{warnings.inspect} for #{namespace}.#{name}, expected #{collection.fetch(:warnings).inspect}"
          end
        end
        collection[:native_types]&.each do |column_name, native_type|
          column = actual.fetch("columns", []).find do |candidate|
            candidate["name"] == column_name
          end
          if column.nil?
            failures << "#{label} did not discover column #{namespace}.#{name}.#{column_name}"
          elsif column["native_type"] != native_type
            failures << "#{label} discovered native type #{column['native_type'].inspect} for #{namespace}.#{name}.#{column_name}, expected #{native_type.inspect}"
          end
        end
      end

      selection = expected.fetch(:selection).map { |name| context.render(name) }
      actual_selection = report.dig("selection_hint", "include_tables")
      if actual_selection != selection
        failures << "#{label} reported selection #{actual_selection.inspect}, expected #{selection.inspect}"
      end
    rescue JSON::ParserError => error
      failures << "#{label} did not emit one discovery JSON document: #{error.message}"
    end

    def reported_errors(command, frames)
      if command.interface == :protocol
        result = frames.find { |frame| frame["type"] == "validation_result" }
        errors = result&.dig("payload", "errors")
        return errors.is_a?(Array) ? errors : []
      end

      frames.flat_map do |frame|
        errors = frame["errors"].is_a?(Array) ? frame["errors"] : []
        # A needs-attention summary carries one attention report rather than a
        # validation error list; surface it so expect_error_codes can pin
        # attention codes too.
        frame["attention"].is_a?(Hash) ? errors + [frame["attention"]] : errors
      end
    end

    def check_protocol(command, frames, failures, label)
      if command.protocol_version
        actual = frames.find { |frame| frame["type"] == "hello_ack" }
                       &.dig("payload", "negotiated_version")
        if actual != command.protocol_version
          failures << "#{label} negotiated protocol #{actual.inspect}, expected #{command.protocol_version}"
        end
      end
      return unless command.status_state

      actual = frames.find { |frame| frame["type"] == "status" }
                     &.dig("payload", "state")
      if actual != command.status_state
        failures << "#{label} reported status state #{actual.inspect}, expected #{command.status_state}"
      end
    end

    def json_frames(text)
      text.lines.filter_map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    def retain_artifacts(scenario, work_dir, observations)
      token = "#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{Process.pid}-#{SecureRandom.hex(3)}"
      directory = File.join(@artifact_root, scenario.name, token)
      FileUtils.mkdir_p(directory)
      Dir[File.join(work_dir, "config-*.json")].each do |config|
        FileUtils.cp(config, directory)
      end
      observations.each_with_index do |observation, index|
        File.write(File.join(directory, "command-#{index + 1}.json"), JSON.pretty_generate(
          argv: observation.argv,
          exit_code: observation.exit_code,
          timed_out: observation.timed_out,
          wall_seconds: observation.wall_seconds,
          peak_rss_bytes: observation.peak_rss_bytes
        ))
        File.write(File.join(directory, "stdout-#{index + 1}.log"), observation.stdout)
        File.write(File.join(directory, "stderr-#{index + 1}.log"), observation.stderr)
      end
      directory
    end

    def compare_streaming_rows(comparison, providers, context, timeout:, index:)
      source = providers.row_stream(
        comparison.source_provider,
        context.render(comparison.source_sql),
        timeout: timeout
      )
      sink = providers.row_stream(
        comparison.sink_provider,
        context.render(comparison.sink_sql),
        timeout: timeout
      )
      row_number = 0
      loop do
        source_row = source.next_row
        sink_row = sink.next_row
        return nil if source_row.nil? && sink_row.nil?

        row_number += 1
        next if source_row == sink_row

        return "row comparison #{index + 1} differed at row #{row_number}: " \
               "source=#{source_row.inspect} sink=#{sink_row.inspect}"
      end
    ensure
      source&.close
      sink&.close
    end

    def peak_rss_bytes(observations)
      observations.filter_map(&:peak_rss_bytes).max || 0
    end

    # Per-CLI-command wall seconds in invocation order, so a scale scenario's
    # PASS line yields a throughput denominator without the seeding and
    # verification time.
    def command_seconds(observations)
      observations.filter_map(&:wall_seconds)
    end

    def command_rows(scenario, context)
      scenario.commands.map do |command|
        next if command.measured_rows.nil?

        Integer(context.render(command.measured_rows))
      end
    end

    def remaining_time(scenario, started)
      remaining = scenario.wall_seconds - (monotonic_time - started)
      raise Error, "#{scenario.name}: scenario exceeded its wall budget" unless remaining.positive?

      remaining
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
