scenario "schema-change-safe-additions" do
  tier :standard
  requires :postgres
  budget wall: 120
  fixture :postgres, "schema-change-items"

  # config.json omits schema_change_policy, so this runs under the default
  # safe_additions policy. That policy applies a source-proven trailing-column
  # addition to the sink as a nullable, default-free column and never backfills
  # existing rows, whether or not the source column carried a default. The gate
  # exercises SCENARIOS.md family 3.1 (add a nullable column live) and 3.2 (add
  # a defaulted column live), interleaving inserts so rows both predate and
  # follow each addition.
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
        ALTER TABLE "${schema}".items ADD COLUMN note text;
        INSERT INTO "${schema}".items (id, value, note) VALUES (2, 'mid', 'n2');
        ALTER TABLE "${schema}".items ADD COLUMN flag integer NOT NULL DEFAULT 7;
        INSERT INTO "${schema}".items (id, value, note, flag)
          VALUES (3, 'after', 'n3', 9);
        INSERT INTO "${schema}".items (id, value, note)
          VALUES (4, 'default-relied', 'n4');
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

  # The source backfills its own reads from the constant default: rows 1 and 2
  # that predate the flag column report flag = 7, and the row that omitted flag
  # on insert (id 4) carries the default the source materialized into its row
  # image. This is the value the sink deliberately does not invent for the
  # rows it never re-saw.
  expect_query :postgres, <<~SQL,
    SELECT id, value, note, flag
    FROM "${schema}".items
    ORDER BY id
  SQL
               rows: [
                 {"id" => 1, "value" => "before", "note" => nil, "flag" => 7},
                 {"id" => 2, "value" => "mid", "note" => "n2", "flag" => 7},
                 {"id" => 3, "value" => "after", "note" => "n3", "flag" => 9},
                 {"id" => 4, "value" => "default-relied", "note" => "n4", "flag" => 7}
               ]

  # The sink applied both additions but never backfilled. A row reads NULL for
  # every column added after it existed: id 1 predates both note (3.1) and flag
  # (3.2); id 2 predates only flag. Rows written after an addition carry the
  # concrete source values, including the default (7) the source filled into
  # id 4's row image. The default itself is dropped: id 1 and id 2 stay NULL
  # for flag rather than taking the source-side 7.
  expect_query :ducklake, <<~SQL,
    SELECT id, value, note, flag
    FROM lake.items
    ORDER BY id
  SQL
               rows: [
                 {"id" => 1, "value" => "before", "note" => nil, "flag" => nil},
                 {"id" => 2, "value" => "mid", "note" => "n2", "flag" => nil},
                 {"id" => 3, "value" => "after", "note" => "n3", "flag" => 9},
                 {"id" => 4, "value" => "default-relied", "note" => "n4", "flag" => 7}
               ]
end
