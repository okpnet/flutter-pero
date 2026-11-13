CREATE FUNCTION recent_orders(n integer) RETURNS TABLE(x integer) AS $$ SELECT 1 $$ LANGUAGE sql;

CREATE TABLE `customers` (
  `id` INT NOT NULL,
  `name` TEXT,
  CONSTRAINT `customers_pk` PRIMARY KEY (`id`)
);

CREATE TABLE `orders` (
  `id` INT NOT NULL,
  `customer_id` INT,
  `total` DECIMAL(18,2),
  CONSTRAINT `orders_pk` PRIMARY KEY (`id`)
);

-- before view

CREATE OR REPLACE VIEW `v_orders` AS
SELECT `o`.`id` AS `order_id`, `c`.`name` AS `customer_name`
FROM `orders` `o`
LEFT JOIN `customers` `c` ON `o`.`customer_id` = `c`.`id`
WHERE o.total > 0;

-- after view

CREATE OR REPLACE VIEW `v_recent` AS
SELECT recent_orders(10) AS `x`;
