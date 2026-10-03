-- ER 図のテーブルから、方言ごとの CREATE TABLE を組み立てる。
local er = require('sqlcard.er')

local M = {}

--                      postgres            mysql           sqlite
local TYPES = {
  int       = { 'INTEGER',          'INT',          'INTEGER' },
  integer   = { 'INTEGER',          'INT',          'INTEGER' },
  bigint    = { 'BIGINT',           'BIGINT',       'INTEGER' },
  smallint  = { 'SMALLINT',         'SMALLINT',     'INTEGER' },
  string    = { 'TEXT',             'VARCHAR(255)', 'TEXT' },
  varchar   = { 'TEXT',             'VARCHAR(255)', 'TEXT' },
  text      = { 'TEXT',             'TEXT',         'TEXT' },
  bool      = { 'BOOLEAN',          'BOOLEAN',      'INTEGER' },
  boolean   = { 'BOOLEAN',          'BOOLEAN',      'INTEGER' },
  float     = { 'DOUBLE PRECISION', 'DOUBLE',       'REAL' },
  double    = { 'DOUBLE PRECISION', 'DOUBLE',       'REAL' },
  decimal   = { 'NUMERIC',          'DECIMAL',      'NUMERIC' },
  numeric   = { 'NUMERIC',          'DECIMAL',      'NUMERIC' },
  date      = { 'DATE',             'DATE',         'TEXT' },
  time      = { 'TIME',             'TIME',         'TEXT' },
  datetime  = { 'TIMESTAMPTZ',      'DATETIME',     'TEXT' },
  timestamp = { 'TIMESTAMPTZ',      'DATETIME',     'TEXT' },
  uuid      = { 'UUID',             'CHAR(36)',     'TEXT' },
  json      = { 'JSONB',            'JSON',         'TEXT' },
  jsonb     = { 'JSONB',            'JSON',         'TEXT' },
  blob      = { 'BYTEA',            'BLOB',         'BLOB' },
  bytes     = { 'BYTEA',            'BLOB',         'BLOB' },
}
local INDEX = { postgres = 1, mysql = 2, sqlite = 3 }

function M.sql_type(er_type, dialect)
  local known = TYPES[er_type:lower()]
  return known and known[INDEX[dialect]] or er_type
end

local function primary_key(tbl)
  for _, col in ipairs(tbl.columns) do
    if col.pk then return col.name end
  end
  return 'id'
end

--- 外部キーの参照先。`user_id` という命名か、リレーションが 1 本だけのときに決まる。
function M.reference(schema, tbl, col)
  local stem = col.name:match('^(.+)_id$')
  if stem then
    local target = schema.by_name[er.pluralize(stem)] or schema.by_name[stem]
    if target then return target end
  end
  local fks, parents = 0, {}
  for _, c in ipairs(tbl.columns) do
    if c.fk then fks = fks + 1 end
  end
  for _, rel in ipairs(schema.relations) do
    if rel.child == tbl.name then table.insert(parents, rel.parent) end
  end
  if fks == 1 and #parents == 1 then return schema.by_name[parents[1]] end
  return nil
end

function M.create_table(schema, tbl, dialect, indent)
  local pks = vim.tbl_filter(function(c) return c.pk end, tbl.columns)
  local width = 0
  for _, col in ipairs(tbl.columns) do
    width = math.max(width, #col.name)
  end

  local defs, constraints = {}, {}
  for _, col in ipairs(tbl.columns) do
    local parts = { M.sql_type(col.type, dialect) }
    if col.pk and #pks == 1 then table.insert(parts, 'PRIMARY KEY') end
    if col.uk then table.insert(parts, 'UNIQUE') end
    local target = col.fk and M.reference(schema, tbl, col)
    if target then
      local ref = ('REFERENCES %s (%s)'):format(target.name, primary_key(target))
      -- MySQL はカラム定義に書いた REFERENCES を黙って無視する
      if dialect == 'mysql' then
        table.insert(constraints, ('FOREIGN KEY (%s) %s'):format(col.name, ref))
      else
        table.insert(parts, ref)
      end
    end
    table.insert(defs, col.name .. (' '):rep(width - #col.name + 1) .. table.concat(parts, ' '))
  end
  if #pks > 1 then
    local names = vim.tbl_map(function(c) return c.name end, pks)
    table.insert(defs, ('PRIMARY KEY (%s)'):format(table.concat(names, ', ')))
  end
  vim.list_extend(defs, constraints)

  local lines = { ('CREATE TABLE %s ('):format(tbl.name) }
  for i, def in ipairs(defs) do
    table.insert(lines, indent .. def .. (i < #defs and ',' or ''))
  end
  table.insert(lines, ');')
  return lines
end

--- 参照される側が先に来るように並べる。
function M.ordered(schema, tables)
  local wanted, seen, out = {}, {}, {}
  for _, t in ipairs(tables) do
    wanted[t.name] = true
  end
  local function visit(tbl)
    if seen[tbl.name] then return end
    seen[tbl.name] = true
    for _, col in ipairs(tbl.columns) do
      local target = col.fk and M.reference(schema, tbl, col)
      if target and wanted[target.name] then visit(target) end
    end
    table.insert(out, tbl)
  end
  for _, t in ipairs(tables) do
    visit(t)
  end
  return out
end

function M.generate(schema, tables, dialect, indent)
  local lines = {}
  for i, tbl in ipairs(M.ordered(schema, tables)) do
    if i > 1 then table.insert(lines, '') end
    vim.list_extend(lines, M.create_table(schema, tbl, dialect, indent))
  end
  return lines
end

return M
