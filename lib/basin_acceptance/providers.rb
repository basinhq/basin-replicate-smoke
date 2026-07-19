require_relative "providers/json_rows"
require_relative "providers/clickhouse"
require_relative "providers/ducklake"
require_relative "providers/mysql"
require_relative "providers/postgres"

module BasinAcceptance
  class Providers
    def initialize(context)
      @providers = {}
      @factories = {
        clickhouse: -> { Provider::ClickHouse.new(context) },
        ducklake: -> { Provider::DuckLake.new(context) },
        mysql: -> { Provider::MySQL.new(context) },
        postgres: -> { Provider::Postgres.new(context) }
      }
    end

    # Creates whatever each required service needs before the scenario seeds it.
    def prepare(services)
      Array(services).each { |service| fetch(service).prepare }
    end

    def execute(provider, sql, timeout:)
      fetch(provider).execute(sql, timeout: timeout)
    end

    def rows(provider, sql, timeout:)
      fetch(provider).rows(sql, timeout: timeout)
    end

    def row_stream(provider, sql, timeout:)
      fetch(provider).row_stream(sql, timeout: timeout)
    end

    def cleanup(services)
      Array(services).each do |service|
        provider = @providers[service.to_sym]
        provider&.cleanup
      rescue Error => error
        warn "cleanup failed for #{service}: #{error.message}"
      end
    end

    private

    def fetch(provider)
      key = provider.to_sym
      return @providers.fetch(key) if @providers.key?(key)

      factory = @factories.fetch(key) do
        raise Error, "unknown acceptance provider: #{provider}"
      end
      @providers[key] = factory.call
    end
  end
end
