scenario "table-drop-parks" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "table-drop-parks"

  # BEHAVIOR 3.9, the PostgreSQL initial-pass detection path.
  #
  # 3.9: a covered table dropped at the source never stops the pipeline. The next
  # `initial` pass finds it vanished while the configuration still selects it,
  # warns with worker.collection_dropped_at_source, marks its coverage
  # missing-at-source, retains its sink data, and keeps the other table covered and
  # replicating.
  #
  # PostgreSQL logical replication carries no DDL, so a mid-stream DROP TABLE is
  # never seen on the stream; the drop is detected on the next initial pass. Under
  # publication_mode = create_if_missing with a fixed include_tables selection, that
  # pass reconciles the publication over only the tables that still exist rather
  # than issuing `ALTER PUBLICATION <pub> SET TABLE <dropped>, <survivor>` (which
  # PostgreSQL would reject for the missing relation). So the run reaches the
  # mark-missing branch and parks tp_orders instead of failing with
  # worker.source_unavailable. The MySQL side of the drop-park parks in-session off
  # the binlog (proven by the e2e dt-drop-parks-mysql scenario); its PostgreSQL twin
  # is the e2e dt-drop-parks-postgres.

  # Run 1 copies both seeded tables at a consistent boundary, so both become
  # covered, and provisions the publication over the pair.
  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  # Run 2 runs after tp_orders is dropped at the source while the configuration
  # still selects it, and a post-drop row is inserted into the surviving tp_events.
  # The initial pass re-discovers, reconciles the publication over the survivor
  # alone, parks tp_orders (marking it missing-at-source and retaining its sink
  # data), and streams the post-drop row: made progress, exit 0. status --json then
  # lists tp_orders under missing_at_source.
  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~SQL
      DROP TABLE "${schema}".tp_orders;
      INSERT INTO "${schema}".tp_events (id, label) VALUES (3, 'post-drop');
    SQL
    expect_exit 0
    expect_once "once:made_progress"
    expect_missing_at_source namespace: "${schema}", name: "tp_orders"
  end

  # The surviving table converges: the two snapshot-copied rows plus the streamed
  # post-drop row, exactly once. tp_orders is intentionally not compared: it no
  # longer exists at the source, and its retained lake data is the operator's to
  # remove.
  expect_rows(
    source: [:postgres, "SELECT id, label FROM \"${schema}\".tp_events ORDER BY id"],
    sink: [:ducklake, "SELECT id, label FROM lake.tp_events ORDER BY id"]
  )
end
