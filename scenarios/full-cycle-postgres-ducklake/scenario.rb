scenario "full-cycle-postgres-ducklake" do
  tier :smoke
  requires :postgres
  budget wall: 60
  fixture :postgres, "orders-basic"

  cli "query", "--target", "source",
      "SELECT id, status FROM \"${schema}\".orders ORDER BY id",
      config: "config.json" do
    expect_exit 0
    expect_query_rows [
      {"id" => 1, "status" => "pending"},
      {"id" => 2, "status" => "pending"},
      {"id" => 3, "status" => "pending"}
    ]
  end

  cli "query", "--target", "source",
      "UPDATE \"${schema}\".orders SET status = 'unexpected' WHERE id = 1",
      config: "config.json" do
    expect_exit 3
  end

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "query", "--target", "sink", "--write",
      "CREATE TABLE lake.operator_notes (id BIGINT, note VARCHAR); " \
      "INSERT INTO lake.operator_notes VALUES (1, 'ready')",
      config: "config.json" do
    expect_exit 0
    expect_query_rows []
  end

  cli "query", "--target", "sink",
      "SELECT id, note FROM lake.operator_notes ORDER BY id",
      config: "config.json" do
    expect_exit 0
    expect_query_rows [{"id" => 1, "note" => "ready"}]
  end

  cli "query", "--target", "source", "--write",
      "INSERT INTO \"${schema}\".orders (id, status) VALUES (5, 'queued')",
      config: "config.json" do
    expect_exit 0
    expect_query_rows []
  end

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~SQL
      INSERT INTO "${schema}".orders (id, status) VALUES (4, 'pending');
      UPDATE "${schema}".orders SET status = 'shipped' WHERE id = 2;
      DELETE FROM "${schema}".orders WHERE id = 3;
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "query", "--target", "sink",
      "SELECT id, status FROM lake.orders ORDER BY id",
      config: "config.json" do
    expect_exit 0
    expect_query_rows [
      {"id" => 1, "status" => "pending"},
      {"id" => 2, "status" => "shipped"},
      {"id" => 4, "status" => "pending"},
      {"id" => 5, "status" => "queued"}
    ]
  end

  cli "query", "--target", "sink", "DELETE FROM lake.orders",
      config: "config.json" do
    expect_exit 3
  end

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  expect_rows(
    source: [:postgres, "SELECT id, status FROM \"${schema}\".orders ORDER BY id"],
    sink: [:ducklake, "SELECT id, status FROM lake.orders ORDER BY id"]
  )
end
