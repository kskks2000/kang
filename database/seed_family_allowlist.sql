-- Add family members before they sign up.
-- Replace the sample values before running.

INSERT INTO metaserver.family_login_allowlist (
    email,
    display_name,
    relationship,
    role_code,
    status,
    note
)
VALUES
    ('family@example.com', 'Family Member', 'family', 'family_member', 'invited', 'Initial family login invite')
ON CONFLICT DO NOTHING;
