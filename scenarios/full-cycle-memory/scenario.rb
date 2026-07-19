scenario "full-cycle-memory" do
  tier :extended
  requires :postgres
  budget wall: 120, rss_mb: 512
  fixture :postgres, "full-cycle-memory"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~SQL
      INSERT INTO "${schema}".events (id, payload)
      VALUES (9000000001, 'tail-a'), (9000000002, 'tail-b');
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  expect_rows(
    source: [:postgres, "SELECT count(*)::bigint AS n FROM \"${schema}\".events"],
    sink: [:ducklake, "SELECT count(*)::bigint AS n FROM lake.events"]
  )
end
