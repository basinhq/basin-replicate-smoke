scenario "clickhouse-replicate-cdc" do
  tier :standard
  requires :postgres, :clickhouse
  budget wall: 60
  fixture :postgres, "clickhouse-replicate-cdc"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~'SQL'
      BEGIN;
      INSERT INTO "${schema}".orders (id, qty, note, active, maybe_null) VALUES
        (10, 1, 'first', true, NULL),
        (11, 2, 'second', false, 'present');
      UPDATE "${schema}".orders SET qty = 7, note = 'first-updated' WHERE id = 10;
      UPDATE "${schema}".orders SET id = 12 WHERE id = 11;
      INSERT INTO "${schema}".orders (id, qty, note, active, maybe_null) VALUES
        (13, 3, 'third', true, 'gone-soon');
      DELETE FROM "${schema}".orders WHERE id = 13;

      INSERT INTO "${schema}".events (id, kind) VALUES (1, 'created');
      TRUNCATE "${schema}".events;
      INSERT INTO "${schema}".events (id, kind) VALUES (2, 'reset');
      COMMIT;
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  # A caught-up rerun replays nothing: the durable applied-delivery ledger and
  # the versioned model keep the destination unchanged.
  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  expect_rows(
    source: [:postgres, <<~SQL],
      SELECT id, qty, note, active, maybe_null
      FROM "${schema}".orders
      ORDER BY id
    SQL
    sink: [:clickhouse, <<~SQL]
      SELECT id, qty, note, active, maybe_null
      FROM orders FINAL
      WHERE _basin_deleted = 0
      ORDER BY id
    SQL
  )

  expect_rows(
    source: [:postgres, <<~SQL],
      SELECT id, kind FROM "${schema}".events ORDER BY id
    SQL
    sink: [:clickhouse, <<~SQL]
      SELECT id, kind FROM events FINAL WHERE _basin_deleted = 0 ORDER BY id
    SQL
  )

  # The key change soft-deleted key 11 and the delete soft-deleted key 13;
  # both stay physically present as versioned markers, invisible to the
  # version-aware read above.
  expect_query :clickhouse,
               "SELECT count(DISTINCT id) AS markers FROM orders WHERE _basin_deleted = 1",
               rows: [{"markers" => 2}]
end
