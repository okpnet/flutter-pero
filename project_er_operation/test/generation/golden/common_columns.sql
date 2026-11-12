CREATE FUNCTION audit_user() RETURNS text AS $$ SELECT current_user $$ LANGUAGE sql;

CREATE TABLE mst_item (
  tenant_id integer NOT NULL,
  id integer NOT NULL,
  name text,
  created_at timestamp DEFAULT now() NOT NULL,
  created_by varchar(50) DEFAULT audit_user(),
  CONSTRAINT mst_item_pk PRIMARY KEY (id)
);

CREATE INDEX mst_item_idx1 ON mst_item (tenant_id, id);

CREATE TABLE tmp_item (
  id integer NOT NULL,
  CONSTRAINT tmp_item_pk PRIMARY KEY (id)
);
