local M = {}

local store = require('sqlcard.store')

M.config = {
  default_dialect = 'postgres', -- postgres | mysql | sqlite
  keyword_case = 'upper', -- upper | lower
  card = {
    width = 50,
    float = { width = 0.6, height = 0.7 },
  },
  -- .sql とカードのバッファにだけ張る。false で無効
  keys = {
    card = '<leader>Dc',
    float = '<leader>DC',
    insert = '<leader>Di',
    dialect = '<leader>Dd',
  },
}

local function notify(m, l) vim.notify('[sqlcard] ' .. m, l or vim.log.levels.INFO) end

function M.dialect(buf)
  return store.dialect(store.root(buf), M.config.default_dialect)
end

function M.set_dialect(name, buf)
  if not vim.tbl_contains(store.DIALECTS, name) then
    notify('知らない方言: ' .. name .. '（' .. table.concat(store.DIALECTS, ' / ') .. '）', vim.log.levels.ERROR)
    return
  end
  local root = store.root(buf)
  store.set_dialect(root, name)
  notify(vim.fs.basename(root) .. ' の方言を ' .. name .. ' にした')
end

function M.select_dialect()
  local buf = vim.api.nvim_get_current_buf()
  local current = M.dialect(buf)
  vim.ui.select(store.DIALECTS, {
    prompt = 'SQL の方言（今: ' .. current .. '）',
    format_item = function(item) return item == current and item .. ' ●' or item end,
  }, function(choice)
    if choice then M.set_dialect(choice, buf) end
  end)
end

function M.card(mode)
  local buf = vim.api.nvim_get_current_buf()
  local root = store.root(buf)
  local title = ('ER: %s (%s)'):format(vim.fs.basename(root), store.SHORT[M.dialect(buf)])
  local card_buf = require('sqlcard.card').toggle(root, mode == 'float' and 'float' or 'split', M.config.card, title)
  if card_buf then M.attach(card_buf) end
end

function M.insert()
  local buf = vim.api.nvim_get_current_buf()
  if vim.b[buf].sqlcard_root then
    notify('挿入先の .sql のウィンドウで実行して', vim.log.levels.WARN)
    return
  end
  local root = store.root(buf)
  local schema = require('sqlcard.names').card_schema(root)
  local tables = vim.tbl_filter(function(t) return #t.columns > 0 end, schema.tables)
  if #tables == 0 then
    notify('カードにカラムつきのテーブルが無い。:SqlCard で ER 図を書いて', vim.log.levels.WARN)
    return
  end

  local ALL = 'すべて（' .. #tables .. ' テーブル）'
  local choices = { ALL }
  for _, t in ipairs(tables) do
    table.insert(choices, t.name)
  end
  local win = vim.api.nvim_get_current_win()
  vim.ui.select(choices, { prompt = 'CREATE TABLE を挿入（' .. M.dialect(buf) .. '）' }, function(choice)
    if not choice or not vim.api.nvim_win_is_valid(win) then return end
    local picked = choice == ALL and tables or { schema.by_name[choice] }
    local indent = vim.bo[buf].expandtab and (' '):rep(vim.fn.shiftwidth()) or '\t'
    local lines = require('sqlcard.ddl').generate(schema, picked, M.dialect(buf), indent)
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local here = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    -- 空行の上ならその行を使い、そうでなければ次の行に入れる
    local at = here == '' and row - 1 or row
    vim.api.nvim_buf_set_lines(buf, at, here == '' and row or at, false, lines)
    vim.api.nvim_win_set_cursor(win, { at + 1, 0 })
  end)
end

function M.attach(buf)
  local keys = M.config.keys
  if not keys or vim.b[buf].sqlcard_attached then return end
  vim.b[buf].sqlcard_attached = true
  local function map(lhs, fn, desc)
    if lhs then vim.keymap.set('n', lhs, fn, { buffer = buf, desc = desc }) end
  end
  map(keys.card, function() M.card('split') end, 'ER カードを横に開く/閉じる')
  map(keys.float, function() M.card('float') end, 'ER カードを浮かせて開く/閉じる')
  map(keys.insert, M.insert, 'カードから CREATE TABLE を挿入')
  map(keys.dialect, M.select_dialect, 'SQL の方言を切り替え')
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})

  local cmd = vim.api.nvim_create_user_command
  cmd('SqlCard', function(a) M.card(a.args) end, {
    nargs = '?',
    complete = function() return { 'split', 'float' } end,
    desc = 'ER カードを開く/閉じる',
  })
  cmd('SqlCardInsert', M.insert, { desc = 'カードから CREATE TABLE を挿入' })
  cmd('SqlDialect', function(a)
    if a.args == '' then M.select_dialect() else M.set_dialect(a.args) end
  end, {
    nargs = '?',
    complete = function() return store.DIALECTS end,
    desc = 'SQL の方言を切り替え',
  })

  local group = vim.api.nvim_create_augroup('sqlcard', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'sql',
    callback = function(ev) M.attach(ev.buf) end,
  })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    pattern = '*.sql',
    callback = function(ev) require('sqlcard.scan').invalidate(store.root(ev.buf)) end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'sql' then M.attach(buf) end
  end
end

return M
