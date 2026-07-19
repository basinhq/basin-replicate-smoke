CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".events (
    id bigint PRIMARY KEY,
    payload text NOT NULL
);
ALTER TABLE "${schema}".events REPLICA IDENTITY FULL;
