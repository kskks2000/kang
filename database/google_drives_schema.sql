-- Google Drive table schema for the Kang app.
-- Target database: dbkang
-- Target schema: kang

CREATE SCHEMA IF NOT EXISTS kang;

CREATE TABLE IF NOT EXISTS kang.google_drives (
    id uuid DEFAULT kang.ms_generate_uuid() NOT NULL,
    user_id uuid,
    drivename text,
    tabname text,
    text01 text,
    text02 text,
    text03 text,
    text04 text,
    text05 text,
    text06 text,
    text07 text,
    text08 text,
    text09 text,
    text10 text,
    text11 text,
    text12 text,
    text13 text,
    text14 text,
    text15 text,
    text16 text,
    text17 text,
    text18 text,
    text19 text,
    text20 text,
    CONSTRAINT pk_google_drives PRIMARY KEY (id)
);

ALTER TABLE kang.google_drives
    ADD COLUMN IF NOT EXISTS user_id uuid;

CREATE INDEX IF NOT EXISTS idx_google_drives_user_id
    ON kang.google_drives USING btree (user_id);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_google_drives_user_id'
          AND conrelid = 'kang.google_drives'::regclass
    ) THEN
        ALTER TABLE kang.google_drives
            ADD CONSTRAINT fk_google_drives_user_id
            FOREIGN KEY (user_id) REFERENCES kang.users(id) ON DELETE CASCADE;
    END IF;
END
$$;

COMMENT ON TABLE kang.google_drives IS
    'Rows imported or synchronized from Google Drive sources.';
COMMENT ON COLUMN kang.google_drives.user_id IS
    'Owner user ID for the imported or synchronized Google Drive row.';
COMMENT ON COLUMN kang.google_drives.drivename IS
    'Google Drive source or file name.';
COMMENT ON COLUMN kang.google_drives.tabname IS
    'Sheet tab or logical table name from the source.';
