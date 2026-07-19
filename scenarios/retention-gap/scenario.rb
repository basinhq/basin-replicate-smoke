scenario "retention-gap" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "retention-gap"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  cli "run-once", config: "config.json" do
    before_sql :postgres, "SELECT pg_drop_replication_slot('${slot}')"
    expect_exit 65
    expect_error_count at_least: 1
    expect_error_codes "worker.carrier_unavailable"
    expect_error_paths "/source"
  end
end
