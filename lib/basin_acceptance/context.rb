require "fileutils"
require "securerandom"

module BasinAcceptance
  class Context
    SCALE_ROWS = {
      "s" => 10_000,
      "m" => 100_000,
      "l" => 1_000_000,
      "xl" => 10_000_000,
      "2xl" => 100_000_000
    }.freeze
    SCALE_WALL_SECONDS = {
      "s" => 300,
      "m" => 600,
      "l" => 900,
      "xl" => 1_800,
      "2xl" => 3_600
    }.freeze
    APPEND_TRANSACTION_ROWS = 50_000

    def self.test_scale
      scale = ENV.fetch("BASIN_ACCEPTANCE_TEST_SCALE", "l")
      return scale if SCALE_ROWS.key?(scale)

      raise Error, "unknown test scale #{scale.inspect}; choose #{SCALE_ROWS.keys.join(", ")}"
    end

    def self.scale_wall_seconds
      SCALE_WALL_SECONDS.fetch(test_scale)
    end

    def self.append_batches
      append_rows = SCALE_ROWS.fetch(test_scale) / 10
      (append_rows + APPEND_TRANSACTION_ROWS - 1) / APPEND_TRANSACTION_ROWS
    end

    attr_reader :work_dir

    def initialize(scenario, work_dir)
      @work_dir = work_dir
      stem = identifier("#{scenario.name}_#{SecureRandom.hex(4)}")
      test_scale = self.class.test_scale
      large_rows = SCALE_ROWS.fetch(test_scale)
      @bindings = {
        "cache_dir" => directory("cache"),
        "catalog_dir" => directory("catalog"),
        "clickhouse_database" => identifier("#{stem}_ch"),
        "clickhouse_endpoint" => clickhouse_endpoint,
        "ext_dir" => ENV.fetch(
          "BASIN_DUCKDB_EXTENSION_DIRECTORY",
          "/opt/duckdb/extensions"
        ),
        "mysql_database" => identifier("#{stem}_db"),
        "mysql_host" => mysql_host,
        "mysql_password" => mysql_password,
        "mysql_port" => mysql_port,
        "mysql_server_id" => 10_000 + SecureRandom.random_number(1_000_000),
        "mysql_user" => mysql_user,
        "append_rows" => (large_rows / 10).to_s,
        "large_rows" => large_rows.to_s,
        "pipeline" => stem,
        "postgres_database" => postgres_database,
        "postgres_host" => postgres_host,
        "postgres_password" => postgres_password,
        "postgres_port" => postgres_port,
        "postgres_user" => postgres_user,
        "publication" => identifier("#{stem}_pub"),
        "scale_rows" => ENV.fetch("BASIN_ACCEPTANCE_SCALE_ROWS", "40000"),
        "schema" => identifier("#{stem}_schema"),
        "slot" => identifier("#{stem}_slot"),
        "state_dir" => directory("state"),
        "test_scale" => test_scale,
        "work_dir" => work_dir
      }
    end

    def render(template)
      rendered = template.gsub(/\$\{([^}]+)\}/) do
        name = Regexp.last_match(1)
        @bindings.fetch(name) do
          raise Error, "config references unknown placeholder ${#{name}}"
        end
      end
      rendered
    end

    def fetch(name)
      @bindings.fetch(name.to_s)
    end

    def postgres_host
      ENV.fetch("BASIN_POSTGRES_HOST", "127.0.0.1")
    end

    def postgres_port
      ENV.fetch("BASIN_POSTGRES_PORT", "15432")
    end

    def postgres_user
      ENV.fetch("BASIN_POSTGRES_USER", "basin")
    end

    def postgres_password
      ENV.fetch("BASIN_POSTGRES_PASSWORD", "basin")
    end

    def postgres_database
      ENV.fetch("BASIN_POSTGRES_DATABASE", "basin_test")
    end

    def mysql_host
      ENV.fetch("BASIN_MYSQL_HOST", "127.0.0.1")
    end

    def clickhouse_endpoint
      host = ENV.fetch("BASIN_CLICKHOUSE_HOST", "127.0.0.1")
      port = ENV.fetch("BASIN_CLICKHOUSE_HTTP_PORT", "18123")
      "http://#{host}:#{port}"
    end

    # Environment the CLI under test inherits for this scenario. The ClickHouse
    # sink names its tables after the collection alone and reads its target
    # database from the environment, so this is how the scenario's isolated
    # database reaches the binary.
    #
    # The cache home is the scenario's own directory, which is empty when the
    # scenario starts and removed when it ends. A binary that caches anything
    # between runs, such as an expanded copy of extensions it carries, therefore
    # starts every scenario cold and cannot satisfy one scenario from another
    # scenario's or another shard's leftovers.
    def cli_environment
      {
        "BASIN_CLICKHOUSE_DATABASE" => fetch("clickhouse_database"),
        "XDG_CACHE_HOME" => fetch("cache_dir")
      }
    end

    def mysql_port
      ENV.fetch("BASIN_MYSQL_PORT", "13306")
    end

    def mysql_user
      ENV.fetch("BASIN_MYSQL_USER", "root")
    end

    def mysql_password
      ENV.fetch("BASIN_MYSQL_PASSWORD", "basin")
    end

    private

    def directory(name)
      path = File.join(work_dir, name)
      FileUtils.mkdir_p(path)
      path
    end

    def identifier(value)
      value.downcase.gsub(/[^a-z0-9_]/, "_")[0, 55]
    end
  end
end
