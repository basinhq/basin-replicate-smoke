scenario "items-snapshot" do
  tier :extended
  requires :postgres
  budget wall: 240, rss_mb: 512
  fixture :postgres, "items-snapshot"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~SQL
      INSERT INTO "${schema}".items (
          id, item_type, author, created_at, title, body, url, score,
          parent_id, descendants, kids, raw
      ) VALUES (
          ${scale_rows} + 1,
          'story',
          'new_user',
          timestamp '2025-01-01 00:00:00',
          'A new story',
          NULL,
          'https://news.example/new',
          1,
          NULL,
          0,
          '[]'::jsonb,
          jsonb_build_object(
              'id', ${scale_rows} + 1,
              'type', 'story',
              'by', 'new_user'
          )
      );
      UPDATE "${schema}".items
      SET score = 999, title = 'Updated story'
      WHERE id = 10;
      DELETE FROM "${schema}".items WHERE id = 3;
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  expect_rows(
    source: [:postgres, <<~SQL],
      SELECT
        id,
        item_type,
        author,
        to_char(created_at, 'YYYY-MM-DD HH24:MI:SS.US') AS created_at,
        title,
        body,
        url,
        score,
        parent_id,
        descendants,
        kids,
        raw
      FROM "${schema}".items
      ORDER BY id
    SQL
    sink: [:ducklake, <<~SQL],
      SELECT
        id,
        item_type,
        author,
        strftime(created_at, '%Y-%m-%d %H:%M:%S.%f') AS created_at,
        title,
        body,
        url,
        score,
        parent_id,
        descendants,
        json(kids) AS kids,
        json(raw) AS raw
      FROM lake.items
      ORDER BY id
    SQL
    streaming: true
  )
end
