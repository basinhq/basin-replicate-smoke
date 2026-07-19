scenario "cdc-typed-scalars" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "cdc-typed-scalars"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~'SQL'
      INSERT INTO "${schema}".readings (id, tz, tsn, blob, note) VALUES
        (1,
         '2026-07-13 00:05:13.903178+00'::timestamptz,
         '2026-07-13 00:05:13.903178'::timestamp,
         '\xdeadbeef'::bytea,
         'alpha'),
        (2,
         '2000-01-01 12:34:56.000001+00'::timestamptz,
         '1999-12-31 23:59:59.999999'::timestamp,
         '\x00ff10'::bytea,
         'bravo');
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  expect_rows(
    source: [:postgres, <<~SQL],
      SELECT
        id,
        to_char(tz AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') AS tz,
        to_char(tsn, 'YYYY-MM-DD HH24:MI:SS.US') AS tsn,
        encode(blob, 'hex') AS blob,
        note
      FROM "${schema}".readings
      ORDER BY id
    SQL
    sink: [:ducklake, <<~SQL]
      SELECT
        id,
        strftime(tz, '%Y-%m-%d %H:%M:%S.%f') AS tz,
        strftime(tsn, '%Y-%m-%d %H:%M:%S.%f') AS tsn,
        lower(hex(blob)) AS blob,
        note
      FROM lake.readings
      ORDER BY id
    SQL
  )
end
