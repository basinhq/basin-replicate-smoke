scenario "mysql-snapshot-basic" do
  tier :standard
  requires :mysql
  budget wall: 60
  fixture :mysql, "mysql-snapshot-basic"

  cli "query", "--target", "source",
      "SELECT id, name, region FROM `${mysql_database}`.customers ORDER BY id",
      config: "config.json" do
    expect_exit 0
    expect_query_rows [
      {"id" => 1, "name" => "Ada", "region" => "emea"},
      {"id" => 2, "name" => "Bela", "region" => "apac"},
      {"id" => 3, "name" => "Chidi", "region" => "amer"}
    ]
  end

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "query", "--target", "sink",
      "SELECT id, name, region FROM lake.customers ORDER BY id",
      config: "config.json" do
    expect_exit 0
    expect_query_rows [
      {"id" => 1, "name" => "Ada", "region" => "emea"},
      {"id" => 2, "name" => "Bela", "region" => "apac"},
      {"id" => 3, "name" => "Chidi", "region" => "amer"}
    ]
  end

  expect_rows(
    source: [:mysql, <<~SQL],
      SELECT JSON_OBJECT('id', id, 'name', name, 'region', region)
      FROM `${mysql_database}`.customers
      ORDER BY id
    SQL
    sink: [:ducklake, <<~SQL],
      SELECT id, name, region
      FROM lake.customers
      ORDER BY id
    SQL
    streaming: true
  )

  expect_rows(
    source: [:mysql, <<~SQL],
      SELECT JSON_OBJECT(
        'order_id', order_id,
        'line_no', line_no,
        'sku', sku,
        'qty', qty
      )
      FROM `${mysql_database}`.order_items
      ORDER BY order_id, line_no
    SQL
    sink: [:ducklake, <<~SQL],
      SELECT order_id, line_no, sku, qty
      FROM lake.order_items
      ORDER BY order_id, line_no
    SQL
    streaming: true
  )
end
