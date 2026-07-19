scenario "scale-sync-mysql-clickhouse" do
  tier :extended
  requires :mysql, :clickhouse
  scale_budget rss_mb: 512
  fixture :mysql, "events-large"

  cli "run-once", config: "config.json" do
    measure_rows "${large_rows}"
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    before_sql_batches :mysql, count: Context.append_batches do |batch, batches|
      <<~SQL
        INSERT INTO `${mysql_database}`.events
        SELECT * FROM `${mysql_database}`.events_append
        WHERE id > ${large_rows} + (${append_rows} * #{batch} DIV #{batches})
          AND id <= ${large_rows} + (${append_rows} * #{batch + 1} DIV #{batches});
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
    source: [:mysql, <<~SQL],
      SELECT JSON_OBJECT(
        'n', COUNT(*),
        'min_id', MIN(id),
        'max_id', MAX(id)
      )
      FROM `${mysql_database}`.events
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
