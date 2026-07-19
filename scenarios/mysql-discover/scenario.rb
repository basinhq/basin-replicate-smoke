scenario "mysql-discover" do
  tier :standard
  requires :mysql
  budget wall: 30
  fixture :mysql, "mysql-discover"

  cli "discover", "--json", config: "discover.json" do
    expect_exit 0
    expect_discovery(
      source: "mysql",
      collections: [
        {
          namespace: "${mysql_database}",
          name: "audit",
          key: [],
          eligible: false,
          warnings: ["no_key"],
          native_types: {"ts" => "datetime", "message" => "text"}
        },
        {
          namespace: "${mysql_database}",
          name: "geo",
          key: ["id"],
          eligible: false,
          warnings: ["unsupported_column_type"],
          native_types: {"id" => "bigint", "shape" => "geometry"}
        },
        {
          namespace: "${mysql_database}",
          name: "orders",
          key: ["id"],
          eligible: true,
          warnings: [],
          native_types: {
            "id" => "bigint unsigned",
            "amount" => "decimal(10,2)",
            "note" => "varchar(64)"
          }
        }
      ],
      selection: ["${mysql_database}.orders"]
    )
  end
end
