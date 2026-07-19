# The sink configuration here deliberately omits `extension_directory`, so the
# binary has to find its own DuckLake extensions. The scenario's cache home is
# empty when the first command starts, which makes that first sink open a cold
# expansion and every later one a reuse. The DuckDB client that verifies the
# lake at the end is a separate program with its own extension directory and
# proves nothing about the binary under test.
scenario "ducklake-embedded-extensions" do
  tier :standard
  requires :postgres
  budget wall: 90
  fixture :postgres, "orders-basic"

  # Cold cache: the first sink open expands the extensions before copying.
  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  # Warm cache: a second process reuses the populated directory and applies the
  # change stream.
  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~SQL
      INSERT INTO "${schema}".orders (id, status) VALUES (4, 'queued');
      UPDATE "${schema}".orders SET status = 'shipped' WHERE id = 2;
      DELETE FROM "${schema}".orders WHERE id = 3;
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  # Reading the lake back through the binary exercises the same resolution on a
  # command that only opens the sink.
  cli "query", "--target", "sink",
      "SELECT id, status FROM lake.orders ORDER BY id",
      config: "config.json" do
    expect_exit 0
    expect_query_rows [
      {"id" => 1, "status" => "pending"},
      {"id" => 2, "status" => "shipped"},
      {"id" => 4, "status" => "queued"}
    ]
  end

  expect_rows(
    source: [:postgres, "SELECT id, status FROM \"${schema}\".orders ORDER BY id"],
    sink: [:ducklake, "SELECT id, status FROM lake.orders ORDER BY id"]
  )
end
