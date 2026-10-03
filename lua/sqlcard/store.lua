-- プロジェクトごとの方言とカードの置き場所。リポジトリには何も置かず、nvim の state に持つ。
local M = {}

local uv = vim.uv or vim.loop

M.DIALECTS = { 'postgres', 'mysql', 'sqlite' }
M.SHORT = { postgres = 'pg', mysql = 'mysql', sqlite = 'sqlite' }

local function dir()
  return vim.fn.stdpath('state') .. '/sqlcard'
end

local function state_file()
  return dir() .. '/state.json'
end

local cache

local function load()
  if cache then return cache end
  local f = io.open(state_file(), 'r')
  local ok, data
  if f then
    ok, data = pcall(vim.json.decode, f:read('*a'))
    f:close()
  end
  cache = (ok and type(data) == 'table') and data or {}
  cache.dialects = cache.dialects or {}
  return cache
end

local function save()
  vim.fn.mkdir(dir(), 'p')
  local f = assert(io.open(state_file(), 'w'))
  f:write(vim.json.encode(cache))
  f:close()
end

function M.card_dir()
  return dir() .. '/cards'
end

--- バッファが属するプロジェクトのルート。カードの中では、そのカードの持ち主を返す。
function M.root(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local owner = vim.b[buf].sqlcard_root
  if owner then return owner end
  local name = vim.api.nvim_buf_get_name(buf)
  local start = name ~= '' and vim.fs.dirname(name) or uv.cwd()
  return vim.fs.root(start, '.git') or uv.cwd()
end

function M.card_path(root)
  return M.card_dir() .. '/' .. root:gsub('[/\\:]', '%%') .. '.mmd'
end

function M.dialect(root, default)
  return load().dialects[root] or default
end

function M.set_dialect(root, dialect)
  load().dialects[root] = dialect
  save()
end

return M
