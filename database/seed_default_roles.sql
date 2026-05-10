-- Default roles for general user login.

INSERT INTO kang.roles (code, name, description)
VALUES
    ('admin', 'Admin', 'Can manage users and application settings.'),
    ('member', 'Member', 'Standard application user.')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description;
