scenario "scale-sync-postgres-clickhouse" do
  tier :extended
  requires :postgres, :clickhouse
  scale_budget rss_mb: 512
  fixture :postgres, "events-large"

  cli "run-once", config: "config.json" do
    measure_rows "${large_rows}"
    expect_exit 0
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
    measure_rows "${append_rows}"
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  expect_rows(
    source: [:postgres, <<~SQL],
      SELECT count(*)::bigint AS n, min(id) AS min_id, max(id) AS max_id
      FROM "${schema}".events
    SQL
    sink: [:clickhouse, <<~SQL]
      SELECT
        toInt64(count()) AS n,
        min(id) AS min_id,
        max(id) AS max_id
      FROM events FINAL
      WHERE _basin_deleted = 0
    SQL
  )

end
