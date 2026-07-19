CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".events (
    id bigint PRIMARY KEY,
    ts timestamp NOT NULL,
    note text NOT NULL
);
ALTER TABLE "${schema}".events REPLICA IDENTITY FULL;

INSERT INTO "${schema}".events (id, ts, note) VALUES
    (1, '2025-12-01 08:00:00'::timestamp, 'pending'),
    (2, '2026-01-15 09:30:00'::timestamp, 'pending'),
    (3, '2026-07-13 10:45:00'::timestamp, 'pending');
