SET client_encoding = 'UTF8';

CREATE TABLE [b] (
  [id] int NOT NULL,
  [a_id] int NULL,
  CONSTRAINT [b_pk] PRIMARY KEY ([id])
);

-- pre a

CREATE TABLE [a] (
  [id] int NOT NULL,
  [b_id] int NULL,
  [updated] datetime2 NULL,
  CONSTRAINT [a_pk] PRIMARY KEY ([id])
);

-- post a

ALTER TABLE [a] ADD CONSTRAINT [a_fk1] FOREIGN KEY ([b_id]) REFERENCES [b] ([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE [b] ADD CONSTRAINT [b_fk1] FOREIGN KEY ([a_id]) REFERENCES [a] ([id]) ON DELETE SET NULL;

GO

CREATE OR ALTER TRIGGER [b_trg01] ON [b]
AFTER INSERT
AS
CREATE FUNCTION touch_updated() RETURNS trigger AS $$ BEGIN NEW.updated = now(); RETURN NEW; END $$ LANGUAGE plpgsql;

GO

-- [PERO] b_trg02: BEFORE は SQL Server にないため、AFTER トリガーにしました

-- [PERO] b_trg02: SQL Server のトリガーは文単位です(行単位の指定は無視)。本体で inserted / deleted を使ってください

GO

CREATE OR ALTER TRIGGER [b_trg02] ON [b]
AFTER INSERT
AS
CREATE FUNCTION b_trg02() RETURNS trigger AS $$ BEGIN RETURN NEW; END $$ LANGUAGE plpgsql;

GO

-- [PERO] a_trg01: BEFORE は SQL Server にないため、AFTER トリガーにしました

-- [PERO] a_trg01: SQL Server のトリガーは文単位です(行単位の指定は無視)。本体で inserted / deleted を使ってください

-- [PERO] a_trg01: WHEN(OLD.* IS DISTINCT FROM NEW.*) は出力しません。本体で IF を使ってください

GO

CREATE OR ALTER TRIGGER [a_trg01] ON [a]
AFTER INSERT, UPDATE
AS
CREATE FUNCTION touch_updated() RETURNS trigger AS $$ BEGIN NEW.updated = now(); RETURN NEW; END $$ LANGUAGE plpgsql;

GO

-- end of file
