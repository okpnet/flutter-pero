GO

CREATE FUNCTION audit_user() RETURNS text AS $$ SELECT current_user $$ LANGUAGE sql;

GO

CREATE TABLE [mst_item] (
  [tenant_id] int NOT NULL,
  [id] int NOT NULL,
  [name] varchar(max) NULL,
  [created_at] datetime2 NOT NULL DEFAULT (now()),
  [created_by] varchar(50) NULL DEFAULT (audit_user()),
  CONSTRAINT [mst_item_pk] PRIMARY KEY ([id])
);

CREATE INDEX [mst_item_idx1] ON [mst_item] ([tenant_id], [id]);

CREATE TABLE [tmp_item] (
  [id] int NOT NULL,
  CONSTRAINT [tmp_item_pk] PRIMARY KEY ([id])
);
