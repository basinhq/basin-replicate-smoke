CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".orders (
    id     bigint PRIMARY KEY,
    status text NOT NULL
);
ALTER TABLE "${schema}".orders REPLICA IDENTITY FULL;

INSERT INTO "${schema}".orders (id, status) VALUES
    (1, 'pending'),
    (2, 'pending'),
    (3, 'pending');
