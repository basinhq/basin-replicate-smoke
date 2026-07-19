require "minitest/autorun"
require "basin_acceptance"
require "fileutils"
require "tmpdir"

class RunnerTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_runs_the_migrated_scenario_and_its_replay
    Dir.mktmpdir("basin-acceptance-runner-test-") do |directory|
      executable = File.join(directory, "fake-cli")
      File.write(executable, <<~RUBY)
        #!/usr/bin/env ruby
        require "json"
        puts JSON.generate(errors: [
          {code: "config.unknown_variant", path: "/worker/lease_overlap"},
          {code: "worker.unknown_connector", path: "/source/kind"},
          {code: "worker.unknown_connector", path: "/sink/kind"}
        ])
        exit 65
      RUBY
      FileUtils.chmod(0o755, executable)
      scenario = BasinAcceptance::ScenarioFile.load(
        File.join(ROOT, "scenarios", "validation-rejects", "scenario.rb")
      )
      runner = BasinAcceptance::Runner.new(
        executable: executable,
        artifact_root: File.join(directory, "artifacts")
      )

      result = runner.run(scenario)

      assert result.passed?, result.failures.join("\n")
      assert_nil result.artifact_dir
      refute File.exist?(File.join(directory, "artifacts"))
    end
  end

  def test_retains_artifacts_for_a_failed_scenario
    Dir.mktmpdir("basin-acceptance-runner-test-") do |directory|
      executable = File.join(directory, "fake-cli")
      File.write(executable, "#!/usr/bin/env ruby\nputs '{}'")
      FileUtils.chmod(0o755, executable)
      command = BasinAcceptance::Command.new(["run-once"], nil)
      command.expect_exit(65)
      scenario = BasinAcceptance::Scenario.new(
        name: "failure-artifacts",
        tier: :smoke,
        wall_seconds: 1,
        directory: directory,
        commands: [command]
      )
      runner = BasinAcceptance::Runner.new(
        executable: executable,
        artifact_root: File.join(directory, "artifacts")
      )

      result = runner.run(scenario)

      refute result.passed?
      assert File.file?(File.join(result.artifact_dir, "command-1.json"))
      assert File.file?(File.join(result.artifact_dir, "stdout-1.log"))
      assert File.file?(File.join(result.artifact_dir, "stderr-1.log"))
    end
  end

  def test_checks_a_discovery_report
    Dir.mktmpdir("basin-acceptance-runner-test-") do |directory|
      executable = File.join(directory, "fake-cli")
      File.write(executable, <<~'RUBY')
        #!/usr/bin/env ruby
        require "json"
        puts JSON.generate(
          source_kind: "postgres",
          collections: [
            {
              namespace: "public",
              name: "orders",
              key: ["id"],
              capture_eligible: true
            }
          ],
          selection_hint: {include_tables: ["public.orders"]}
        )
      RUBY
      FileUtils.chmod(0o755, executable)
      command = BasinAcceptance::Command.new(["discover", "--json"], nil)
      command.expect_discovery(
        source: "postgres",
        collections: [
          {namespace: "public", name: "orders", key: ["id"], eligible: true}
        ],
        selection: ["public.orders"]
      )
      scenario = BasinAcceptance::Scenario.new(
        name: "discovery",
        tier: :smoke,
        wall_seconds: 1,
        directory: directory,
        commands: [command]
      )
      runner = BasinAcceptance::Runner.new(
        executable: executable,
        artifact_root: File.join(directory, "artifacts")
      )

      result = runner.run(scenario)

      assert result.passed?, result.failures.join("\n")
    end
  end

  def test_enforces_the_cli_process_group_memory_budget
    Dir.mktmpdir("basin-acceptance-runner-test-") do |directory|
      executable = File.join(directory, "fake-cli")
      File.write(executable, <<~RUBY)
        #!/usr/bin/env ruby
        allocation = "x" * (8 * 1024 * 1024)
        sleep 0.1
        puts "{}" if allocation.bytesize.positive?
      RUBY
      FileUtils.chmod(0o755, executable)
      scenario = BasinAcceptance::Scenario.new(
        name: "memory-budget",
        tier: :extended,
        wall_seconds: 1,
        rss_bytes: 1024 * 1024,
        directory: directory,
        commands: [BasinAcceptance::Command.new([], nil)]
      )
      runner = BasinAcceptance::Runner.new(
        executable: executable,
        artifact_root: File.join(directory, "artifacts")
      )

      result = runner.run(scenario)

      refute result.passed?
      assert_operator result.peak_rss_bytes, :>, scenario.rss_bytes
      assert_includes result.failures.join("\n"), "peak CLI RSS"
    end
  end

  def test_skips_when_the_declared_fixture_is_absent
    Dir.mktmpdir("basin-acceptance-runner-test-") do |directory|
      executable = File.join(directory, "fake-cli")
      File.write(executable, "#!/usr/bin/env ruby\nexit 1")
      FileUtils.chmod(0o755, executable)
      scenario = BasinAcceptance::Scenario.new(
        name: "absent-fixture",
        tier: :extended,
        wall_seconds: 1,
        directory: directory,
        commands: [BasinAcceptance::Command.new(["run-once"], nil)],
        skip_file: File.join(directory, "missing.csv"),
        skip_reason: "fixture not built"
      )
      runner = BasinAcceptance::Runner.new(
        executable: executable,
        artifact_root: File.join(directory, "artifacts")
      )

      result = runner.run(scenario)

      assert result.skipped?
      assert_equal "fixture not built", result.skip_reason
      assert_empty result.failures
    end
  end

  def test_runs_when_the_declared_fixture_is_present
    Dir.mktmpdir("basin-acceptance-runner-test-") do |directory|
      executable = File.join(directory, "fake-cli")
      File.write(executable, "#!/usr/bin/env ruby\nputs '{}'")
      FileUtils.chmod(0o755, executable)
      fixture = File.join(directory, "present.csv")
      File.write(fixture, "row\n")
      scenario = BasinAcceptance::Scenario.new(
        name: "present-fixture",
        tier: :extended,
        wall_seconds: 1,
        directory: directory,
        commands: [BasinAcceptance::Command.new(["run-once"], nil)],
        skip_file: fixture,
        skip_reason: "fixture not built"
      )
      runner = BasinAcceptance::Runner.new(
        executable: executable,
        artifact_root: File.join(directory, "artifacts")
      )

      result = runner.run(scenario)

      refute result.skipped?
      assert result.passed?, result.failures.join("\n")
    end
  end

  def test_renders_placeholders_in_cli_arguments
    Dir.mktmpdir("basin-acceptance-runner-test-") do |directory|
      executable = File.join(directory, "fake-cli")
      File.write(executable, <<~'RUBY')
        #!/usr/bin/env ruby
        valid = ARGV.length == 3 &&
                ARGV.fetch(0) == "reset" &&
                ARGV.fetch(1) == "--table" &&
                ARGV.fetch(2).match?(/\Aargument_rendering_[a-f0-9]{8}_schema\.items\z/)
        puts "{}"
        exit(valid ? 0 : 64)
      RUBY
      FileUtils.chmod(0o755, executable)
      scenario = BasinAcceptance::Scenario.new(
        name: "argument-rendering",
        tier: :smoke,
        wall_seconds: 1,
        directory: directory,
        commands: [
          BasinAcceptance::Command.new(
            ["reset", "--table", "${schema}.items"],
            nil
          )
        ]
      )
      runner = BasinAcceptance::Runner.new(
        executable: executable,
        artifact_root: File.join(directory, "artifacts")
      )

      result = runner.run(scenario)

      assert result.passed?, result.failures.join("\n")
    end
  end
end
