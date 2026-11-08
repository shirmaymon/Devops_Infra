-- Draft schema for the VM Calculator database.
-- Runs once, on the first start of the database, when the data directory is empty.

-- Users: local accounts and Google accounts. A Google login and a local account
-- with the same email are one user, so the email is unique.
-- (Used by the auth service.)
CREATE TABLE users (
    id            SERIAL PRIMARY KEY,
    email         TEXT UNIQUE NOT NULL,
    name          TEXT,
    password_hash TEXT,                 -- empty for a user who only signs in with Google
    google_id     TEXT UNIQUE,          -- empty for a user who only has a local account
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Saved files: the content is stored in the database as JSON.
-- The owner is the logged-in user. The limit of 5 files per user is checked by the application.
CREATE TABLE saved_files (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    filename   TEXT NOT NULL,           -- <name>_DD-MM-YYYY_HH-MM_<id>.json
    data       JSONB NOT NULL,          -- the saved hosts, users and machines
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, filename)
);

CREATE INDEX saved_files_owner_idx ON saved_files (user_id, created_at);

-- Login sessions. The browser holds a random session ID in a cookie; only its SHA-256 hash is
-- stored here. The auth service and the Flask API both read this table.
-- Logout deletes the row. A session ends at expires_at (absolute) or after an idle period
-- (last_seen); the values are set by the services, see common.py.
CREATE TABLE sessions (
    id_hash    TEXT PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    csrf_token TEXT NOT NULL,           -- CSRF token of this session, sent by the page in a header
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX sessions_user_idx ON sessions (user_id);

-- Cloud VM prices, pulled from the clouds once a day, with the time of the pull.
CREATE TABLE cloud_prices (
    id            SERIAL PRIMARY KEY,
    cloud         TEXT NOT NULL,        -- for example aws, azure, gcp
    machine_type  TEXT NOT NULL,
    price_per_hour NUMERIC(12, 6) NOT NULL,
    currency      TEXT NOT NULL DEFAULT 'USD',
    pulled_at     TIMESTAMPTZ NOT NULL
);

CREATE INDEX cloud_prices_lookup_idx ON cloud_prices (cloud, machine_type, pulled_at DESC);
