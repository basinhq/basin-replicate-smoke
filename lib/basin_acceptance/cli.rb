require "open3"
require "timeout"

module BasinAcceptance
  class Cli
    class LineStream
      def initialize(argv:, environment:, timeout:, stdin_data:)
        @argv = argv
        @deadline = monotonic_time + timeout
        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(
          environment,
          *argv,
          pgroup: true
        )
        @stderr_reader = Thread.new { @stderr.read }
        @stdin.write(stdin_data) unless stdin_data.nil?
        @stdin.close
        @finished = false
      end

      def next_line
        return nil if @finished

        remaining = @deadline - monotonic_time
        timeout! unless remaining.positive?
        timeout! if IO.select([@stdout], nil, nil, remaining).nil?

        line = @stdout.gets
        return line unless line.nil?

        finish(check_exit: true)
        nil
      rescue StandardError
        close
        raise
      end

      def close
        return if @finished

        signal("TERM")
        signal("KILL") unless @wait_thread.join(1)
        finish(check_exit: false)
      end

      private

      def timeout!
        close
        raise Error, "streaming command exceeded its timeout: #{@argv.inspect}"
      end

      def finish(check_exit:)
        status = @wait_thread.value
        stderr = @stderr_reader.value
        @stdout.close unless @stdout.closed?
        @finished = true
        return unless check_exit && !status.success?

        raise Error,
              "streaming command exited #{exit_code(status)}: #{stderr.strip}"
      end

      def signal(name)
        Process.kill(name, -@wait_thread.pid)
      rescue Errno::ESRCH
        nil
      end

      def exit_code(status)
        return status.exitstatus unless status.exitstatus.nil?

        128 + status.termsig
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    class ProcessGroupMemory
      SAMPLE_INTERVAL_SECONDS = 0.02

      def initialize(process_group, proc_root: "/proc")
        @process_group = process_group
        @proc_root = proc_root
        @peak_rss_bytes = sample_rss_bytes
        @stopping = false
        @thread = Thread.new { sample_until_stopped }
        @thread.report_on_exception = false
      end

      def stop
        @stopping = true
        @thread.wakeup
        @thread.join
        @peak_rss_bytes
      rescue ThreadError
        @thread.join
        @peak_rss_bytes
      end

      private

      def sample_until_stopped
        loop do
          sleep(SAMPLE_INTERVAL_SECONDS)
          break if @stopping

          @peak_rss_bytes = [@peak_rss_bytes, sample_rss_bytes].max
        end
      end

      def sample_rss_bytes
        process_ids.sum do |process_id|
          next 0 unless process_group(process_id) == @process_group

          resident_bytes(process_id)
        end
      rescue SystemCallError
        0
      end

      def process_ids
        Dir.children(@proc_root).filter_map do |entry|
          Integer(entry, exception: false) if entry.match?(/\A\d+\z/)
        end
      end

      def process_group(process_id)
        stat = File.read(File.join(@proc_root, process_id.to_s, "stat"))
        closing_parenthesis = stat.rindex(") ")
        return nil if closing_parenthesis.nil?

        fields = stat[(closing_parenthesis + 2)..].split
        Integer(fields.fetch(2), exception: false)
      rescue SystemCallError, IndexError
        nil
      end

      def resident_bytes(process_id)
        status = File.read(File.join(@proc_root, process_id.to_s, "status"))
        kilobytes = status[/^VmRSS:\s+(\d+)\s+kB$/, 1]
        kilobytes.nil? ? 0 : Integer(kilobytes) * 1024
      rescue SystemCallError
        0
      end
    end

    Result = Struct.new(
      :argv,
      :exit_code,
      :stdout,
      :stderr,
      :timed_out,
      :wall_seconds,
      :peak_rss_bytes,
      keyword_init: true
    )

    class Running
      attr_reader :argv

      def initialize(argv:, stdout:, stderr:, wait_thread:, started:,
                     stdout_sink: nil, stderr_sink: nil)
        @argv = argv
        @stdout_reader = Thread.new { read_and_tee(stdout, stdout_sink) }
        @stderr_reader = Thread.new { read_and_tee(stderr, stderr_sink) }
        @wait_thread = wait_thread
        @started = started
        @memory = ProcessGroupMemory.new(wait_thread.pid)
        @result = nil
      end

      def running?
        @wait_thread.alive?
      end

      def signal(name)
        Process.kill(name, -@wait_thread.pid)
      rescue Errno::ESRCH
        nil
      end

      def wait(timeout:, terminate_on_timeout: true)
        return @result unless @result.nil?

        status = Timeout.timeout(timeout) { @wait_thread.value }
        finish(status, timed_out: false)
      rescue Timeout::Error
        return nil unless terminate_on_timeout

        stop_process_group
        finish(@wait_thread.value, timed_out: true)
      end

      def terminate
        return @result unless @result.nil?

        stop_process_group
        finish(@wait_thread.value, timed_out: true)
      end

      private

      def read_and_tee(stream, sink)
        output = +""
        while (chunk = stream.readpartial(16 * 1024))
          output << chunk
          sink&.write(chunk)
          sink&.flush
        end
        output
      rescue EOFError
        output
      end

      def stop_process_group
        signal("TERM")
        return if @wait_thread.join(1)

        signal("KILL")
      end

      def finish(status, timed_out:)
        @result = Result.new(
          argv: @argv,
          exit_code: exit_code(status),
          stdout: @stdout_reader.value,
          stderr: @stderr_reader.value,
          timed_out: timed_out,
          wall_seconds: monotonic_time - @started,
          peak_rss_bytes: @memory.stop
        )
      end

      def exit_code(status)
        return status.exitstatus unless status.exitstatus.nil?

        128 + status.termsig
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    def initialize(executable, environment: {})
      @executable = File.expand_path(executable)
      @environment = environment
      unless File.file?(@executable) && File.executable?(@executable)
        raise Error, "BASIN_TEST_CLI is not an executable file: #{@executable}"
      end
    end

    def run(arguments, timeout:, stdin_data: nil, stream_output: false)
      start(
        arguments,
        stdin_data: stdin_data,
        stream_output: stream_output
      ).wait(timeout: timeout)
    end

    def start(arguments, stdin_data: nil, environment: {}, stream_output: false)
      argv = [@executable, *arguments]
      started = monotonic_time
      stdin, stdout, stderr, wait_thread = Open3.popen3(
        @environment.merge(environment),
        *argv,
        pgroup: true
      )
      stdin.write(stdin_data) unless stdin_data.nil?
      stdin.close
      Running.new(
        argv: argv,
        stdout: stdout,
        stderr: stderr,
        wait_thread: wait_thread,
        started: started,
        stdout_sink: stream_output ? $stdout : nil,
        stderr_sink: stream_output ? $stderr : nil
      )
    end

    def line_stream(arguments, timeout:, stdin_data: nil)
      argv = [@executable, *arguments]
      LineStream.new(
        argv: argv,
        environment: @environment,
        timeout: timeout,
        stdin_data: stdin_data
      )
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
