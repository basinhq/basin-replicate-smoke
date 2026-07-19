scenario "validation-rejects" do
  tier :smoke
  budget wall: 10

  cli "run-once", config: "config.json" do
    expect_exit 65
    expect_error_count at_least: 3
    expect_error_codes "worker.unknown_connector", "config.unknown_variant"
    expect_error_paths "/source/kind", "/sink/kind", "/worker/lease_overlap"
    replay_identically
  end
end
