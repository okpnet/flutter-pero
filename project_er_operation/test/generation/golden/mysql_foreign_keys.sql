CREATE TABLE `customers` (
  `id` INT AUTO_INCREMENT NOT NULL,
  `email` VARCHAR(255) NOT NULL,
  CONSTRAINT `customers_pk` PRIMARY KEY (`id`)
);

ALTER TABLE `customers` ADD CONSTRAINT `customers_unq1` UNIQUE (`email`);

CREATE TABLE `orders` (
  `order_no` INT NOT NULL,
  `customers_id` INT NOT NULL,
  `memo` TEXT,
  CONSTRAINT `orders_pk` PRIMARY KEY (`order_no`, `customers_id`)
);

CREATE INDEX `orders_idx1` ON `orders` (`customers_id`, `order_no`);

CREATE INDEX `orders_by_memo` ON `orders` (`memo`);

ALTER TABLE `orders` ADD CONSTRAINT `orders_fk1` FOREIGN KEY (`customers_id`) REFERENCES `customers` (`id`) ON DELETE CASCADE ON UPDATE SET NULL;
