CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".events (
    id bigint PRIMARY KEY,
    payload text NOT NULL
);
ALTER TABLE "${schema}".events REPLICA IDENTITY FULL;

INSERT INTO "${schema}".events (id, payload)
SELECT id, repeat('x', 100)
FROM generate_series(1, ${scale_rows}) AS id;
