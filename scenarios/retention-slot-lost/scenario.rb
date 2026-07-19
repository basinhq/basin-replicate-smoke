scenario "retention-slot-lost" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "ticks-empty"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
  end

  # Deliver real work so the pipeline durably acknowledges a position.
  cli "run-once", config: "config.json" do
    before_sql :postgres, <<~SQL
      INSERT INTO "${schema}".ticks (id, label) VALUES (1, 'first');
    SQL
    expect_exit 0
    expect_once "once:made_progress"
  end

  # The slot vanishes under an acknowledged pipeline: operator recovery with
  # its own stable code, never a silent restart from the current head and not
  # the carrier-gap report a never-acknowledged pipeline gets (retention-gap
  # covers that half).
  cli "run-once", config: "config.json" do
    before_sql :postgres, "SELECT pg_drop_replication_slot('${slot}')"
    expect_exit 3
    expect_once "once:needs_attention"
    expect_error_codes "worker.source_position_lost"
  end
end
