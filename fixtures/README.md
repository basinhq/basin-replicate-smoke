# Fixtures

Every data-backed E2E scenario declares its initial source state through the
fixture DSL:

```ruby
fixture :postgres, "orders-basic"
```

The runner resolves this to `sql/postgres/orders-basic.sql`, renders scenario
placeholders, and executes it before the first Basin command. MySQL fixtures use
the same convention under `sql/mysql/`.

Fixtures own schemas and initial data. Scenarios own pipeline configuration,
changes made after the initial load, and assertions. Reuse a fixture whenever
multiple scenarios need the same source shape.

## Scale fixtures

`events-large` deterministically generates the same event-shaped rows in
PostgreSQL and MySQL. Both append and current-state sync scenarios exercise it
against DuckLake and ClickHouse.

Choose a named scale with `just scale=<name>`:

| Scale | Initial rows | Appended rows |
|---|---:|---:|
| `s` | 10,000 | 1,000 |
| `m` | 100,000 | 10,000 |
| `l` | 1,000,000 | 100,000 |
| `xl` | 10,000,000 | 1,000,000 |
| `2xl` | 100,000,000 | 10,000,000 |

The default is `l`. For example:

```sh
just scale=s scenario scale-sync-postgres-ducklake
just scale=xl scenario scale-append-mysql-clickhouse
```

Each scale is one order of magnitude larger than the previous scale. Add a new
name to `BasinAcceptance::Context::SCALE_ROWS` when a larger runner needs the
next order of magnitude.
