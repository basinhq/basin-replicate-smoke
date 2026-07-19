scenario "scale-append-postgres-clickhouse" do
  tier :extended
  requires :postgres, :clickhouse
  scale_budget rss_mb: 512
  fixture :postgres, "events-large"

  cli "run-once", config: "config.json" do
    expect_exit 0
    measure_rows "${large_rows}"
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    before_sql_batches :postgres, count: Context.append_batches do |batch, batches|
      <<~SQL
        INSERT INTO "${schema}".events
        SELECT * FROM "${schema}".events_append
        WHERE id > ${large_rows} + (${append_rows} * #{batch} / #{batches})
          AND id <= ${large_rows} + (${append_rows} * #{batch + 1} / #{batches});
      SQL
    end
    expect_exit 0
    measure_rows "${append_rows}"
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  expect_query :clickhouse, <<~SQL,
    SELECT count() = ${large_rows} AS ok
    FROM events
    WHERE id <= ${large_rows}
  SQL
               rows: [{"ok" => 1}]

  expect_query :clickhouse, <<~SQL,
    SELECT count() = ${append_rows} AS ok
    FROM events
    WHERE _basin_operation = 'insert' AND id > ${large_rows}
  SQL
               rows: [{"ok" => 1}]
end
