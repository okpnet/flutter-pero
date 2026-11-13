CREATE TABLE [users] (
  [id] int IDENTITY(1,1) NOT NULL,
  [name] varchar(100) NOT NULL,
  [status] varchar(10) NULL DEFAULT N'it''s',
  [score] decimal(18,2) NULL DEFAULT 0,
  [active] bit NULL DEFAULT 1,
  [order] int NULL,
  CONSTRAINT [users_pk] PRIMARY KEY ([id])
);

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'ユーザー表', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'users';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'O''Brien''s name', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'users', @level2type = N'COLUMN', @level2name = N'name';
