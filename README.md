# basin-replicate-smoke

Black-box smoke and end-to-end tests for the
[basin-replicate](https://github.com/basinhq/basin-replicate) CLI.

The test runner treats Basin as an external executable. It does not build or load
the Rust workspace, native library, or Ruby gem. Docker and `just` are the only
host requirements.

## Run the tests

### Unit tests

```sh
just unit
```

These test the Ruby code in `lib/`. They do not run Basin or start databases.

- Scenario parsing, validation, and suite selection
- Process control, timeout handling, and memory sampling
- Provider output parsing and row comparison

### Smoke tests

```sh
just smoke
```

These are the two quickest end-to-end checks.

- Replicate PostgreSQL rows into DuckLake and verify the result
- Reject an invalid configuration with stable errors and exit codes

### E2E tests

```sh
just e2e
```

This is the normal end-to-end suite.

- PostgreSQL and MySQL snapshots and change capture
- DuckLake and ClickHouse delivery
- Schema changes, restarts, retention gaps, and graceful shutdown

### Full E2E tests

```sh
just e2e-full
```

This runs every scenario, including slower coverage excluded from `just e2e`.

- Large snapshots and change streams with memory limits
- Slow sinks, resets, and long-running recovery cases

Large scenarios use deterministic synthetic events. Run one source and sink:

```sh
just scenario scale-sync-postgres-ducklake
just scenario scale-sync-postgres-clickhouse
just scenario scale-sync-mysql-ducklake
just scenario scale-sync-mysql-clickhouse
```

Run all four source/sink combinations together:

```sh
just scenario scale-sync
```

Choose a scale on the command line. Each step is ten times larger:

```sh
just scale=s scenario scale-sync-postgres-ducklake
just scale=xl scenario scale-append-mysql-clickhouse
```

The available scales are `s` (10,000 rows), `m` (100,000), `l` (1,000,000),
`xl` (10,000,000), and `2xl` (100,000,000). The default is `l`. Each scenario
also appends a batch equal to one tenth of its initial rows.

CI runs one PostgreSQL-to-ClickHouse scale check at `s`. Release testing runs
PostgreSQL-to-ClickHouse and MySQL-to-DuckLake at `l`, covering both snapshot
and append modes. The nightly suite runs the complete matrix at `xl`.

### One scenario

```sh
just scenario validation-rejects
just scenario mysql-cdc-mutations
```

Use a scenario name from `scenarios/` to run only that case.
`scale-sync` and `scale-append` run their four source/sink combinations.
`scale` runs both groups.

Containers and database volumes are removed after each run, including an
interrupted run. Remove this repository's Docker images, downloaded CLI, and
reports when they are no longer needed:

```sh
just clean
```

## Choosing the Basin build

End-to-end runs use the published `latest` pack image by default. To test
another build:

```sh
just cli=/path/to/basin-replicate smoke
just tag=v0.4.0 e2e
just image=ghcr.io/basinhq/basin-replicate-pack@sha256:... smoke
```

The matching environment variables are `BASIN_TEST_CLI`, `BASIN_CLI_TAG`, and
`BASIN_CLI_IMAGE`. `BASIN_CLI_REPO` can override the default pack repository.
The resolver uses a local binary first, then a full image reference, then a
repository and tag.

The selected binary is mounted read-only into the runner container. A preflight
check reports incompatible glibc requirements before any scenario starts.
Every E2E run writes Markdown and JSON result reports under `artifacts/`. The
report includes scenario status, total and CLI time, peak CLI RSS, measured row
counts, and throughput for scale scenarios. Failed runs also keep their
rendered config, arguments, stdout, and stderr. GitHub Actions adds the Markdown
table to the job summary and uploads the complete directory.

## Test environment

Docker Compose provides PostgreSQL, MySQL, and ClickHouse. The runner image also
contains pinned DuckDB and DuckLake releases with verified checksums.

Each scenario gets isolated database resources and an empty CLI cache. This
keeps scenarios independent when they run concurrently. Source and sink checks
use ordinary database clients or the public Basin `query` command. The runner
does not inspect Basin's private state tables.

## Scenarios

Each directory under `scenarios/` contains:

- `scenario.rb`, written with the DSL in `lib/basin_acceptance/scenario.rb`
- one or more Basin JSON configuration files

A scenario declares its suite tier, required services, wall-time budget, setup,
commands, and assertions. Basin operations must go through the `cli`,
`continuous`, or `protocol` DSL methods.

```ruby
scenario "snapshot-basic" do
  tier :standard
  requires :postgres
  budget wall: 60
  fixture :postgres, "snapshot-basic"

  cli "run-once", config: "config.json" do
    expect_exit 0
    expect_once "once:made_progress"
  end
end
```

Placeholders such as `${schema}` are expanded in configuration files, CLI
arguments, and SQL. Row comparisons should use a stable ordering and normalize
provider-specific values in SQL. Set `streaming: true` for large comparisons so
the runner does not retain both result sets in memory.

Continuous scenarios can wait for provider readiness, apply SQL between gates,
poll public status, send a shutdown signal, and check the destination. Polling
defaults to 20 seconds and can be changed with `wait_timeout`.

Extended scenarios can add an RSS limit:

```ruby
budget wall: 120, rss_mb: 512
```

The runner samples the full CLI process group through Linux `/proc`. Extended
scale scenarios use 40,000 rows by default. Override that value with
`BASIN_ACCEPTANCE_SCALE_ROWS`.

## Sharding

Scenarios are assigned to shards by declared wall-time budget. Assignment is
stable for a given scenario set.

```sh
just shard e2e 1 2
```

Each local shard receives its own Compose project name. CI runs every shard on
a separate machine.

## Fixtures

Every end-to-end scenario obtains its source setup from `fixtures/`. Named SQL
fixtures live under `fixtures/sql/<provider>/`. Shared fixtures are referenced
by more than one scenario instead of being copied.

Large event fixtures generate deterministic synthetic rows at the selected
scale. Scenario files contain only post-load changes and expected results. See
[fixtures/README.md](fixtures/README.md) for the layout and scale definitions.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a change. Participation
is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Report vulnerabilities
privately as described in [SECURITY.md](SECURITY.md).

This project is licensed under the [Apache License 2.0](LICENSE).
