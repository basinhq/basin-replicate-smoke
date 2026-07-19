CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".customers (
    id bigint PRIMARY KEY,
    name text NOT NULL,
    region text NOT NULL
);
ALTER TABLE "${schema}".customers REPLICA IDENTITY FULL;

CREATE TABLE "${schema}".order_items (
    order_id integer NOT NULL,
    line_no integer NOT NULL,
    sku text NOT NULL,
    qty integer NOT NULL,
    PRIMARY KEY (order_id, line_no)
);
ALTER TABLE "${schema}".order_items REPLICA IDENTITY FULL;

INSERT INTO "${schema}".customers (id, name, region) VALUES
    (1, 'Ada', 'emea'),
    (2, 'Bela', 'apac'),
    (3, 'Chidi', 'amer');

INSERT INTO "${schema}".order_items (order_id, line_no, sku, qty) VALUES
    (100, 1, 'sku-a', 2),
    (100, 2, 'sku-b', 1),
    (101, 1, 'sku-c', 5);
