-- Correct the browser base used by profile-card and invitation links.
-- The Flutter H5 client adds `#/user/:id` itself.
INSERT INTO `system_settings`
  (`key`, `value`, `type`, `remark`, `created_at`, `updated_at`, `deleted_at`)
VALUES
  ('register_base_url', 'https://h5.example.com/#', 'string',
   'H5 public URL for profile sharing and invitations', NOW(), NOW(), NULL)
ON DUPLICATE KEY UPDATE
  `value` = VALUES(`value`),
  `type` = VALUES(`type`),
  `remark` = VALUES(`remark`),
  `updated_at` = NOW(),
  `deleted_at` = NULL;

SELECT `key`, `value`, `updated_at`
FROM `system_settings`
WHERE `key` = 'register_base_url';
