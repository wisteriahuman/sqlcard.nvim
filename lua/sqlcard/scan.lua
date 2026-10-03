-- プロジェクト内の .sql から、定義済みのテーブル名とカラム名を集める。
-- 読むのは CREATE TABLE と ADD COLUMN だけ。DROP や RENAME は追わない。
local M = {}

local SKIP_DIRS = { ['.git'] = true, node_modules = true, vendor = true, dist = true, build = true, target = true, ['.venv'] = true }
local NOT_COLUMN = { primary = true, foreign = true, unique = true, constraint = true, check = true, key = true, index = true, exclude = true, like = true }
local MAX_FILES, MAX_BYTES, MAX_DEPTH = 500, 512 * 1024, 8

local function ident(raw)
  local name = raw:gsub('[`"%[%]]', ''):match('([^%.]+)$')
  return name
end

local IDENT = '[%w_%.`"]+'

--- @return table<string, string[]> テーブル名 → カラム名
function M.parse(text)
  local tables = {}
  text = text:gsub('%-%-[^\n]*', '')
  local lower = text:lower()
  local function columns(name)
    tables[name] = tables[name] or {}
    return tables[name]
  end

  local pos = 1
  while true do
    local s, e = lower:find('create%s+table%s+', pos)
    if not s then break end
    local _, e2 = lower:find('^if%s+not%s+exists%s+', e + 1)
    local ns, ne = lower:find('^' .. IDENT, (e2 or e) + 1)
    if not ns then
      pos = e + 1
    else
      local cols = columns(ident(text:sub(ns, ne)))
      local open, close = lower:find('%b()', ne + 1)
      if open and lower:sub(ne + 1, open - 1):match('^%s*$') then
        -- 型の中のカンマ（NUMERIC(10, 2)）で切らない
        local body = text:sub(open + 1, close - 1):gsub('%b()', '')
        for def in (body .. ','):gmatch('(.-),') do
          local first = def:match('^%s*(' .. IDENT .. ')')
          if first and not NOT_COLUMN[first:lower()] then table.insert(cols, ident(first)) end
        end
        pos = close + 1
      else
        pos = ne + 1
      end
    end
  end

  pos = 1
  while true do
    local s, e = lower:find('alter%s+table%s+', pos)
    if not s then break end
    local stop = lower:find(';', e, true) or #lower
    local stmt_lower, stmt = lower:sub(e + 1, stop), text:sub(e + 1, stop)
    local head = stmt_lower:match('^if%s+exists%s+') or ''
    head = head .. (stmt_lower:sub(#head + 1):match('^only%s+') or '')
    local ns, ne = stmt_lower:find('^' .. IDENT, #head + 1)
    if ns then
      local cols = columns(ident(stmt:sub(ns, ne)))
      local at = ne + 1
      while true do
        local _, ae = stmt_lower:find('add%s+', at)
        if not ae then break end
        local rest = ae + 1
        local _, ce = stmt_lower:find('^column%s+', rest)
        rest = (ce or ae) + 1
        local _, ie = stmt_lower:find('^if%s+not%s+exists%s+', rest)
        rest = (ie or rest - 1) + 1
        local cs, cend = stmt_lower:find('^' .. IDENT, rest)
        if cs and not NOT_COLUMN[stmt_lower:sub(cs, cend)] then table.insert(cols, ident(stmt:sub(cs, cend))) end
        at = (cend or ae) + 1
      end
    end
    pos = stop + 1
  end
  return tables
end

local function files(root)
  local out = {}
  for name, type_ in vim.fs.dir(root, { depth = MAX_DEPTH, skip = function(dir) return not SKIP_DIRS[vim.fs.basename(dir)] end }) do
    if type_ == 'file' and name:match('%.sql$') then
      table.insert(out, root .. '/' .. name)
      if #out >= MAX_FILES then break end
    end
  end
  return out
end

local cache = {}

function M.invalidate(root)
  cache[root] = nil
end

--- @return table<string, table<string, string[]>> ファイルパス → テーブル
function M.project(root)
  if cache[root] then return cache[root] end
  local result = {}
  for _, path in ipairs(files(root)) do
    local f = io.open(path, 'r')
    if f then
      result[path] = M.parse(f:read(MAX_BYTES) or '')
      f:close()
    end
  end
  cache[root] = result
  return result
end

return M
