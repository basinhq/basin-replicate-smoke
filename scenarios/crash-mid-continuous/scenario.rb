scenario "crash-mid-continuous" do
  tier :standard
  requires :postgres
  budget wall: 120
  fixture :postgres, "crash-mid-continuous"

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
        INSERT INTO "${schema}".backlog
        SELECT g, repeat(chr(97 + (g % 26)::integer), 1024)
        FROM generate_series(1, 5000) AS g;
      SQL
      wait_status received: :present
    end

    shutdown_with "KILL"
    expect_exit 137
  end

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
    source: [:postgres, "SELECT id, payload FROM \"${schema}\".backlog ORDER BY id"],
    sink: [:ducklake, "SELECT id, payload FROM lake.backlog ORDER BY id"]
  )
end
