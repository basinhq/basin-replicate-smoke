scenario "discover-select-subset" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "discover-select-subset"

  cli "discover", "--json", config: "discover.json" do
    expect_exit 0
    expect_discovery(
      source: "postgres",
      collections: [
        {
          namespace: "${schema}",
          name: "audit",
          key: ["id"],
          eligible: true
        },
        {
          namespace: "${schema}",
          name: "orders",
          key: ["id"],
          eligible: true
        }
      ],
      selection: ["${schema}.audit", "${schema}.orders"]
    )
  end

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  expect_rows(
    source: [:postgres, "SELECT id, status FROM \"${schema}\".orders ORDER BY id"],
    sink: [:ducklake, "SELECT id, status FROM lake.orders ORDER BY id"]
  )

  expect_query(
    :ducklake,
    <<~SQL,
      SELECT count(*) AS count
      FROM duckdb_tables()
      WHERE database_name = 'lake' AND table_name = 'audit'
    SQL
    rows: [{"count" => 0}]
  )
end
