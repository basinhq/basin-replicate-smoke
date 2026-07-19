-- One table with a primary key and the default (primary-key) replica identity,
-- so an in-session DROP COLUMN of a non-key column is a compatible relation
-- change routed to the schema_change_policy rather than the incompatible-drift
-- guard a key change would trip first. The no_data start captures nothing; the
-- pre-drop and post-drop rows arrive in the streaming session. `drop_val` is the
-- non-key column removed mid-stream and propagated to the sink.
CREATE SCHEMA "${schema}";

CREATE TABLE "${schema}".dd_items (
    id       integer PRIMARY KEY,
    keep_val text NOT NULL,
    drop_val text
);
