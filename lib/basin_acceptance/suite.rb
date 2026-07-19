module BasinAcceptance
  class Suite
    GROUPS = {
      "scale" => "scale-",
      "scale-release" => %w[
        scale-append-mysql-ducklake
        scale-append-postgres-clickhouse
        scale-sync-mysql-ducklake
        scale-sync-postgres-clickhouse
      ],
      "scale-sync" => "scale-sync-",
      "scale-append" => "scale-append-"
    }.freeze

    attr_reader :scenarios

    def self.load(directory)
      paths = Dir[File.join(directory, "*", "scenario.rb")].sort
      new(paths.map { |path| ScenarioFile.load(path) })
    end

    def initialize(scenarios)
      @scenarios = scenarios.freeze
      duplicate = @scenarios.group_by(&:name).find { |_name, matches| matches.length > 1 }
      raise Error, "duplicate scenario name: #{duplicate.first}" if duplicate
    end

    def fetch(name)
      @scenarios.find { |scenario| scenario.name == name } ||
        raise(Error, "unknown scenario: #{name}")
    end

    def select(name)
      exact = @scenarios.find { |scenario| scenario.name == name }
      return [exact] unless exact.nil?

      prefix = GROUPS[name]
      raise Error, "unknown scenario or group: #{name}" if prefix.nil?

      return @scenarios.select { |scenario| prefix.include?(scenario.name) } if prefix.is_a?(Array)

      @scenarios.select { |scenario| scenario.name.start_with?(prefix) }
    end

    # Splits scenarios across `total` shards so a continuous integration run can
    # execute them at the same time. Assignment packs by declared wall budget
    # rather than by count, so one shard does not collect every long scenario.
    # The result depends only on the scenario set, so every shard index covers
    # the same scenarios on every run.
    def self.shard(scenarios, index:, total:)
      raise Error, "shard count must be positive" unless total.positive?
      raise Error, "shard index must be within 1..#{total}" unless (1..total).cover?(index)

      totals = Array.new(total, 0.0)
      buckets = Array.new(total) { [] }
      ordered = scenarios.sort_by { |scenario| [-scenario.wall_seconds, scenario.name] }
      ordered.each do |scenario|
        position = totals.each_with_index.min_by { |seconds, at| [seconds, at] }.last
        buckets.fetch(position) << scenario
        totals[position] += scenario.wall_seconds
      end
      buckets.fetch(index - 1).sort_by(&:name)
    end

    def for_tier(tier)
      tiers = case tier
              when :smoke then %i[smoke]
              when :e2e then %i[smoke standard]
              when :"e2e-full" then %i[smoke standard extended]
              else raise Error, "unknown suite tier: #{tier}"
              end
      @scenarios.select { |scenario| tiers.include?(scenario.tier) }
    end
  end
end
