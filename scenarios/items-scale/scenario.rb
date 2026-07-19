scenario "items-scale" do
  tier :extended
  requires :postgres
  budget wall: 900, rss_mb: 512
  fixture :postgres, "items-scale"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end

  expect_rows(
    source: [:postgres, "SELECT count(*)::bigint AS n FROM \"${schema}\".items"],
    sink: [:ducklake, "SELECT count(*)::bigint AS n FROM lake.items"]
  )
end
