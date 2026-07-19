scenario "append-slow-sink" do
  tier :extended
  requires :postgres
  budget wall: 600, rss_mb: 512
  fixture :postgres, "append-slow-sink"

  # Phase A: establish the slot and a caught-up position on the empty table so
  # the backlog that follows is retained in the source WAL.
  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  # Phase B: a large backlog piles up in the source across several transactions
  # while no worker runs (the inserts complete before the command starts). The
  # run-once then drains the whole backlog in one pass. The RSS ceiling asserts
  # the drain stays bounded rather than scaling with the retained backlog;
  # convergence proves it drains to zero once input stops.
  #
  # This is the honestly black-box-expressible subset of the slow-sink arc. The
  # engine's backpressure and queue-runway signals surface only through the
  # Prometheus metrics endpoint, not the CLI stdout the runner reads, so a
  # "runway warning while input outruns the sink" cannot be asserted here. The
  # attention/runway code surface (worker.runway_at_risk, exit 3) is a source
  # retention concern, exercised by the retention-gap family, not sink lag.
  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~SQL
      INSERT INTO "${schema}".events (id, bucket, payload, doc)
      SELECT g, g % 100, 'backlog-' || g, jsonb_build_object('id', g, 'gen', 'backlog')
      FROM generate_series(1, 40000) AS g;
      INSERT INTO "${schema}".events (id, bucket, payload, doc)
      SELECT g, g % 100, 'backlog-' || g, jsonb_build_object('id', g, 'gen', 'backlog')
      FROM generate_series(40001, 80000) AS g;
      INSERT INTO "${schema}".events (id, bucket, payload, doc)
      SELECT g, g % 100, 'backlog-' || g, jsonb_build_object('id', g, 'gen', 'backlog')
      FROM generate_series(80001, 120000) AS g;
      INSERT INTO "${schema}".events (id, bucket, payload, doc)
      SELECT g, g % 100, 'backlog-' || g, jsonb_build_object('id', g, 'gen', 'backlog')
      FROM generate_series(120001, 160000) AS g;
      INSERT INTO "${schema}".events (id, bucket, payload, doc)
      SELECT g, g % 100, 'backlog-' || g, jsonb_build_object('id', g, 'gen', 'backlog')
      FROM generate_series(160001, 200000) AS g;
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  # Append insert-only, so the sink history matches the source rows exactly.
  expect_rows(
    source: [:postgres, "SELECT count(*)::bigint AS n FROM \"${schema}\".events"],
    sink: [:ducklake, "SELECT count(*)::bigint AS n FROM lake.events"]
  )
end
