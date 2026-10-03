-- 方言ごとの語彙。common は全方言で出す。
local M = {}

M.keywords = {
  common = {
    'SELECT', 'FROM', 'WHERE', 'GROUP BY', 'ORDER BY', 'HAVING', 'LIMIT', 'OFFSET', 'DISTINCT', 'AS',
    'JOIN', 'INNER JOIN', 'LEFT JOIN', 'RIGHT JOIN', 'CROSS JOIN', 'ON', 'USING', 'UNION', 'UNION ALL',
    'INSERT INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE FROM',
    'CREATE TABLE', 'CREATE TABLE IF NOT EXISTS', 'ALTER TABLE', 'DROP TABLE', 'DROP TABLE IF EXISTS',
    'ADD COLUMN', 'DROP COLUMN', 'RENAME TO', 'RENAME COLUMN',
    'CREATE INDEX', 'CREATE UNIQUE INDEX', 'DROP INDEX',
    'PRIMARY KEY', 'FOREIGN KEY', 'REFERENCES', 'UNIQUE', 'NOT NULL', 'NULL', 'DEFAULT', 'CHECK', 'CONSTRAINT',
    'ON DELETE CASCADE', 'ON DELETE SET NULL', 'ON DELETE RESTRICT', 'ON UPDATE CASCADE',
    'AND', 'OR', 'NOT', 'IN', 'EXISTS', 'BETWEEN', 'LIKE', 'IS NULL', 'IS NOT NULL',
    'CASE', 'WHEN', 'THEN', 'ELSE', 'END', 'WITH', 'ASC', 'DESC',
    'BEGIN', 'COMMIT', 'ROLLBACK', 'TRUE', 'FALSE', 'CURRENT_TIMESTAMP',
  },
  postgres = {
    'RETURNING', 'ON CONFLICT', 'DO NOTHING', 'DO UPDATE SET', 'ILIKE', 'GENERATED ALWAYS AS IDENTITY',
    'CREATE EXTENSION IF NOT EXISTS', 'CREATE TYPE', 'AS ENUM', 'ALTER COLUMN', 'SET NOT NULL', 'DROP NOT NULL',
    'CREATE POLICY', 'ENABLE ROW LEVEL SECURITY', 'CREATE OR REPLACE FUNCTION', 'LANGUAGE plpgsql',
    'CREATE TRIGGER', 'CONCURRENTLY', 'WITH RECURSIVE', 'LATERAL',
  },
  mysql = {
    'AUTO_INCREMENT', 'ON DUPLICATE KEY UPDATE', 'ENGINE=InnoDB', 'DEFAULT CHARSET=utf8mb4', 'COLLATE utf8mb4_0900_ai_ci',
    'UNSIGNED', 'MODIFY COLUMN', 'CHANGE COLUMN', 'ON UPDATE CURRENT_TIMESTAMP', 'INSERT IGNORE INTO', 'REPLACE INTO',
    'COMMENT', 'KEY', 'AFTER', 'SHOW TABLES', 'DESCRIBE',
  },
  sqlite = {
    'AUTOINCREMENT', 'INSERT OR IGNORE INTO', 'INSERT OR REPLACE INTO', 'ON CONFLICT', 'DO NOTHING', 'DO UPDATE SET',
    'RETURNING', 'WITHOUT ROWID', 'STRICT', 'PRAGMA foreign_keys = ON', 'PRAGMA', 'WITH RECURSIVE',
  },
}

M.types = {
  postgres = {
    'INTEGER', 'BIGINT', 'SMALLINT', 'SERIAL', 'BIGSERIAL', 'TEXT', 'VARCHAR', 'BOOLEAN', 'NUMERIC', 'REAL',
    'DOUBLE PRECISION', 'DATE', 'TIME', 'TIMESTAMP', 'TIMESTAMPTZ', 'INTERVAL', 'UUID', 'JSON', 'JSONB', 'BYTEA', 'TEXT[]',
  },
  mysql = {
    'INT', 'BIGINT', 'SMALLINT', 'TINYINT', 'TINYINT(1)', 'VARCHAR(255)', 'CHAR', 'TEXT', 'LONGTEXT', 'BOOLEAN', 'DECIMAL',
    'FLOAT', 'DOUBLE', 'DATE', 'TIME', 'DATETIME', 'TIMESTAMP', 'JSON', 'BLOB', 'ENUM', 'BINARY(16)',
  },
  sqlite = { 'INTEGER', 'TEXT', 'REAL', 'BLOB', 'NUMERIC' },
}

M.functions = {
  common = {
    'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'COALESCE', 'NULLIF', 'CAST', 'LOWER', 'UPPER', 'TRIM', 'LENGTH', 'REPLACE',
    'ROUND', 'ABS', 'ROW_NUMBER', 'RANK',
  },
  postgres = {
    'now', 'gen_random_uuid', 'date_trunc', 'extract', 'to_char', 'string_agg', 'array_agg', 'jsonb_build_object',
    'jsonb_agg', 'unnest', 'generate_series', 'concat', 'greatest', 'least',
  },
  mysql = {
    'NOW', 'UUID', 'DATE_FORMAT', 'DATE_ADD', 'DATE_SUB', 'DATEDIFF', 'GROUP_CONCAT', 'CONCAT', 'IFNULL', 'IF',
    'JSON_EXTRACT', 'JSON_OBJECT', 'LAST_INSERT_ID', 'UNIX_TIMESTAMP',
  },
  sqlite = {
    'datetime', 'date', 'strftime', 'unixepoch', 'julianday', 'group_concat', 'ifnull', 'iif', 'json_extract',
    'json_object', 'last_insert_rowid', 'random', 'printf',
  },
}

local UPSERT = {
  postgres = 'INSERT INTO ${1:table} (${2:columns})\nVALUES (${3})\nON CONFLICT (${4:key}) DO UPDATE SET ${5:column} = EXCLUDED.${5:column};',
  mysql = 'INSERT INTO ${1:table} (${2:columns})\nVALUES (${3})\nON DUPLICATE KEY UPDATE ${4:column} = VALUES(${4:column});',
  sqlite = 'INSERT INTO ${1:table} (${2:columns})\nVALUES (${3})\nON CONFLICT (${4:key}) DO UPDATE SET ${5:column} = excluded.${5:column};',
}

local ID_COLUMN = {
  postgres = 'id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY',
  mysql = 'id BIGINT AUTO_INCREMENT PRIMARY KEY',
  sqlite = 'id INTEGER PRIMARY KEY AUTOINCREMENT',
}

local CREATED_AT = {
  postgres = 'created_at TIMESTAMPTZ NOT NULL DEFAULT now()',
  mysql = 'created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP',
  sqlite = "created_at TEXT NOT NULL DEFAULT (datetime('now'))",
}

--- 骨組み。{ 絞り込みに使う語, 説明, 本体 }
function M.snippets(dialect)
  return {
    { 'create table', 'テーブル作成', 'CREATE TABLE ${1:name} (\n\t' .. ID_COLUMN[dialect] .. ',\n\t${2}\n);' },
    { 'alter table add column', 'カラム追加', 'ALTER TABLE ${1:table} ADD COLUMN ${2:column} ${3:type};' },
    { 'create index', 'インデックス作成', 'CREATE INDEX ${1:idx_name} ON ${2:table} (${3:column});' },
    { 'foreign key', '外部キー制約', 'FOREIGN KEY (${1:column}) REFERENCES ${2:table} (${3:id}) ON DELETE ${4:CASCADE}' },
    { 'references', '参照（カラム定義内）', 'REFERENCES ${1:table} (${2:id}) ON DELETE ${3:CASCADE}' },
    { 'id column', '主キーの連番カラム', ID_COLUMN[dialect] },
    { 'created_at column', '作成日時カラム', CREATED_AT[dialect] },
    { 'insert into', '行の追加', 'INSERT INTO ${1:table} (${2:columns})\nVALUES (${3});' },
    { 'upsert', 'あれば更新、なければ追加', UPSERT[dialect] },
    { 'select from', '行の取得', 'SELECT ${1:*}\nFROM ${2:table}\nWHERE ${3};' },
    { 'update set', '行の更新', 'UPDATE ${1:table}\nSET ${2:column} = ${3:value}\nWHERE ${4};' },
    { 'delete from', '行の削除', 'DELETE FROM ${1:table}\nWHERE ${2};' },
  }
end

return M
