scenario "qp-schema-add" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "qp-schema-add"

  # The query polling source sees no DDL: it diffs each poll's result shape against the
  # accepted baseline and emits the same neutral schema event a log source emits when the
  # shape changes. This gate exercises that arc under the default safe_additions policy
  # through the shipped binary, mirroring the closest once-driven scenario
  # (cadence-exit-contract) because no query smoke scenario existed before.

  # Run one polls the three seeded rows from the watermark floor, emitting a create
  # baseline and delivering the rows.
  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  # A nullable column is added at the source and two rows carrying it are inserted. Run two
  # resumes from the persisted watermark, diffs the widened shape against the accepted
  # baseline, emits the neutral schema event ahead of the new rows, evolves the destination
  # with a nullable note, and delivers ids 4 and 5.
  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~SQL
      ALTER TABLE "${schema}".orders ADD COLUMN note text;
      INSERT INTO "${schema}".orders (id, status, note)
        VALUES (4, 'pending', 'gift'), (5, 'shipped', 'fragile');
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  # Run three finds nothing past the watermark and is already caught up.
  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  # The pre-change rows read NULL for note in both source and sink (no backfill); the
  # post-change rows carry their values. A matching comparison proves the destination gained
  # the nullable column and the new rows delivered exactly once.
  expect_rows(
    source: [:postgres, "SELECT id, status, note FROM \"${schema}\".orders ORDER BY id"],
    sink: [:ducklake, "SELECT id, status, note FROM lake.orders ORDER BY id"]
  )
end
