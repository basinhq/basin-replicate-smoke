require "json"

module BasinAcceptance
  module Provider
    class ClickHouse
      def initialize(context)
        @context = context
        @cli = Cli.new(ENV.fetch("BASIN_CURL", "/usr/bin/curl"))
      end

      # One statement per call: the ClickHouse HTTP interface accepts a single
      # statement per POST body.
      def execute(sql, timeout:)
        run(sql, timeout: timeout)
        nil
      end

      def rows(sql, timeout:)
        result = run("#{bare(sql)} FORMAT JSONEachRow", timeout: timeout)
        result.stdout.lines.filter_map do |line|
          text = line.strip
          JSON.parse(text) unless text.empty?
        end
      end

      def row_stream(sql, timeout:)
        stream = @cli.line_stream(
          [*arguments, "--data-binary", "#{bare(sql)} FORMAT JSONEachRow"],
          timeout: timeout
        )
        JsonRows.new(stream, "ClickHouse query")
      end

      # The scenario's database does not exist until it is created here, so both
      # lifecycle statements address the always-present default database.
      def prepare
        run(
          "CREATE DATABASE IF NOT EXISTS #{quote_ident(database)}",
          timeout: 30,
          database: "default"
        )
        nil
      end

      def cleanup
        run(
          "DROP DATABASE IF EXISTS #{quote_ident(database)}",
          timeout: 30,
          database: "default"
        )
        nil
      end

      private

      def run(sql, timeout:, database: self.database)
        result = @cli.run(
          [*arguments(database), "--data-binary", sql],
          timeout: timeout
        )
        return result if result.exit_code.zero? && !result.timed_out

        raise Error,
              "ClickHouse query failed with exit #{result.exit_code}: " \
              "#{result.stderr.strip} #{result.stdout.strip}".strip
      end

      def bare(sql)
        sql.strip.sub(/;\z/, "")
      end

      def arguments(database = self.database)
        [
          "--silent",
          "--show-error",
          "--fail-with-body",
          "--user", "#{user}:#{password}",
          "--url", url(database)
        ]
      end

      # 64-bit integers render as JSON numbers, not the quoted default, so sink
      # rows compare structurally against row_to_json output from PostgreSQL.
      def url(database)
        endpoint = @context.fetch("clickhouse_endpoint")
        "#{endpoint}/?database=#{database}&output_format_json_quote_64bit_integers=0"
      end

      def database
        @context.fetch("clickhouse_database")
      end

      def quote_ident(value)
        %Q{`#{value.gsub('`', '``')}`}
      end

      def user
        ENV.fetch("BASIN_CLICKHOUSE_USER", "basin")
      end

      def password
        ENV.fetch("BASIN_CLICKHOUSE_PASSWORD", "basin")
      end
    end
  end
end
