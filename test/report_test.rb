require "minitest/autorun"
require "basin_acceptance"
require "tmpdir"

class ReportTest < Minitest::Test
  Result = Struct.new(
    :wall_seconds,
    :peak_rss_bytes,
    :command_seconds,
    :command_rows,
    :failures,
    keyword_init: true
  )

  def test_writes_markdown_and_machine_readable_throughput
    result = Result.new(
      wall_seconds: 12.5,
      peak_rss_bytes: 128 * 1024 * 1024,
      command_seconds: [4.0, 1.0, 0.5],
      command_rows: [1_000_000, 1_000, nil],
      failures: []
    )
    report = BasinAcceptance::Report.new(
      suite: "e2e-full",
      records: [{name: "scale-sync", status: "PASS", result: result}],
      generated_at: Time.utc(2026, 7, 19)
    )

    Dir.mktmpdir do |directory|
      markdown_path, json_path = report.write(directory, stem: "results")
      markdown = File.read(markdown_path)
      document = JSON.parse(File.read(json_path))

      assert_includes markdown, "| `scale-sync` | PASS | 12.500s | 5.500s | 128.0 MiB | 1,001,000 | 200200 rows/s |"
      scenario = document.fetch("scenarios").fetch(0)
      assert_equal 1_001_000, scenario.fetch("measured_rows")
      assert_in_delta 200_200, scenario.fetch("throughput_rows_per_second"), 0.001
      assert_equal [1_000_000, 1_000, nil], scenario.fetch("command_rows")
    end
  end
end
