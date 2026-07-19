require "json"

module BasinAcceptance
  module Provider
    class MySQL
      def initialize(context)
        @context = context
        @cli = Cli.new(
          ENV.fetch("BASIN_MYSQL_CLIENT", "/usr/bin/mysql"),
          environment: {"MYSQL_PWD" => context.mysql_password}
        )
      end

      def execute(sql, timeout:)
        result = @cli.run(arguments, timeout: timeout, stdin_data: sql)
        check(result, "MySQL command")
        nil
      end

      def rows(sql, timeout:)
        result = @cli.run(
          [*arguments, "--execute", sql],
          timeout: timeout
        )
        check(result, "MySQL query")
        result.stdout.lines.filter_map do |line|
          text = line.strip
          JSON.parse(text) unless text.empty?
        end
      rescue JSON::ParserError => error
        raise Error, "MySQL query did not return one JSON object per row: #{error.message}"
      end

      def row_stream(sql, timeout:)
        stream = @cli.line_stream(
          [*arguments, "--execute", sql],
          timeout: timeout
        )
        JsonRows.new(stream, "MySQL query")
      end

      def prepare
        nil
      end

      def cleanup
        database = quote_ident(@context.fetch("mysql_database"))
        execute("DROP DATABASE IF EXISTS #{database}", timeout: 10)
      end

      private

      def arguments
        [
          "--batch",
          "--local-infile=1",
          "--raw",
          "--skip-column-names",
          "--host", @context.mysql_host,
          "--port", @context.mysql_port,
          "--user", @context.mysql_user
        ]
      end

      def check(result, label)
        return if result.exit_code.zero? && !result.timed_out

        raise Error,
              "#{label} failed with exit #{result.exit_code}: #{result.stderr.strip}"
      end

      def quote_ident(value)
        "`#{value.gsub('`', '``')}`"
      end
    end
  end
end
