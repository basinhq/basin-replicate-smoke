# Security policy

## Reporting a vulnerability

Report vulnerabilities privately through
[GitHub security advisories](https://github.com/basinhq/basin-replicate-smoke/security/advisories/new).
Do not open a public issue for a vulnerability that could expose credentials,
execute unintended commands, escape the runner container, or silently report an
incorrect test result.

You should receive an acknowledgement within a week.

## Scope

This repository contains a test runner that executes an externally supplied Basin
binary and connects it to disposable database services. Reports are in scope
when they concern the runner, its container boundary, CLI artifact handling,
configuration rendering, logs, or retained artifacts.

Vulnerabilities in the Basin CLI itself belong in the
[basin-replicate security advisory form](https://github.com/basinhq/basin-replicate/security/advisories/new).

The credentials in `compose.yml` are fixed local test credentials for
disposable services. They are not production secrets.
