scenario "schema-change-quarantine" do
  tier :standard
  requires :postgres
  budget wall: 120
  fixture :postgres, "schema-change-items"

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
        INSERT INTO "${schema}".items (id, value) VALUES (1, 'before');
        ALTER TABLE "${schema}".items ADD COLUMN extra text;
        INSERT INTO "${schema}".items (id, value, extra)
          VALUES (2, 'after', 'new');
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

  expect_rows(
    source: [:postgres, "SELECT id, value FROM \"${schema}\".items ORDER BY id"],
    sink: [:ducklake, "SELECT id, value FROM lake.items ORDER BY id"]
  )
end
