-- Two tables seeded before the pipeline exists so the initial-snapshot run copies
-- both and both become covered. tp_orders is the table dropped at the source
-- between runs while the configuration still selects it; tp_events is the table
-- that keeps its coverage and stays intact. Integer and text columns only.
CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".tp_orders (
    id  integer PRIMARY KEY,
    sku text NOT NULL
);
INSERT INTO "${schema}".tp_orders (id, sku) VALUES (1, 'sku-a'), (2, 'sku-b');

CREATE TABLE "${schema}".tp_events (
    id    integer PRIMARY KEY,
    label text NOT NULL
);
INSERT INTO "${schema}".tp_events (id, label) VALUES (1, 'seeded-1'), (2, 'seeded-2');
