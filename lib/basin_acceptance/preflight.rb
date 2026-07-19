require "open3"
require "timeout"

module BasinAcceptance
  # Proves the CLI artifact can execute inside the runner container before any
  # scenario starts. The artifact is normally built elsewhere, so a runtime
  # mismatch would otherwise surface as an unexplained scenario failure well
  # into a run.
  module Preflight
    CHUNK_BYTES = 1024 * 1024
    OVERLAP_BYTES = 32
    VERSION_PATTERN = /GLIBC_(\d+)\.(\d+)(?:\.(\d+))?/.freeze

    def self.verify(executable, timeout: 30)
      unless File.file?(executable) && File.executable?(executable)
        raise Error, "the CLI under test is not an executable file: #{executable}"
      end

      stdout, stderr, status = capture(executable, timeout)
      return if status.success?

      raise Error, diagnosis(executable, stdout, stderr, status)
    end

    def self.capture(executable, timeout)
      Timeout.timeout(timeout) { Open3.capture3(executable, "--version") }
    rescue Timeout::Error
      raise Error, "the CLI under test did not answer --version within #{timeout}s: #{executable}"
    rescue SystemCallError => error
      raise Error, "the CLI under test could not be started: #{executable}: #{error.message}"
    end

    def self.diagnosis(executable, stdout, stderr, status)
      required = required_glibc(executable)
      available = available_glibc
      detail = [stderr.strip, stdout.strip].reject(&:empty?).join(" ")
      if required && available && (required <=> available) == 1
        return "the CLI under test needs glibc #{version_text(required)} but this " \
               "runner container provides #{version_text(available)}. The artifact " \
               "was built against a newer C library than the pinned runner image. " \
               "Build it on an older base, or run the tests on an image that " \
               "ships glibc #{version_text(required)} or later. (#{executable}: #{detail})"
      end

      "the CLI under test failed --version with exit #{status.exitstatus.inspect}: " \
        "#{executable}: #{detail}"
    end

    # Reads the GLIBC_x.y symbol versions the dynamic linker will demand. The
    # highest one is the floor the runtime has to meet. Scanning bytes keeps
    # this free of binutils, which the runner image does not install.
    def self.required_glibc(path)
      versions = []
      File.open(path, "rb") do |file|
        carry = ""
        while (chunk = file.read(CHUNK_BYTES))
          versions.concat((carry + chunk).scan(VERSION_PATTERN))
          carry = chunk[-OVERLAP_BYTES..] || chunk
        end
      end
      versions.map { |parts| parts.compact.map(&:to_i) }.max
    rescue SystemCallError
      nil
    end

    def self.available_glibc
      first_line, status = Open3.capture2("ldd", "--version")
      return nil unless status.success?

      match = first_line.lines.first.to_s.match(/(\d+)\.(\d+)(?:\.(\d+))?\s*\z/)
      match && match.captures.compact.map(&:to_i)
    rescue SystemCallError
      nil
    end

    def self.version_text(version)
      version.join(".")
    end
  end
end
