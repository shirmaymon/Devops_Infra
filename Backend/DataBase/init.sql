-- Draft schema for the VM Calculator database.
-- Runs once, on the first start of the database, when the data directory is empty.

-- Users: local accounts and Google accounts. A Google login and a local account
-- with the same email are one user, so the email is unique.
-- (Used by the auth service, which is not built yet.)
CREATE TABLE users (
    id            SERIAL PRIMARY KEY,
    email         TEXT UNIQUE NOT NULL,
    name          TEXT,
    password_hash TEXT,                 -- empty for a user who only signs in with Google
    google_id     TEXT UNIQUE,          -- empty for a user who only has a local account
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Saved files: the content is stored in the database as JSON.
-- For now the owner is identified by first and last name (lowercase), as in the current app.
-- When the auth service exists, the owner becomes a user_id that references users(id).
-- The limit of 5 files per owner is checked by the application.
CREATE TABLE saved_files (
    id         SERIAL PRIMARY KEY,
    first_name TEXT NOT NULL,
    last_name  TEXT NOT NULL,
    filename   TEXT NOT NULL,           -- <first>_<last>_DD-MM-YYYY_HH-MM.json
    data       JSONB NOT NULL,          -- the saved hosts, users and machines
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (first_name, last_name, filename)
);

CREATE INDEX saved_files_owner_idx ON saved_files (first_name, last_name, created_at);

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
