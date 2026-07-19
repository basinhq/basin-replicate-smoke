scenario "cadence-lease" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "cadence-lease"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:already_caught_up"
    replay_identically
  end
end
