require "minitest/autorun"
require "basin_acceptance"
require "tmpdir"

class ContextTest < Minitest::Test
  def test_named_scales_grow_by_one_order_of_magnitude
    assert_equal(
      {"s" => 10_000, "m" => 100_000, "l" => 1_000_000,
       "xl" => 10_000_000, "2xl" => 100_000_000},
      BasinAcceptance::Context::SCALE_ROWS
    )
  end

  def test_scale_sets_initial_and_append_rows
    previous = ENV["BASIN_ACCEPTANCE_TEST_SCALE"]
    ENV["BASIN_ACCEPTANCE_TEST_SCALE"] = "m"
    scaled = context("scale-sync-postgres-ducklake")

    assert_equal "100000", scaled.fetch("large_rows")
    assert_equal "10000", scaled.fetch("append_rows")
  ensure
    ENV["BASIN_ACCEPTANCE_TEST_SCALE"] = previous
  end

  def test_scale_sets_the_scenario_wall_budget
    previous = ENV["BASIN_ACCEPTANCE_TEST_SCALE"]
    ENV["BASIN_ACCEPTANCE_TEST_SCALE"] = "xl"

    assert_equal 1_800, BasinAcceptance::Context.scale_wall_seconds
  ensure
    ENV["BASIN_ACCEPTANCE_TEST_SCALE"] = previous
  end

  def test_large_appends_are_split_below_the_transaction_limit
    previous = ENV["BASIN_ACCEPTANCE_TEST_SCALE"]
    ENV["BASIN_ACCEPTANCE_TEST_SCALE"] = "xl"

    assert_equal 20, BasinAcceptance::Context.append_batches
  ensure
    ENV["BASIN_ACCEPTANCE_TEST_SCALE"] = previous
  end

  def test_rejects_an_unknown_scale
    previous = ENV["BASIN_ACCEPTANCE_TEST_SCALE"]
    ENV["BASIN_ACCEPTANCE_TEST_SCALE"] = "huge"

    error = assert_raises(BasinAcceptance::Error) { context("scale") }
    assert_includes error.message, "choose s, m, l, xl, 2xl"
  ensure
    ENV["BASIN_ACCEPTANCE_TEST_SCALE"] = previous
  end

  def test_two_scenarios_never_share_a_clickhouse_database
    databases = 2.times.map do
      context("clickhouse-replicate-cdc").fetch("clickhouse_database")
    end

    assert_equal 2, databases.uniq.length
    assert(databases.all? { |name| name.match?(/\Aclickhouse_replicate_cdc_[a-f0-9]{8}_ch\z/) })
  end

  def test_the_cli_does_not_inherit_clickhouse_connection_state
    context = context("clickhouse-replicate-cdc")
    refute context.cli_environment.key?("BASIN_CLICKHOUSE_DATABASE")
  end

  def test_the_cli_caches_into_an_empty_directory_under_the_scenario_work_dir
    context = context("ducklake-embedded-extensions")
    cache_dir = context.cli_environment.fetch("XDG_CACHE_HOME")

    assert_equal context.fetch("cache_dir"), cache_dir
    assert_equal File.join(context.work_dir, "cache"), cache_dir
    assert_empty Dir.children(cache_dir)
  end

  private

  def context(name)
    scenario = BasinAcceptance::Scenario.new(name: name, tier: :full, wall_seconds: 1)
    BasinAcceptance::Context.new(scenario, Dir.mktmpdir("basin-acceptance-context-"))
  end
end
