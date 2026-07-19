scenario "cdc-mutations" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "cdc-mutations"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~'SQL'
      BEGIN;
      INSERT INTO "${schema}".orders
        (id, amount, note, created_at, payload, blob, maybe_null)
      VALUES
        (10,
         19.99,
         repeat('x', 5000),
         '2026-07-16 12:00:00.123456+00'::timestamptz,
         '{"k":1}',
         '\xdeadbeef',
         NULL),
        (11,
         5.00,
         'small',
         '2026-07-16 12:01:00.000001+00'::timestamptz,
         '{"k":2}',
         '\x00',
         'present');
      UPDATE "${schema}".orders
        SET amount = 42.50, note = repeat('y', 6000)
        WHERE id = 10;
      UPDATE "${schema}".orders SET id = 12 WHERE id = 11;
      DELETE FROM "${schema}".orders WHERE id = 12;

      INSERT INTO "${schema}".events (id, kind, data, ts)
        VALUES (1, 'created', '{"a":1}', '2026-07-16 12:02:00.111111');
      TRUNCATE "${schema}".events;
      INSERT INTO "${schema}".events (id, kind, data, ts)
        VALUES (2, 'reset', '[1,2,3]', '2026-07-16 12:03:00.222222');
      COMMIT;
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  expect_rows(
    source: [:postgres, <<~SQL],
      SELECT
        id,
        amount::text AS amount,
        note,
        to_char(
          created_at AT TIME ZONE 'UTC',
          'YYYY-MM-DD HH24:MI:SS.US'
        ) AS created_at,
        payload,
        encode(blob, 'hex') AS blob,
        maybe_null
      FROM "${schema}".orders
      ORDER BY id
    SQL
    sink: [:ducklake, <<~SQL]
      SELECT
        id,
        CAST(amount AS VARCHAR) AS amount,
        note,
        strftime(created_at, '%Y-%m-%d %H:%M:%S.%f') AS created_at,
        json(payload) AS payload,
        lower(hex(blob)) AS blob,
        maybe_null
      FROM lake.orders
      ORDER BY id
    SQL
  )

  expect_rows(
    source: [:postgres, <<~SQL],
      SELECT
        id,
        kind,
        data,
        to_char(ts, 'YYYY-MM-DD HH24:MI:SS.US') AS ts
      FROM "${schema}".events
      ORDER BY id
    SQL
    sink: [:ducklake, <<~SQL]
      SELECT
        id,
        kind,
        json(data) AS data,
        strftime(ts, '%Y-%m-%d %H:%M:%S.%f') AS ts
      FROM lake.events
      ORDER BY id
    SQL
  )
end
