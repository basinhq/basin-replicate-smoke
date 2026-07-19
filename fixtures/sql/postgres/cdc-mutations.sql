CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".orders (
    id integer PRIMARY KEY,
    amount numeric(12, 2) NOT NULL,
    note text NOT NULL,
    created_at timestamptz NOT NULL,
    payload jsonb NOT NULL,
    blob bytea NOT NULL,
    maybe_null text
);
ALTER TABLE "${schema}".orders REPLICA IDENTITY FULL;

CREATE TABLE "${schema}".events (
    id integer PRIMARY KEY,
    kind text NOT NULL,
    data jsonb NOT NULL,
    ts timestamp NOT NULL
);
ALTER TABLE "${schema}".events REPLICA IDENTITY FULL;
