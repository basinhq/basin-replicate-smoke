require "fileutils"
require "json"
require "time"

module BasinAcceptance
  class Report
    def initialize(suite:, records:, generated_at: Time.now.utc)
      @suite = suite
      @records = records
      @generated_at = generated_at
    end

    def write(directory, stem:)
      FileUtils.mkdir_p(directory)
      json_path = File.join(directory, "#{stem}.json")
      markdown_path = File.join(directory, "#{stem}.md")
      File.write(json_path, JSON.pretty_generate(document) << "\n")
      File.write(markdown_path, markdown)
      [markdown_path, json_path]
    end

    def document
      {
        suite: @suite,
        generated_at: @generated_at.iso8601,
        scenarios: @records.map { |record| row(record) }
      }
    end

    def markdown
      lines = [
        "# Acceptance test results",
        "",
        "Suite: `#{@suite}`  ",
        "Generated: `#{@generated_at.iso8601}`",
        "",
        "| Test | Status | Total time | CLI time | Peak CLI RSS | Measured rows | Throughput |",
        "|---|---:|---:|---:|---:|---:|---:|"
      ]
      @records.each do |record|
        value = row(record)
        lines << format(
          "| `%s` | %s | %.3fs | %.3fs | %.1f MiB | %s | %s |",
          value[:name], value[:status], value[:wall_seconds],
          value[:cli_seconds], value[:peak_cli_rss_mib],
          integer_or_dash(value[:measured_rows]),
          rate_or_dash(value[:throughput_rows_per_second])
        )
      end
      lines.join("\n") << "\n"
    end

    private

    def row(record)
      result = record.fetch(:result)
      seconds = Array(result.command_seconds)
      rows = Array(result.command_rows)
      measured = rows.compact.sum
      measured_seconds = rows.each_index.sum do |index|
        rows[index].nil? ? 0.0 : seconds.fetch(index, 0.0)
      end
      {
        name: record.fetch(:name),
        status: record.fetch(:status),
        wall_seconds: result.wall_seconds,
        cli_seconds: seconds.sum,
        command_seconds: seconds,
        command_rows: rows,
        peak_cli_rss_bytes: result.peak_rss_bytes,
        peak_cli_rss_mib: result.peak_rss_bytes.fdiv(1024 * 1024),
        measured_rows: measured.zero? ? nil : measured,
        throughput_rows_per_second: measured.positive? && measured_seconds.positive? ? measured.fdiv(measured_seconds) : nil,
        failures: result.failures
      }
    end

    def integer_or_dash(value)
      value ? value.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse : "-"
    end

    def rate_or_dash(value)
      value ? format("%.0f rows/s", value) : "-"
    end
  end
end
