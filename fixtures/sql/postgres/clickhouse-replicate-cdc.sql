CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".orders (
    id bigint PRIMARY KEY,
    qty integer NOT NULL,
    note text NOT NULL,
    active boolean NOT NULL,
    maybe_null text
);
ALTER TABLE "${schema}".orders REPLICA IDENTITY FULL;

CREATE TABLE "${schema}".events (
    id bigint PRIMARY KEY,
    kind text NOT NULL
);
ALTER TABLE "${schema}".events REPLICA IDENTITY FULL;
