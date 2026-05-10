-- Google OAuth storage for Calendar and Drive integrations.
-- Target database: dbkang
-- Target schema: kang

CREATE SCHEMA IF NOT EXISTS kang;

CREATE OR REPLACE FUNCTION kang.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$function$;

CREATE TABLE IF NOT EXISTS kang.google_oauth_accounts (
    id uuid DEFAULT kang.ms_generate_uuid() NOT NULL,
    user_id uuid NOT NULL,
    google_subject text NOT NULL,
    google_email text NOT NULL,
    display_name text,
    photo_url text,
    scopes text[] DEFAULT ARRAY[]::text[] NOT NULL,
    access_token_encrypted text,
    refresh_token_encrypted text,
    token_type text DEFAULT 'Bearer'::text NOT NULL,
    expires_at timestamp with time zone,
    key_version text DEFAULT 'v1'::text NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    last_refreshed_at timestamp with time zone,
    last_used_at timestamp with time zone,
    connected_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT google_oauth_accounts_pkey PRIMARY KEY (id),
    CONSTRAINT google_oauth_accounts_user_id_fkey FOREIGN KEY (user_id)
        REFERENCES kang.users(id) ON DELETE CASCADE,
    CONSTRAINT google_oauth_accounts_status_check
        CHECK (status IN ('active', 'expired', 'revoked', 'error'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_google_oauth_accounts_active_subject
    ON kang.google_oauth_accounts USING btree (google_subject)
    WHERE revoked_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_google_oauth_accounts_primary_user
    ON kang.google_oauth_accounts USING btree (user_id)
    WHERE is_primary = true AND revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_google_oauth_accounts_user_id
    ON kang.google_oauth_accounts USING btree (user_id);

CREATE INDEX IF NOT EXISTS ix_google_oauth_accounts_email
    ON kang.google_oauth_accounts USING btree (lower(google_email));

CREATE INDEX IF NOT EXISTS ix_google_oauth_accounts_status
    ON kang.google_oauth_accounts USING btree (status, expires_at);

COMMENT ON TABLE kang.google_oauth_accounts IS
    'Linked Google OAuth accounts for Calendar, Drive, and future Google Workspace APIs.';
COMMENT ON COLUMN kang.google_oauth_accounts.google_subject IS
    'Stable Google account subject claim. Used to prevent one Google account from being linked to multiple Kang users.';
COMMENT ON COLUMN kang.google_oauth_accounts.scopes IS
    'Granted OAuth scopes such as calendar.events or drive.file.';
COMMENT ON COLUMN kang.google_oauth_accounts.access_token_encrypted IS
    'Encrypted short-lived Google access token. Never store a plain access token here.';
COMMENT ON COLUMN kang.google_oauth_accounts.refresh_token_encrypted IS
    'Encrypted long-lived Google refresh token for offline access. Never store a plain refresh token here.';
COMMENT ON COLUMN kang.google_oauth_accounts.key_version IS
    'Application encryption key version used for token encryption.';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'trg_google_oauth_accounts_updated_at'
          AND tgrelid = 'kang.google_oauth_accounts'::regclass
    ) THEN
        CREATE TRIGGER trg_google_oauth_accounts_updated_at
        BEFORE UPDATE ON kang.google_oauth_accounts
        FOR EACH ROW
        EXECUTE PROCEDURE kang.touch_updated_at();
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS kang.google_oauth_states (
    state text NOT NULL,
    user_id uuid NOT NULL,
    provider text DEFAULT 'google'::text NOT NULL,
    code_verifier text,
    nonce text,
    redirect_uri text NOT NULL,
    return_url text,
    requested_scopes text[] DEFAULT ARRAY[]::text[] NOT NULL,
    ip_address inet,
    user_agent text,
    expires_at timestamp with time zone DEFAULT (now() + interval '10 minutes') NOT NULL,
    consumed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT google_oauth_states_pkey PRIMARY KEY (state),
    CONSTRAINT google_oauth_states_user_id_fkey FOREIGN KEY (user_id)
        REFERENCES kang.users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS ix_google_oauth_states_user_id
    ON kang.google_oauth_states USING btree (user_id);

CREATE INDEX IF NOT EXISTS ix_google_oauth_states_expires_at
    ON kang.google_oauth_states USING btree (expires_at);

COMMENT ON TABLE kang.google_oauth_states IS
    'Short-lived OAuth state and PKCE data used during the Google consent callback.';
COMMENT ON COLUMN kang.google_oauth_states.code_verifier IS
    'Short-lived PKCE verifier. Delete or consume this row immediately after callback handling.';

CREATE TABLE IF NOT EXISTS kang.google_service_sync_states (
    id uuid DEFAULT kang.ms_generate_uuid() NOT NULL,
    oauth_account_id uuid NOT NULL,
    service text NOT NULL,
    resource_id text DEFAULT 'primary'::text NOT NULL,
    sync_token text,
    page_token text,
    cursor_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_attempt_at timestamp with time zone,
    last_success_at timestamp with time zone,
    last_error_at timestamp with time zone,
    last_error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT google_service_sync_states_pkey PRIMARY KEY (id),
    CONSTRAINT google_service_sync_states_oauth_account_id_fkey FOREIGN KEY (oauth_account_id)
        REFERENCES kang.google_oauth_accounts(id) ON DELETE CASCADE,
    CONSTRAINT google_service_sync_states_service_check
        CHECK (service IN ('calendar', 'drive'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_google_service_sync_states_resource
    ON kang.google_service_sync_states USING btree (oauth_account_id, service, resource_id);

CREATE INDEX IF NOT EXISTS ix_google_service_sync_states_service
    ON kang.google_service_sync_states USING btree (service, last_success_at);

COMMENT ON TABLE kang.google_service_sync_states IS
    'Per-service sync cursors for Google Calendar and Drive integrations.';
COMMENT ON COLUMN kang.google_service_sync_states.resource_id IS
    'Calendar ID, Drive changes resource, or primary when the service has one default cursor.';
COMMENT ON COLUMN kang.google_service_sync_states.sync_token IS
    'Google incremental sync token when provided by Calendar or Drive APIs.';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'trg_google_service_sync_states_updated_at'
          AND tgrelid = 'kang.google_service_sync_states'::regclass
    ) THEN
        CREATE TRIGGER trg_google_service_sync_states_updated_at
        BEFORE UPDATE ON kang.google_service_sync_states
        FOR EACH ROW
        EXECUTE PROCEDURE kang.touch_updated_at();
    END IF;
END $$;
