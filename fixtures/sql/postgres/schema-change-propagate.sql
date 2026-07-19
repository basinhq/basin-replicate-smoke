CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".items (
    id integer PRIMARY KEY,
    value text NOT NULL
);
ALTER TABLE "${schema}".items REPLICA IDENTITY FULL;
