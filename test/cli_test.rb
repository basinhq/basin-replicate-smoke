require "minitest/autorun"
require "basin_acceptance"
require "fileutils"
require "tmpdir"

class CliTest < Minitest::Test
  def with_executable(body)
    Dir.mktmpdir("basin-acceptance-cli-test-") do |directory|
      path = File.join(directory, "fake-cli")
      File.write(path, "#!/usr/bin/env ruby\n#{body}")
      FileUtils.chmod(0o755, path)
      yield path
    end
  end

  def test_captures_separate_streams_and_exit_code
    with_executable('puts "result"; warn "log"; exit 65') do |path|
      result = BasinAcceptance::Cli.new(path).run([], timeout: 1)

      assert_equal 65, result.exit_code
      assert_equal "result\n", result.stdout
      assert_equal "log\n", result.stderr
      refute result.timed_out
    end
  end

  def test_terminates_a_timed_out_process
    with_executable("sleep 10") do |path|
      result = BasinAcceptance::Cli.new(path).run([], timeout: 0.05)

      assert result.timed_out
      assert_operator result.wall_seconds, :<, 2
    end
  end

  def test_writes_supplied_standard_input
    with_executable("print STDIN.read.upcase") do |path|
      result = BasinAcceptance::Cli.new(path).run(
        [],
        timeout: 1,
        stdin_data: "hello\n"
      )

      assert_equal "HELLO\n", result.stdout
      assert_equal 0, result.exit_code
    end
  end

  def test_starts_and_signals_a_long_running_process
    body = <<~'RUBY'
      trap("TERM") { puts "drained"; exit 0 }
      File.write(ARGV.fetch(0), "ready")
      sleep
    RUBY
    with_executable(body) do |path|
      marker = "#{path}.ready"
      process = BasinAcceptance::Cli.new(path).start([marker])
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
      until File.exist?(marker)
        flunk "child did not become ready" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        Thread.pass
      end

      assert process.running?
      process.signal("TERM")
      result = process.wait(timeout: 1)

      assert_equal 0, result.exit_code
      assert_equal "drained\n", result.stdout
      refute result.timed_out
    ensure
      process&.terminate if process&.running?
    end
  end

  def test_sums_resident_memory_for_the_process_group
    Dir.mktmpdir("basin-acceptance-proc-test-") do |directory|
      write_process_status(directory, 101, process_group: 42, rss_kb: 100)
      write_process_status(directory, 102, process_group: 42, rss_kb: 50)
      write_process_status(directory, 103, process_group: 7, rss_kb: 1_000)

      memory = BasinAcceptance::Cli::ProcessGroupMemory.new(
        42,
        proc_root: directory
      )

      assert_equal 150 * 1024, memory.stop
    end
  end

  def test_streams_standard_output_one_line_at_a_time
    body = <<~'RUBY'
      require "json"
      3.times do |id|
        puts JSON.generate(id: id)
        STDOUT.flush
      end
    RUBY
    with_executable(body) do |path|
      stream = BasinAcceptance::Cli.new(path).line_stream([], timeout: 1)
      rows = []
      while (line = stream.next_line)
        rows << JSON.parse(line)
      end

      assert_equal [{"id" => 0}, {"id" => 1}, {"id" => 2}], rows
    ensure
      stream&.close
    end
  end

  def test_terminates_a_stream_that_exceeds_its_timeout
    with_executable("sleep 10") do |path|
      stream = BasinAcceptance::Cli.new(path).line_stream([], timeout: 0.05)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      error = assert_raises(BasinAcceptance::Error) { stream.next_line }

      assert_includes error.message, "exceeded its timeout"
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
                      :<,
                      2
    ensure
      stream&.close
    end
  end

  private

  def write_process_status(root, process_id, process_group:, rss_kb:)
    directory = File.join(root, process_id.to_s)
    FileUtils.mkdir_p(directory)
    File.write(
      File.join(directory, "stat"),
      "#{process_id} (basin worker) S 1 #{process_group} #{process_group} 0 0\n"
    )
    File.write(File.join(directory, "status"), "VmRSS:\t#{rss_kb} kB\n")
  end
end
