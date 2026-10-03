-- 補完に出すテーブル名・カラム名を、カード・プロジェクトの .sql・今のバッファから集める。
local er = require('sqlcard.er')
local scan = require('sqlcard.scan')
local store = require('sqlcard.store')

local M = {}

local function read_lines(path)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
  local f = io.open(path, 'r')
  if not f then return {} end
  local text = f:read('*a')
  f:close()
  return vim.split(text, '\n', { plain = true })
end

function M.card_schema(root)
  return er.parse(read_lines(store.card_path(root)))
end

--- @return { name: string, source: string, columns: string[] }[]
function M.collect(root, buf)
  local order, by_name = {}, {}
  local function add(name, source, columns)
    local entry = by_name[name]
    if not entry then
      entry = { name = name, source = source, columns = {}, seen = {} }
      by_name[name] = entry
      table.insert(order, entry)
    end
    for _, col in ipairs(columns) do
      if not entry.seen[col] then
        entry.seen[col] = true
        table.insert(entry.columns, col)
      end
    end
  end

  for _, tbl in ipairs(M.card_schema(root).tables) do
    add(tbl.name, 'card', vim.tbl_map(function(c) return c.name end, tbl.columns))
  end

  local current = vim.api.nvim_buf_get_name(buf)
  local project = scan.project(root)
  local paths = vim.tbl_keys(project)
  table.sort(paths)
  for _, path in ipairs(paths) do
    if path ~= current then
      for name, columns in pairs(project[path]) do
        add(name, 'sql', columns)
      end
    end
  end
  if vim.bo[buf].filetype == 'sql' then
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    for name, columns in pairs(scan.parse(text)) do
      add(name, 'buf', columns)
    end
  end
  return order
end

return M
