SELECT pg_create_logical_replication_slot('${slot}', 'pgoutput');

CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".ledger (
    id integer PRIMARY KEY,
    entry text NOT NULL
);
ALTER TABLE "${schema}".ledger REPLICA IDENTITY FULL;
