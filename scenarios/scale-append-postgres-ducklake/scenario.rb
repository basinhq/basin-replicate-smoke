scenario "scale-append-postgres-ducklake" do
  tier :extended
  requires :postgres
  # DuckDB runs in-process; its buffer pool is capped at 512 MiB, so total RSS
  # needs headroom for that cap plus the worker baseline. The out-of-process
  # sinks (ClickHouse) keep the tighter 512.
  scale_budget rss_mb: 1024
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

  expect_query :ducklake, <<~SQL,
    SELECT count(*) = ${large_rows} AS ok
    FROM lake.events
    WHERE id <= ${large_rows}
  SQL
               rows: [{"ok" => true}]

  expect_query :ducklake, <<~SQL,
    SELECT count(*) = ${append_rows} AS ok
    FROM lake.events
    WHERE _basin_operation = 'insert' AND id > ${large_rows}
  SQL
               rows: [{"ok" => true}]
end
