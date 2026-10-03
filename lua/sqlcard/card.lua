-- プロジェクトごとの ER 図カード。実体は state 配下の .mmd ファイル。
local store = require('sqlcard.store')

local M = {}

local function ensure_file(path)
  if vim.uv.fs_stat(path) then return end
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local f = assert(io.open(path, 'w'))
  f:write('erDiagram\n')
  f:close()
end

local function card_window(buf)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then return win end
  end
end

--- @param mode 'split'|'float'
function M.toggle(root, mode, config, title)
  local path = store.card_path(root)
  ensure_file(path)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.b[buf].sqlcard_root = root
  vim.bo[buf].buflisted = false
  if vim.bo[buf].filetype == '' then vim.bo[buf].filetype = 'mermaid' end

  local open = card_window(buf)
  if open then
    vim.api.nvim_win_close(open, false)
    return
  end

  if mode == 'float' then
    local width = math.floor(vim.o.columns * config.float.width)
    local height = math.floor(vim.o.lines * config.float.height)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2 - 1),
      col = math.floor((vim.o.columns - width) / 2),
      border = 'rounded',
      title = ' ' .. title .. ' ',
      title_pos = 'center',
    })
    vim.keymap.set('n', 'q', function()
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= '' then
        vim.api.nvim_win_close(win, false)
      else
        vim.api.nvim_feedkeys('q', 'n', false)
      end
    end, { buffer = buf, desc = 'カードを閉じる（フローティング時）' })
  else
    vim.cmd('botright vertical sbuffer ' .. buf)
    vim.api.nvim_win_set_width(0, config.width)
  end
  return buf
end

return M
