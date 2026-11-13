CREATE TABLE `users` (
  `id` INT AUTO_INCREMENT NOT NULL,
  `name` VARCHAR(100) NOT NULL COMMENT 'O''Brien''s name',
  `status` VARCHAR(10) DEFAULT 'it''s',
  `score` DECIMAL(18,2) DEFAULT 0,
  `active` TINYINT(1) DEFAULT 1,
  `order` INT,
  CONSTRAINT `users_pk` PRIMARY KEY (`id`)
) COMMENT='ユーザー表';
