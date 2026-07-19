CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".readings (
    id integer PRIMARY KEY,
    tz timestamptz NOT NULL,
    tsn timestamp NOT NULL,
    blob bytea NOT NULL,
    note text NOT NULL
);
ALTER TABLE "${schema}".readings REPLICA IDENTITY FULL;
