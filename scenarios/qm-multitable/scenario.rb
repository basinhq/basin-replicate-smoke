scenario "qm-multitable" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "qm-multitable"

  # One query polling pipeline captures three relations round-robin over one
  # connection: nobody runs three connectors for three tables. Each relation is an
  # independent cursor with its own watermark, so a poll of one never moves another's
  # position. This gate exercises the multi-table happy path through the shipped
  # binary, mirroring qp-schema-add's single-table structure.

  # Run one polls every relation's seeded rows from its watermark floor, emits a
  # create baseline per relation, and delivers every row.
  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  # New rows land in two of the three relations. Run two resumes each relation from
  # its own persisted watermark and delivers only the relations that advanced; the
  # untouched relation stays put.
  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~SQL
      INSERT INTO "${schema}".mt_orders (id, status) VALUES (3, 'shipped');
      INSERT INTO "${schema}".mt_metrics (id, value) VALUES (3, 300);
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  # Run three finds nothing past any relation's watermark and is already caught up.
  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  # Each relation converged independently into its own DuckLake table, with no
  # cross-table interference and no duplication.
  expect_rows(
    source: [:postgres, "SELECT id, status FROM \"${schema}\".mt_orders ORDER BY id"],
    sink: [:ducklake, "SELECT id, status FROM lake.mt_orders ORDER BY id"]
  )
  expect_rows(
    source: [:postgres, "SELECT id, kind FROM \"${schema}\".mt_events ORDER BY id"],
    sink: [:ducklake, "SELECT id, kind FROM lake.mt_events ORDER BY id"]
  )
  expect_rows(
    source: [:postgres, "SELECT id, value FROM \"${schema}\".mt_metrics ORDER BY id"],
    sink: [:ducklake, "SELECT id, value FROM lake.mt_metrics ORDER BY id"]
  )
end
