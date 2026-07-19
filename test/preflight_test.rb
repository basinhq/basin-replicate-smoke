require "minitest/autorun"
require "basin_acceptance"
require "fileutils"
require "tmpdir"

class PreflightTest < Minitest::Test
  def test_accepts_an_artifact_that_answers_version
    with_executable("#!/usr/bin/env ruby\nputs 'basin-replicate 0.1.0'\n") do |path|
      assert_nil BasinAcceptance::Preflight.verify(path)
    end
  end

  def test_rejects_a_missing_artifact
    error = assert_raises(BasinAcceptance::Error) do
      BasinAcceptance::Preflight.verify("/nonexistent/basin-replicate")
    end

    assert_includes error.message, "not an executable file"
  end

  def test_names_both_glibc_versions_when_the_artifact_is_too_new
    available = BasinAcceptance::Preflight.available_glibc
    skip "this runtime does not report a glibc version" if available.nil?

    required = [2, available.fetch(1) + 2]
    text = required.join(".")
    body = <<~RUBY
      #!/usr/bin/env ruby
      # GLIBC_#{text}
      warn "libc.so.6: version `GLIBC_#{text}' not found"
      exit 1
    RUBY
    with_executable(body) do |path|
      error = assert_raises(BasinAcceptance::Error) do
        BasinAcceptance::Preflight.verify(path)
      end

      assert_includes error.message, "needs glibc #{text}"
      assert_includes error.message, "runner container provides"
    end
  end

  def test_reports_an_ordinary_failure_without_a_glibc_claim
    with_executable("#!/usr/bin/env ruby\nwarn 'boom'\nexit 3\n") do |path|
      error = assert_raises(BasinAcceptance::Error) do
        BasinAcceptance::Preflight.verify(path)
      end

      assert_includes error.message, "failed --version with exit 3"
      assert_includes error.message, "boom"
      refute_includes error.message, "glibc"
    end
  end

  def test_reads_the_highest_required_glibc_version_across_read_chunks
    Dir.mktmpdir("basin-acceptance-preflight-") do |directory|
      path = File.join(directory, "artifact")
      # The highest version straddles the boundary between two reads.
      padding = "\0" * (BasinAcceptance::Preflight::CHUNK_BYTES - 15)
      File.binwrite(path, "GLIBC_2.17#{padding}GLIBC_2.30GLIBC_2.9")

      assert_equal [2, 30], BasinAcceptance::Preflight.required_glibc(path)
    end
  end

  private

  def with_executable(body)
    Dir.mktmpdir("basin-acceptance-preflight-") do |directory|
      path = File.join(directory, "basin-replicate")
      File.write(path, body)
      FileUtils.chmod(0o755, path)
      yield path
    end
  end
end
