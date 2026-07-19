CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".mt_orders (
    id     bigint PRIMARY KEY,
    status text NOT NULL
);

CREATE TABLE "${schema}".mt_events (
    id   bigint PRIMARY KEY,
    kind text NOT NULL
);

CREATE TABLE "${schema}".mt_metrics (
    id    bigint PRIMARY KEY,
    value bigint NOT NULL
);

INSERT INTO "${schema}".mt_orders (id, status) VALUES
    (1, 'pending'),
    (2, 'pending');

INSERT INTO "${schema}".mt_events (id, kind) VALUES
    (1, 'created'),
    (2, 'shipped');

INSERT INTO "${schema}".mt_metrics (id, value) VALUES
    (1, 100),
    (2, 200);
