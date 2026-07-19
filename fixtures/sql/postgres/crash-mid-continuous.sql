CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".backlog (
    id bigint PRIMARY KEY,
    payload text NOT NULL
);
ALTER TABLE "${schema}".backlog REPLICA IDENTITY FULL;
