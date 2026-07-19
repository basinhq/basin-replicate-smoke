scenario "schema-change-propagate-drop" do
  tier :standard
  requires :postgres
  budget wall: 120
  fixture :postgres, "schema-change-propagate-drop"

  continuous config: "config.json" do
    wait_timeout 60
    ready_when(
      :postgres,
      <<~SQL,
        SELECT active
        FROM pg_replication_slots
        WHERE slot_name = '${slot}'
      SQL
      rows: [{"active" => true}]
    )

    gate do
      before_sql :postgres, <<~SQL
        INSERT INTO "${schema}".dd_items (id, keep_val, drop_val)
          VALUES (1, 'k1', 'd1');
        ALTER TABLE "${schema}".dd_items DROP COLUMN drop_val;
        INSERT INTO "${schema}".dd_items (id, keep_val) VALUES (2, 'k2');
      SQL
      wait_query(
        :postgres,
        <<~SQL,
          SELECT confirmed_flush_lsn >= pg_current_wal_lsn() AS caught_up
          FROM pg_replication_slots
          WHERE slot_name = '${slot}'
        SQL
        rows: [{"caught_up" => true}]
      )
      wait_status caught_up: true, journal_depth: 0, acknowledged: :present
    end

    expect_exit 0
  end

  # The sink side scans every column the sink actually created (SELECT *), so a
  # surviving drop_val would add a third column the source projection lacks and
  # fail the streaming compare: a passing compare proves the propagated
  # DROP COLUMN ran on the replicate DuckLake table and the narrowed columns
  # converged across the pre-drop and post-drop rows.
  expect_rows(
    source: [:postgres, <<~SQL],
      SELECT id, keep_val
      FROM "${schema}".dd_items
      ORDER BY id
    SQL
    sink: [:ducklake, <<~SQL],
      SELECT *
      FROM lake.dd_items
      ORDER BY id
    SQL
    streaming: true
  )
end
