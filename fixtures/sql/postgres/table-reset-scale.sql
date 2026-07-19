CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".items (
    id bigint PRIMARY KEY,
    item_type text NOT NULL,
    author text,
    created_at timestamp NOT NULL,
    title text,
    body text,
    url text,
    score bigint,
    parent_id bigint,
    descendants bigint,
    kids jsonb NOT NULL,
    raw jsonb NOT NULL
);
ALTER TABLE "${schema}".items REPLICA IDENTITY FULL;

CREATE TABLE "${schema}".control (
    id bigint PRIMARY KEY,
    body text NOT NULL
);
ALTER TABLE "${schema}".control REPLICA IDENTITY FULL;

INSERT INTO "${schema}".items (
    id, item_type, author, created_at, title, body, url, score,
    parent_id, descendants, kids, raw
)
SELECT
    id,
    CASE WHEN id % 10 = 0 THEN 'story' ELSE 'comment' END,
    'user_' || (id % 10000),
    timestamp '2024-01-01 00:00:00' + (id * interval '1 second'),
    CASE WHEN id % 10 = 0 THEN 'Story ' || id ELSE NULL END,
    CASE
        WHEN id % 10 = 0 THEN NULL
        ELSE '<p>Comment ' || id || ' ' || repeat(chr(97 + (id % 26)::integer), 1800) || '</p>'
    END,
    CASE WHEN id % 10 = 0 THEN 'https://news.example/items/' || id ELSE NULL END,
    CASE WHEN id % 10 = 0 THEN id % 500 ELSE NULL END,
    CASE WHEN id % 10 = 0 THEN NULL ELSE (id / 10) * 10 END,
    CASE WHEN id % 10 = 0 THEN id % 200 ELSE NULL END,
    CASE
        WHEN id % 10 = 0 THEN jsonb_build_array(id + 1, id + 2, id + 3)
        ELSE '[]'::jsonb
    END,
    jsonb_build_object(
        'id', id,
        'type', CASE WHEN id % 10 = 0 THEN 'story' ELSE 'comment' END,
        'by', 'user_' || (id % 10000),
        'time', 1704067200 + id,
        'dead', false,
        'deleted', false
    )
FROM generate_series(1, ${scale_rows}) AS id;

INSERT INTO "${schema}".control VALUES (1, 'before-reset');
