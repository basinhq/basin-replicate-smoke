CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".orders (
    id bigint PRIMARY KEY,
    status text NOT NULL
);
ALTER TABLE "${schema}".orders REPLICA IDENTITY FULL;

CREATE TABLE "${schema}".audit (
    id bigint PRIMARY KEY,
    action text NOT NULL
);
ALTER TABLE "${schema}".audit REPLICA IDENTITY FULL;

INSERT INTO "${schema}".orders (id, status) VALUES
    (1, 'pending'),
    (2, 'pending'),
    (3, 'shipped');

INSERT INTO "${schema}".audit (id, action) VALUES
    (1, 'created'),
    (2, 'updated');
