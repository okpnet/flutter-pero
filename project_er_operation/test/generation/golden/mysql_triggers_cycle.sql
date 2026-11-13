SET client_encoding = 'UTF8';

CREATE TABLE `b` (
  `id` INT NOT NULL,
  `a_id` INT,
  CONSTRAINT `b_pk` PRIMARY KEY (`id`)
);

-- pre a

CREATE TABLE `a` (
  `id` INT NOT NULL,
  `b_id` INT,
  `updated` DATETIME,
  CONSTRAINT `a_pk` PRIMARY KEY (`id`)
);

-- post a

ALTER TABLE `a` ADD CONSTRAINT `a_fk1` FOREIGN KEY (`b_id`) REFERENCES `b` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE `b` ADD CONSTRAINT `b_fk1` FOREIGN KEY (`a_id`) REFERENCES `a` (`id`) ON DELETE SET NULL;

-- [PERO] b_trg01: STATEMENT単位のトリガーは MySQL にないため出力しません

CREATE TRIGGER `b_trg02` BEFORE INSERT ON `b` FOR EACH ROW
CREATE FUNCTION b_trg02() RETURNS trigger AS $$ BEGIN RETURN NEW; END $$ LANGUAGE plpgsql;

-- [PERO] a_trg01: WHEN(OLD.* IS DISTINCT FROM NEW.*) は MySQL にないため出力しません。本体で IF を使ってください

CREATE TRIGGER `a_trg01_insert` BEFORE INSERT ON `a` FOR EACH ROW
CREATE FUNCTION touch_updated() RETURNS trigger AS $$ BEGIN NEW.updated = now(); RETURN NEW; END $$ LANGUAGE plpgsql;

CREATE TRIGGER `a_trg01_update` BEFORE UPDATE ON `a` FOR EACH ROW
CREATE FUNCTION touch_updated() RETURNS trigger AS $$ BEGIN NEW.updated = now(); RETURN NEW; END $$ LANGUAGE plpgsql;

-- end of file
