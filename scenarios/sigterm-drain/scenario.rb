scenario "sigterm-drain" do
  tier :standard
  requires :postgres
  budget wall: 120
  fixture :postgres, "sigterm-drain"

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
        INSERT INTO "${schema}".events
        SELECT g, repeat('e', 64)
        FROM generate_series(1, 100) AS g;
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

    shutdown_with "TERM"
    expect_exit 0
  end

  expect_rows(
    source: [:postgres, "SELECT id, payload FROM \"${schema}\".events ORDER BY id"],
    sink: [:ducklake, "SELECT id, payload FROM lake.events ORDER BY id"]
  )
end
