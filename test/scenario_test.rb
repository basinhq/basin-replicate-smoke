require "minitest/autorun"
require "basin_acceptance"

class ScenarioTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_loads_the_validation_scenario
    scenario = BasinAcceptance::ScenarioFile.load(
      File.join(ROOT, "scenarios", "validation-rejects", "scenario.rb")
    )

    assert_equal "validation-rejects", scenario.name
    assert_equal :smoke, scenario.tier
    assert_equal 10.0, scenario.wall_seconds
    assert_nil scenario.rss_bytes
    assert_equal ["run-once"], scenario.commands.fetch(0).arguments
  end

  def test_suite_tiers_are_additive
    suite = BasinAcceptance::Suite.load(File.join(ROOT, "scenarios"))

    smoke = ["full-cycle-postgres-ducklake", "validation-rejects"]
    assert_equal smoke, suite.for_tier(:smoke).map(&:name)
    expected = [
      "cadence-exit-contract",
      "cadence-lease",
      "cdc-mutations",
      "cdc-typed-scalars",
      "clickhouse-replicate-additive",
      "clickhouse-replicate-cdc",
      "crash-mid-continuous",
      "discover-select-subset",
      "ducklake-append-history",
      "ducklake-embedded-extensions",
      "full-cycle-postgres-ducklake-partitioned",
      "full-cycle-postgres-ducklake",
      "mysql-cdc-mutations",
      "mysql-discover",
      "mysql-snapshot-basic",
      "protocol-drive",
      "qm-multitable",
      "qp-schema-add",
      "retention-gap",
      "retention-slot-lost",
      "schema-change-halt",
      "schema-change-propagate-drop",
      "schema-change-propagate",
      "schema-change-quarantine",
      "schema-change-safe-additions",
      "sigterm-drain",
      "snapshot-basic",
      "table-drop-parks",
      "validation-rejects",
      "verify-postgres-ducklake"
    ]
    assert_equal expected, suite.for_tier(:e2e).map(&:name)
    extended = [
      "append-slow-sink",
      "full-cycle-memory",
      "items-scale",
      "items-snapshot",
      "scale-append-mysql-clickhouse",
      "scale-append-mysql-ducklake",
      "scale-append-postgres-clickhouse",
      "scale-append-postgres-ducklake",
      "scale-sync-mysql-clickhouse",
      "scale-sync-mysql-ducklake",
      "scale-sync-postgres-clickhouse",
      "scale-sync-postgres-ducklake",
      "table-reset-scale"
    ]
    assert_equal (expected + extended).sort,
                 suite.for_tier(:"e2e-full").map(&:name).sort
  end

  def test_scale_matrix_covers_every_source_and_sink
    suite = BasinAcceptance::Suite.load(File.join(ROOT, "scenarios"))
    expected = %w[scale-append scale-sync].product(
      %w[postgres mysql],
      %w[ducklake clickhouse]
    ).map { |parts| parts.join("-") }.sort
    actual = suite.scenarios.map(&:name).grep(/\Ascale-(append|sync)-/).sort

    assert_equal expected, actual
    actual.each do |name|
      assert_equal ["events-large"], suite.fetch(name).fixtures.map(&:name)
    end
  end

  def test_scenario_names_and_files_match_their_directories
    suite = BasinAcceptance::Suite.load(File.join(ROOT, "scenarios"))

    suite.scenarios.each do |scenario|
      assert_equal File.basename(scenario.directory), scenario.name

      scenario.fixtures.each do |fixture|
        assert_path_exists fixture.file,
                           "#{scenario.name} references missing fixture #{fixture.name}"
      end

      scenario.commands.filter_map(&:config).each do |config|
        assert_path_exists File.join(scenario.directory, config),
                           "#{scenario.name} references missing config #{config}"
      end
    end
  end

  def test_scenarios_keep_sql_fixtures_outside_scenario_directories
    local_seeds = Dir[File.join(ROOT, "scenarios", "*", "seed.sql")]

    assert_empty local_seeds
  end

  def test_rejects_an_unknown_fixture
    builder = BasinAcceptance::ScenarioBuilder.new(
      "missing-fixture",
      File.join(ROOT, "scenarios", "missing-fixture")
    )
    builder.tier :standard
    builder.budget wall: 10
    builder.fixture :postgres, "does-not-exist"
    builder.cli "run-once"

    error = assert_raises(BasinAcceptance::Error) { builder.build }
    assert_includes error.message, 'unknown postgres fixture "does-not-exist"'
  end

  def test_converts_the_declared_rss_budget_to_bytes
    builder = BasinAcceptance::ScenarioBuilder.new("memory", ROOT)
    builder.tier :extended
    builder.budget wall: 60, rss_mb: 512
    builder.cli "run-once"

    assert_equal 512 * 1024 * 1024, builder.build.rss_bytes
  end

  def test_loads_streaming_row_comparisons
    scenario = BasinAcceptance::ScenarioFile.load(
      File.join(ROOT, "scenarios", "snapshot-basic", "scenario.rb")
    )

    assert scenario.row_comparisons.all?(&:streaming)
  end

  def test_normalizes_expected_query_rows_through_json
    builder = BasinAcceptance::ScenarioBuilder.new("query", ROOT)
    builder.tier :standard
    builder.budget wall: 10
    builder.cli "query", "--target", "source", "SELECT 1" do
      expect_query_rows [{value: 1}]
    end

    rows = builder.build.commands.fetch(0).query_rows
    assert_equal [{"value" => 1}], rows
  end
end
