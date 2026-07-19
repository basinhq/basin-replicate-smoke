require "json"

module BasinAcceptance
  module Provider
    class DuckLake
      def initialize(context)
        @context = context
        @cli = Cli.new(ENV.fetch("BASIN_DUCKDB", "/usr/local/bin/duckdb"))
      end

      def execute(sql, timeout:)
        run(sql, timeout: timeout)
        nil
      end

      def rows(sql, timeout:)
        result = run(sql, timeout: timeout, json: true)
        JSON.parse(result.stdout)
      end

      def row_stream(sql, timeout:)
        stream = @cli.line_stream(
          ["-jsonlines", ":memory:", "-c", full_sql(sql)],
          timeout: timeout
        )
        JsonRows.new(stream, "DuckLake query")
      end

      def prepare
        nil
      end

      def cleanup
        nil
      end

      private

      def run(sql, timeout:, json: false)
        arguments = []
        arguments << "-json" if json
        arguments.concat([":memory:", "-c", full_sql(sql)])
        result = @cli.run(arguments, timeout: timeout)
        return result if result.exit_code.zero? && !result.timed_out

        raise Error,
              "DuckLake query failed with exit #{result.exit_code}: #{result.stderr.strip}"
      end

      def full_sql(sql)
        <<~SQL
          SET extension_directory=#{quote(@context.fetch("ext_dir"))};
          SET autoinstall_known_extensions=false;
          SET autoload_known_extensions=false;
          LOAD ducklake;
          ATTACH #{quote("ducklake:#{catalog_path}")} AS lake
            (DATA_PATH #{quote("#{data_path}/")});
          #{sql}
        SQL
      end

      def catalog_path
        File.join(@context.fetch("catalog_dir"), "metadata.duckdb")
      end

      def data_path
        File.join(@context.fetch("catalog_dir"), "data")
      end

      def quote(value)
        "'#{value.gsub("'", "''")}'"
      end
    end
  end
end
