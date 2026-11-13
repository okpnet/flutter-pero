CREATE FUNCTION audit_user() RETURNS text AS $$ SELECT current_user $$ LANGUAGE sql;

CREATE TABLE `mst_item` (
  `tenant_id` INT NOT NULL,
  `id` INT NOT NULL,
  `name` TEXT,
  `created_at` DATETIME NOT NULL DEFAULT (now()),
  `created_by` VARCHAR(50) DEFAULT (audit_user()),
  CONSTRAINT `mst_item_pk` PRIMARY KEY (`id`)
);

CREATE INDEX `mst_item_idx1` ON `mst_item` (`tenant_id`, `id`);

CREATE TABLE `tmp_item` (
  `id` INT NOT NULL,
  CONSTRAINT `tmp_item_pk` PRIMARY KEY (`id`)
);
