scenario "protocol-drive" do
  tier :standard
  budget wall: 10

  protocol config: "broken-config.json" do
    expect_exit 0
    expect_protocol_version 1
    expect_status_state "stopped"
    expect_error_count at_least: 3
    expect_error_codes "worker.unknown_connector", "config.unknown_variant"
    expect_error_paths "/source/kind", "/sink/kind", "/worker/lease_overlap"
  end

  protocol config: "config.json" do
    expect_exit 0
    expect_protocol_version 1
    expect_status_state "stopped"
    expect_error_count at_most: 0
    replay_identically
  end
end
