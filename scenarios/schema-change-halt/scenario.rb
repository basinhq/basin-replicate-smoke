scenario "schema-change-halt" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "schema-change-items"

  continuous config: "config.json" do
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
        ALTER TABLE "${schema}".items ADD COLUMN extra text;
        INSERT INTO "${schema}".items (id, value, extra)
          VALUES (2, 'after', 'new');
      SQL
      wait_for_exit
    end

    expect_exit 3
  end
end
