SET search_path TO app, public;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'app') EXEC(N'CREATE SCHEMA [app]');

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'other') EXEC(N'CREATE SCHEMA [other]');

CREATE TABLE [app].[node] (
  [id] int IDENTITY(1,1) NOT NULL,
  [parent_id] int NULL,
  [name] varchar(20) NULL DEFAULT (''),
  [qty] decimal(18,2) NULL,
  [due] date NULL DEFAULT (CURRENT_DATE + 30),
  [state] varchar(max) NULL,
  CONSTRAINT [node_pk] PRIMARY KEY ([id]),
  CONSTRAINT [node_ck1] CHECK (qty >= 0),
  CONSTRAINT [node_state_ck] CHECK (state <> 'closed' OR qty = 0)
);

ALTER TABLE [app].[node] ADD CONSTRAINT [node_uq] UNIQUE ([name], [qty]);

GO

CREATE FUNCTION count_nodes() RETURNS bigint AS $$ SELECT count(*) FROM node $$ LANGUAGE sql;

GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'ノード数', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'FUNCTION', @level1name = N'count_nodes';

CREATE TABLE [other].[other] (
  [id] int IDENTITY(1,1) NOT NULL,
  [node_id] int NULL,
  CONSTRAINT [other_pk] PRIMARY KEY ([id])
);

-- [PERO] node_fk1: DEFERRABLE INITIALLY DEFERRED は SQL Server にないため出力しません

ALTER TABLE [app].[node] ADD CONSTRAINT [node_fk1] FOREIGN KEY ([parent_id]) REFERENCES [app].[node] ([id]) ON DELETE SET NULL ON UPDATE NO ACTION;

-- [PERO] other_fk1: DEFERRABLE INITIALLY IMMEDIATE は SQL Server にないため出力しません

ALTER TABLE [other].[other] ADD CONSTRAINT [other_fk1] FOREIGN KEY ([id]) REFERENCES [app].[node] ([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

GO

CREATE OR ALTER VIEW [app].[v_node] AS
SELECT id, name FROM app.node WHERE qty > 0;

GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'ノードのビュー', @level0type = N'SCHEMA', @level0name = N'app', @level1type = N'VIEW', @level1name = N'v_node';

GO

CREATE FUNCTION view_rows() RETURNS bigint AS $$ SELECT count(*) FROM app.v_node $$ LANGUAGE sql;

GO

-- [PERO] node_trg01: BEFORE は SQL Server にないため、AFTER トリガーにしました

-- [PERO] node_trg01: SQL Server のトリガーは文単位です(行単位の指定は無視)。本体で inserted / deleted を使ってください

-- [PERO] node_trg01: UPDATE OF は出力しません。本体で UPDATE(列) を使ってください

GO

CREATE OR ALTER TRIGGER [app].[node_trg01] ON [app].[node]
AFTER INSERT, UPDATE
AS
CREATE FUNCTION touch() RETURNS trigger AS $$ BEGIN RETURN NEW; END $$ LANGUAGE plpgsql;

GO
