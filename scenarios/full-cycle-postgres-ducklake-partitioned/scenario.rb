scenario "full-cycle-postgres-ducklake-partitioned" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "full-cycle-postgres-ducklake-partitioned"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~SQL
      INSERT INTO "${schema}".events (id, ts, note)
        VALUES (4, '2026-08-02 11:00:00'::timestamp, 'pending');
      UPDATE "${schema}".events SET note = 'shipped' WHERE id = 2;
      DELETE FROM "${schema}".events WHERE id = 3;
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  expect_rows(
    source: [:postgres, <<~SQL],
      SELECT id, to_char(ts, 'YYYY-MM-DD HH24:MI:SS') AS ts, note
      FROM "${schema}".events
      ORDER BY id
    SQL
    sink: [:ducklake, <<~SQL]
      SELECT id, strftime(ts, '%Y-%m-%d %H:%M:%S') AS ts, note
      FROM lake.events
      ORDER BY id
    SQL
  )
end
