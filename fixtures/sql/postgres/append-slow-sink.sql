CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".events (
    id      bigint PRIMARY KEY,
    bucket  integer NOT NULL,
    payload text NOT NULL,
    doc     jsonb NOT NULL
);
ALTER TABLE "${schema}".events REPLICA IDENTITY FULL;
