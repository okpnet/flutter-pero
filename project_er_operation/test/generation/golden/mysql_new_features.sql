SET search_path TO app, public;

CREATE DATABASE IF NOT EXISTS `app` DEFAULT CHARACTER SET utf8mb4;

CREATE DATABASE IF NOT EXISTS `other` DEFAULT CHARACTER SET utf8mb4;

CREATE TABLE `app`.`node` (
  `id` INT AUTO_INCREMENT NOT NULL,
  `parent_id` INT,
  `name` VARCHAR(20) DEFAULT (''),
  `qty` DECIMAL(18,2),
  `due` DATE DEFAULT (CURRENT_DATE + 30),
  `state` TEXT,
  CONSTRAINT `node_pk` PRIMARY KEY (`id`),
  CONSTRAINT `node_ck1` CHECK (qty >= 0),
  CONSTRAINT `node_state_ck` CHECK (state <> 'closed' OR qty = 0)
);

-- [PERO] node_uq: NULLS NOT DISTINCT は MySQL にないため、通常のUNIQUEにしました

ALTER TABLE `app`.`node` ADD CONSTRAINT `node_uq` UNIQUE (`name`, `qty`);

CREATE FUNCTION count_nodes() RETURNS bigint AS $$ SELECT count(*) FROM node $$ LANGUAGE sql;

CREATE TABLE `other`.`other` (
  `id` INT AUTO_INCREMENT NOT NULL,
  `node_id` INT,
  CONSTRAINT `other_pk` PRIMARY KEY (`id`)
);

-- [PERO] node_fk1: DEFERRABLE INITIALLY DEFERRED は MySQL にないため出力しません

ALTER TABLE `app`.`node` ADD CONSTRAINT `node_fk1` FOREIGN KEY (`parent_id`) REFERENCES `app`.`node` (`id`) ON DELETE SET NULL ON UPDATE NO ACTION;

-- [PERO] other_fk1: DEFERRABLE INITIALLY IMMEDIATE は MySQL にないため出力しません

ALTER TABLE `other`.`other` ADD CONSTRAINT `other_fk1` FOREIGN KEY (`id`) REFERENCES `app`.`node` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION;

CREATE OR REPLACE VIEW `app`.`v_node` AS
SELECT id, name FROM app.node WHERE qty > 0;

CREATE FUNCTION view_rows() RETURNS bigint AS $$ SELECT count(*) FROM app.v_node $$ LANGUAGE sql;

-- [PERO] node_trg01: UPDATE OF は MySQL にないため、UPDATEの全列が対象になります

CREATE TRIGGER `app`.`node_trg01_insert` BEFORE INSERT ON `app`.`node` FOR EACH ROW
CREATE FUNCTION touch() RETURNS trigger AS $$ BEGIN RETURN NEW; END $$ LANGUAGE plpgsql;

CREATE TRIGGER `app`.`node_trg01_update` BEFORE UPDATE ON `app`.`node` FOR EACH ROW
CREATE FUNCTION touch() RETURNS trigger AS $$ BEGIN RETURN NEW; END $$ LANGUAGE plpgsql;
