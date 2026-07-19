scenario "cadence-exit-contract" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "ticks-empty"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~SQL
      INSERT INTO "${schema}".ticks (id, label) VALUES (1, 'first');
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  expect_rows(
    source: [:postgres, "SELECT id, label FROM \"${schema}\".ticks ORDER BY id"],
    sink: [:ducklake, "SELECT id, label FROM lake.ticks ORDER BY id"]
  )
end
