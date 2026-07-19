CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".events (
    id bigint PRIMARY KEY,
    user_id bigint NOT NULL,
    event_name text NOT NULL,
    occurred_at timestamp NOT NULL,
    properties jsonb NOT NULL
);
ALTER TABLE "${schema}".events REPLICA IDENTITY FULL;

INSERT INTO "${schema}".events
SELECT
    id,
    id % 100000,
    (ARRAY['page_view', 'button_click', 'signup', 'purchase'])[1 + id % 4],
    timestamp '2024-01-01 00:00:00' + id * interval '1 second',
    jsonb_build_object('session_id', 'session_' || id % 250000, 'path', '/page/' || id % 1000)
FROM generate_series(1, ${large_rows}) AS id;

CREATE TABLE "${schema}".events_append
    (LIKE "${schema}".events INCLUDING ALL);
INSERT INTO "${schema}".events_append
SELECT
    ${large_rows} + id,
    id % 100000,
    'tail',
    timestamp '2025-01-01 00:00:00' + id * interval '1 second',
    jsonb_build_object('batch', 'tail', 'id', id)
FROM generate_series(1, ${append_rows}) AS id;
