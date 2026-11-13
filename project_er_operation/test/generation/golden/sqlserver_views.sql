GO

CREATE FUNCTION recent_orders(n integer) RETURNS TABLE(x integer) AS $$ SELECT 1 $$ LANGUAGE sql;

GO

CREATE TABLE [customers] (
  [id] int NOT NULL,
  [name] varchar(max) NULL,
  CONSTRAINT [customers_pk] PRIMARY KEY ([id])
);

CREATE TABLE [orders] (
  [id] int NOT NULL,
  [customer_id] int NULL,
  [total] decimal(18,2) NULL,
  CONSTRAINT [orders_pk] PRIMARY KEY ([id])
);

-- before view

GO

CREATE OR ALTER VIEW [v_orders] AS
SELECT [o].[id] AS [order_id], [c].[name] AS [customer_name]
FROM [orders] [o]
LEFT JOIN [customers] [c] ON [o].[customer_id] = [c].[id]
WHERE o.total > 0;

GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'注文一覧', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'VIEW', @level1name = N'v_orders';

-- after view

GO

CREATE OR ALTER VIEW [v_recent] AS
SELECT * FROM recent_orders(10);

GO
