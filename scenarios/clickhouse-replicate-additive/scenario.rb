scenario "clickhouse-replicate-additive" do
  tier :standard
  requires :postgres, :clickhouse
  budget wall: 60
  fixture :postgres, "clickhouse-replicate-additive"

  # Run 1 (snapshot_mode initial) copies the three seeded rows into the base
  # ReplacingMergeTree table, created from the canonical schema event.
  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  # Add a nullable column live under the safe_additions policy. The current-state
  # ReplacingMergeTree is evolved online with ADD COLUMN IF NOT EXISTS ahead of
  # the rows that carry the column, and the added column is never part of the
  # ORDER BY, so the replacement key is unaffected. Rows 2 and 3 predate the
  # addition and stay NULL for note (no backfill); the two new rows (4, 5) and the
  # updated pre-existing row (1) carry their note values.
  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~'SQL'
      ALTER TABLE "${schema}".orders ADD COLUMN note text;
      INSERT INTO "${schema}".orders (id, status, note) VALUES
        (4, 'pending', 'gift'),
        (5, 'shipped', 'fragile');
      UPDATE "${schema}".orders SET note = 'reopened' WHERE id = 1;
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  # A caught-up rerun replays nothing: the durable applied-delivery ledger keeps
  # the destination unchanged and the idempotent ADD COLUMN re-runs harmlessly.
  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  # The version-aware FINAL read the current projection wires resolves the newest
  # row per key and drops soft-delete markers. Comparing id, status, and note
  # against the live source proves the ReplacingMergeTree gained the nullable
  # column online: pre-change rows 2 and 3 read NULL in both, and rows 1, 4, and
  # 5 carry their post-addition note values.
  expect_rows(
    source: [:postgres, <<~SQL],
      SELECT id, status, note FROM "${schema}".orders ORDER BY id
    SQL
    sink: [:clickhouse, <<~SQL]
      SELECT id, status, note FROM orders FINAL
      WHERE _basin_deleted = 0
      ORDER BY id
    SQL
  )
end
