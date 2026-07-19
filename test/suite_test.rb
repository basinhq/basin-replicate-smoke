require "minitest/autorun"
require "basin_acceptance"

class SuiteTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_shards_cover_every_scenario_exactly_once
    scenarios = BasinAcceptance::Suite.load(File.join(ROOT, "scenarios")).for_tier(:"e2e-full")
    total = 4

    names = (1..total).flat_map do |index|
      BasinAcceptance::Suite.shard(scenarios, index: index, total: total).map(&:name)
    end

    assert_equal scenarios.map(&:name).sort, names.sort
  end

  def test_shards_balance_the_declared_wall_budgets
    scenarios = BasinAcceptance::Suite.load(File.join(ROOT, "scenarios")).for_tier(:"e2e-full")
    total = 4

    budgets = (1..total).map do |index|
      BasinAcceptance::Suite.shard(scenarios, index: index, total: total)
                            .sum(&:wall_seconds)
    end

    longest = scenarios.map(&:wall_seconds).max
    assert_operator budgets.max - budgets.min, :<=, longest
  end

  def test_a_shard_index_is_stable_across_calls
    scenarios = BasinAcceptance::Suite.load(File.join(ROOT, "scenarios")).for_tier(:e2e)

    first = BasinAcceptance::Suite.shard(scenarios, index: 2, total: 3).map(&:name)
    second = BasinAcceptance::Suite.shard(scenarios, index: 2, total: 3).map(&:name)

    assert_equal first, second
  end

  def test_rejects_a_shard_index_outside_the_count
    scenarios = BasinAcceptance::Suite.load(File.join(ROOT, "scenarios")).for_tier(:smoke)

    assert_raises(BasinAcceptance::Error) do
      BasinAcceptance::Suite.shard(scenarios, index: 4, total: 3)
    end
  end

  def test_selects_the_complete_scale_sync_group
    suite = BasinAcceptance::Suite.load(File.join(ROOT, "scenarios"))

    assert_equal %w[
      scale-sync-mysql-clickhouse
      scale-sync-mysql-ducklake
      scale-sync-postgres-clickhouse
      scale-sync-postgres-ducklake
    ], suite.select("scale-sync").map(&:name)
  end

  def test_selects_the_complete_scale_matrix
    suite = BasinAcceptance::Suite.load(File.join(ROOT, "scenarios"))

    assert_equal 8, suite.select("scale").length
    assert suite.select("scale").all? { |scenario| scenario.name.start_with?("scale-") }
  end

  def test_release_scale_group_covers_both_sources_and_sinks
    suite = BasinAcceptance::Suite.load(File.join(ROOT, "scenarios"))

    assert_equal %w[
      scale-append-mysql-ducklake
      scale-append-postgres-clickhouse
      scale-sync-mysql-ducklake
      scale-sync-postgres-clickhouse
    ], suite.select("scale-release").map(&:name)
  end

  def test_select_prefers_an_exact_scenario_and_rejects_unknown_groups
    suite = BasinAcceptance::Suite.load(File.join(ROOT, "scenarios"))

    assert_equal ["snapshot-basic"], suite.select("snapshot-basic").map(&:name)
    assert_raises(BasinAcceptance::Error) { suite.select("scale-snyc") }
  end
end
