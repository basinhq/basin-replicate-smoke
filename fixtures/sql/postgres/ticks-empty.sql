CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".ticks (
    id integer PRIMARY KEY,
    label text NOT NULL
);
ALTER TABLE "${schema}".ticks REPLICA IDENTITY FULL;
