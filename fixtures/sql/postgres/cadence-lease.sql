CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".orders (
    id integer PRIMARY KEY,
    entry text NOT NULL
);
ALTER TABLE "${schema}".orders REPLICA IDENTITY FULL;
