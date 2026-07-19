scenario "snapshot-basic" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "snapshot-basic"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~SQL
      INSERT INTO "${schema}".customers (id, name, region) VALUES (4, 'Deja', 'emea');
      INSERT INTO "${schema}".order_items (order_id, line_no, sku, qty)
        VALUES (101, 2, 'sku-d', 3);
      UPDATE "${schema}".order_items
        SET qty = 9
        WHERE order_id = 100 AND line_no = 1;
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  expect_rows(
    source: [:postgres, <<~SQL],
      SELECT id, name, region
      FROM "${schema}".customers
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
    source: [:postgres, <<~SQL],
      SELECT order_id, line_no, sku, qty
      FROM "${schema}".order_items
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
