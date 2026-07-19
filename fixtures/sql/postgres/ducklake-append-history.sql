CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".items (
    id   bigint PRIMARY KEY,
    note text NOT NULL
);
ALTER TABLE "${schema}".items REPLICA IDENTITY FULL;
