CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".vf_orders (
    id bigint PRIMARY KEY,
    status text NOT NULL
);
ALTER TABLE "${schema}".vf_orders REPLICA IDENTITY FULL;

INSERT INTO "${schema}".vf_orders (id, status) VALUES
    (1, 'pending'),
    (2, 'pending'),
    (3, 'pending');
