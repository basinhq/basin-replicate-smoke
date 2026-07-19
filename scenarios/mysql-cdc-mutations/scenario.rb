scenario "mysql-cdc-mutations" do
  tier :standard
  requires :mysql
  budget wall: 60
  fixture :mysql, "mysql-cdc-mutations"

  continuous config: "config.json" do
    ready_when(
      :mysql,
      <<~SQL,
        SELECT JSON_OBJECT('ready', COUNT(*) > 0)
        FROM information_schema.PROCESSLIST
        WHERE COMMAND LIKE 'Binlog Dump%'
      SQL
      rows: [{"ready" => true}]
    )

    gate do
      before_sql :mysql, <<~SQL
        START TRANSACTION;
        INSERT INTO `${mysql_database}`.orders (id, note, updated)
          VALUES (1, 'first', '2026-07-13 00:00:00');
        INSERT INTO `${mysql_database}`.orders (id, note, updated)
          VALUES (2, 'removed', '2026-07-13 01:00:00');
        UPDATE `${mysql_database}`.orders
          SET note = 'first-updated', updated = '2026-07-13 02:00:00'
          WHERE id = 1;
        DELETE FROM `${mysql_database}`.orders WHERE id = 2;
        COMMIT;
      SQL
      wait_status caught_up: true, journal_depth: 0, acknowledged: :present
    end

    expect_exit 0
  end

  expect_rows(
    source: [:mysql, <<~SQL],
      SELECT JSON_OBJECT(
        'id', id,
        'note', note,
        'updated', DATE_FORMAT(updated, '%Y-%m-%d %H:%i:%s')
      )
      FROM `${mysql_database}`.orders
      ORDER BY id
    SQL
    sink: [:ducklake, <<~SQL]
      SELECT
        id,
        note,
        strftime(updated, '%Y-%m-%d %H:%M:%S') AS updated
      FROM lake.orders
      ORDER BY id
    SQL
  )
end
