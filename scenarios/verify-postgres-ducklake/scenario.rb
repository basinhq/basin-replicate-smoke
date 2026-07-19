# Black-box smoke of the `verify` subcommand against the shipped CLI. A
# converged PostgreSQL-to-DuckLake pipeline verifies clean (exit 0); a row
# tampered directly in the sink, bypassing the pipeline, makes the next verify
# find the divergence (exit 3). The runner asserts the exit contract; asserting
# the NDJSON connectivity and summary lines awaits a verify-output matcher in the
# smoke DSL, the follow-up noted alongside the e2e driver.
scenario "verify-postgres-ducklake" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "verify-postgres-ducklake"

  # Copy the three seeded rows as the initial snapshot.
  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  # A converged pipeline: the source and sink agree, so verify exits 0.
  cli "verify", config: "config.json" do
    expect_exit 0
  end

  # Tamper one row directly in the DuckLake sink, bypassing the pipeline.
  cli "query", "--target", "sink", "--write",
      "UPDATE lake.vf_orders SET status = 'tampered' WHERE id = 2",
      config: "config.json" do
    expect_exit 0
    expect_query_rows []
  end

  # verify now reads both sides independently, finds the divergence at id 2,
  # and exits 3.
  cli "verify", config: "config.json" do
    expect_exit 3
  end
end
