CREATE FUNCTION recent_orders(n integer) RETURNS TABLE(x integer) AS $$ SELECT 1 $$ LANGUAGE sql;

CREATE TABLE customers (
  id integer NOT NULL,
  name text,
  CONSTRAINT customers_pk PRIMARY KEY (id)
);

CREATE TABLE orders (
  id integer NOT NULL,
  customer_id integer,
  total numeric(18,2),
  CONSTRAINT orders_pk PRIMARY KEY (id)
);

-- before view

CREATE VIEW v_orders AS
SELECT o.id AS order_id, c.name AS customer_name
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.id
WHERE o.total > 0;

COMMENT ON VIEW v_orders IS '注文一覧';

-- after view

CREATE VIEW v_recent AS
SELECT * FROM recent_orders(10);
