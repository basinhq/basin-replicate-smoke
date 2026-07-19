# Contributing

## Getting started

Docker and `just` are the only host requirements. The test runner runs Ruby and its
dependencies in a pinned container.

```sh
just unit                              # Ruby unit tests
just smoke                             # smoke scenarios
just scenario validation-rejects      # one scenario
just cli=/path/to/basin-replicate e2e  # test a local CLI build
```

Run `just unit` before opening a pull request. Run the relevant scenario when a
change affects the runner, providers, fixtures, or scenario DSL.

## Scenarios

Each scenario lives in its own directory under `scenarios/`. Keep its
configuration and `scenario.rb` together. Put source setup in a named fixture
under `fixtures/sql/<provider>/`. The scenario name must match the directory
name.

Declare a suite tier and wall-time budget for every scenario. Reserve
`:extended` for scale or long-running coverage. Add `rss_mb` when memory use is
part of the contract.

Use `:optional` only for scenarios that require an external fixture or exceed
the standard GitHub-hosted runner limits. Optional scenarios run only by name.

Basin must remain an external executable. Exercise it through the `cli`,
`continuous`, or `protocol` DSL methods. Use independent database clients for
source and sink assertions, and do not inspect Basin's private state.

Row comparisons need a stable ordering. Normalize provider-specific values in
SQL and use `streaming: true` for large result sets.

## Code conventions

- Keep comments focused on behavior that the code cannot express by itself.
- Keep analogous scenarios structured alike.
- Reuse an existing named fixture when scenarios need the same source shape.
- Put shared behavior in `lib/basin_acceptance/` and provider-specific behavior
  in `lib/basin_acceptance/providers/`.
- Add or update unit tests for DSL and runner changes.
- Do not commit generated data, retained artifacts, or resolved CLI binaries.

## Pull requests

Keep changes focused and explain why the behavior is correct. Include the exact
commands used for verification. Update the README when commands, requirements,
or supported workflows change.
