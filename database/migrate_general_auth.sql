-- Migration from invite/allowlist auth to general user sign-up.

DROP TABLE IF EXISTS kang.family_login_allowlist CASCADE;

INSERT INTO kang.roles (code, name, description)
VALUES
    ('admin', 'Admin', 'Can manage users and application settings.'),
    ('member', 'Member', 'Standard application user.')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description;

DELETE FROM kang.roles
WHERE code IN ('family_admin', 'family_member');
