require "json"

module BasinAcceptance
  module Provider
    class Postgres
      def initialize(context)
        @context = context
        @cli = Cli.new(
          ENV.fetch("BASIN_PSQL", "/usr/bin/psql"),
          environment: {"PGPASSWORD" => context.postgres_password}
        )
      end

      def execute(sql, timeout:)
        result = @cli.run(arguments, timeout: timeout, stdin_data: sql)
        check(result, "PostgreSQL command")
        nil
      end

      def rows(sql, timeout:)
        wrapped = json_query(sql)
        result = @cli.run(
          [*arguments, "--tuples-only", "--no-align", "--command", wrapped],
          timeout: timeout
        )
        check(result, "PostgreSQL query")
        result.stdout.lines.filter_map do |line|
          text = line.strip
          JSON.parse(text) unless text.empty?
        end
      end

      def row_stream(sql, timeout:)
        stream = @cli.line_stream(
          [*arguments, "--tuples-only", "--no-align", "--command", json_query(sql)],
          timeout: timeout
        )
        JsonRows.new(stream, "PostgreSQL query")
      end

      def prepare
        nil
      end

      def cleanup
        slot = quote_literal(@context.fetch("slot"))
        publication = quote_ident(@context.fetch("publication"))
        schema = quote_ident(@context.fetch("schema"))
        execute(
          <<~SQL,
            SELECT pg_drop_replication_slot(slot_name)
            FROM pg_replication_slots
            WHERE slot_name = #{slot};
            DROP PUBLICATION IF EXISTS #{publication};
            DROP SCHEMA IF EXISTS #{schema} CASCADE;
          SQL
          timeout: 10
        )
      end

      private

      def arguments
        [
          "--no-psqlrc",
          "--quiet",
          "--set", "ON_ERROR_STOP=1",
          "--host", @context.postgres_host,
          "--port", @context.postgres_port,
          "--username", @context.postgres_user,
          "--dbname", @context.postgres_database
        ]
      end

      def json_query(sql)
        query = sql.strip.sub(/;\z/, "")
        "SELECT row_to_json(basin_row)::text FROM (#{query}) AS basin_row"
      end

      def check(result, label)
        return if result.exit_code.zero? && !result.timed_out

        raise Error,
              "#{label} failed with exit #{result.exit_code}: #{result.stderr.strip}"
      end

      def quote_ident(value)
        %Q{"#{value.gsub('"', '""')}"}
      end

      def quote_literal(value)
        "'#{value.gsub("'", "''")}'"
      end
    end
  end
end
