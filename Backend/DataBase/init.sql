-- Draft schema for the VM Calculator database.
-- Runs once, on the first start of the database, when the data directory is empty.

-- Users: local accounts and Google accounts. A Google login and a local account
-- with the same email are one user, so the email is unique.
CREATE TABLE users (
    id            SERIAL PRIMARY KEY,
    email         TEXT UNIQUE NOT NULL,
    name          TEXT,
    password_hash TEXT,                 -- empty for a user who only signs in with Google
    google_id     TEXT UNIQUE,          -- empty for a user who only has a local account
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Saved files: the content stays on disk, the database keeps the owner and the path.
-- The limit of 5 files per user is checked by the application.
CREATE TABLE saved_files (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    path       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX saved_files_user_idx ON saved_files (user_id);

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
