scenario "table-reset-scale" do
  tier :extended
  requires :postgres
  budget wall: 2100, rss_mb: 512
  fixture :postgres, "table-reset-scale"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "reset", "--table", "${schema}.items", config: "config.json" do
    before_sql :postgres, <<~SQL
      DELETE FROM "${schema}".items WHERE id % 10 = 0;
      UPDATE "${schema}".items
      SET body = 'changed before reset'
      WHERE id = 1;
      INSERT INTO "${schema}".items (
          id, item_type, author, created_at, title, body, url, score,
          parent_id, descendants, kids, raw
      ) VALUES (
          1000000000,
          'comment',
          'reset_user',
          timestamp '2025-01-01 00:00:00',
          NULL,
          'inserted before reset',
          NULL,
          NULL,
          1,
          NULL,
          '[]'::jsonb,
          '{"id":1000000000,"type":"comment"}'::jsonb
      );
      UPDATE "${schema}".control
      SET body = 'caught-up-during-reset'
      WHERE id = 1;
    SQL
    expect_exit 0
  end

  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~SQL
      INSERT INTO "${schema}".items (
          id, item_type, author, created_at, title, body, url, score,
          parent_id, descendants, kids, raw
      ) VALUES (
          1000000001,
          'comment',
          'resume_user',
          timestamp '2025-01-01 00:00:01',
          NULL,
          'inserted after reset',
          NULL,
          NULL,
          1,
          NULL,
          '[]'::jsonb,
          '{"id":1000000001,"type":"comment"}'::jsonb
      );
      UPDATE "${schema}".control
      SET body = 'resumed-after-reset'
      WHERE id = 1;
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  expect_rows(
    source: [:postgres, "SELECT count(*)::bigint AS n FROM \"${schema}\".items"],
    sink: [:ducklake, "SELECT count(*)::bigint AS n FROM lake.items"]
  )

  expect_rows(
    source: [:postgres, <<~SQL],
      SELECT id, body
      FROM "${schema}".items
      WHERE id IN (1, 10, 1000000000, 1000000001)
      ORDER BY id
    SQL
    sink: [:ducklake, <<~SQL],
      SELECT id, body
      FROM lake.items
      WHERE id IN (1, 10, 1000000000, 1000000001)
      ORDER BY id
    SQL
    streaming: true
  )

  expect_rows(
    source: [:postgres, <<~SQL],
      SELECT id, body
      FROM "${schema}".control
      ORDER BY id
    SQL
    sink: [:ducklake, <<~SQL],
      SELECT id, body
      FROM lake.control
      ORDER BY id
    SQL
    streaming: true
  )
end
