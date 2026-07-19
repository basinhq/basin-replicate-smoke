scenario "ducklake-append-history" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "ducklake-append-history"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~'SQL'
      BEGIN;
      INSERT INTO "${schema}".items (id, note) VALUES (1, 'a'), (2, 'b');
      UPDATE "${schema}".items SET note = 'a2' WHERE id = 1;
      DELETE FROM "${schema}".items WHERE id = 2;
      TRUNCATE "${schema}".items;
      INSERT INTO "${schema}".items (id, note) VALUES (3, 'c');
      COMMIT;
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  # Append history is replay-safe: a caught-up rerun adds no rows.
  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  # The complete labeled history in transaction order: one immutable row per
  # change, the delete tombstone carrying its key and before-image columns,
  # the truncate carrying only its label.
  expect_query :ducklake, <<~SQL,
    SELECT _basin_operation AS op, id, note
    FROM lake.items
    ORDER BY _basin_version
  SQL
               rows: [
                 {"op" => "insert", "id" => 1, "note" => "a"},
                 {"op" => "insert", "id" => 2, "note" => "b"},
                 {"op" => "update", "id" => 1, "note" => "a2"},
                 {"op" => "delete", "id" => 2, "note" => "b"},
                 {"op" => "truncate", "id" => nil, "note" => nil},
                 {"op" => "insert", "id" => 3, "note" => "c"}
               ]
end
