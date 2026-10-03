-- blink.cmp のソース。方言の語彙と、集めたテーブル名・カラム名を出す。
local dialects = require('sqlcard.dialects')
local names = require('sqlcard.names')
local store = require('sqlcard.store')

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:enabled()
  return vim.bo.filetype == 'sql'
end

function source:get_trigger_characters()
  return { '.' }
end

local function in_text(before)
  if before:find('%-%-') then return true end
  local _, quotes = before:gsub("'", '')
  return quotes % 2 == 1
end

--- @return table[] blink に渡す前の素の候補（テストしやすいように blink へ依存しない）
function source.candidates(buf, before)
  if in_text(before) then return {} end
  local sqlcard = require('sqlcard')
  local root = store.root(buf)
  local dialect = sqlcard.dialect(buf)
  local tag = store.SHORT[dialect]
  local tables = names.collect(root, buf)
  local items = {}

  local qualifier = before:match('([%w_]+)%.[%w_]*$')
  if qualifier then
    for _, tbl in ipairs(tables) do
      if tbl.name == qualifier then
        for _, col in ipairs(tbl.columns) do
          table.insert(items, { label = col, kind = 'Field', description = tbl.name .. ' · ' .. tbl.source })
        end
      end
    end
    return items
  end

  local lower = sqlcard.config.keyword_case == 'lower'
  local function cased(word)
    return lower and word:lower() or word
  end
  for _, group in ipairs({ 'common', dialect }) do
    for _, kw in ipairs(dialects.keywords[group]) do
      table.insert(items, { label = cased(kw), kind = 'Keyword', description = group == dialect and tag or nil })
    end
    for _, fn in ipairs(dialects.functions[group]) do
      table.insert(items, { label = fn, kind = 'Function', description = group == dialect and tag or nil, snippet = fn .. '(${1})' })
    end
  end
  for _, type_ in ipairs(dialects.types[dialect]) do
    table.insert(items, { label = cased(type_), kind = 'TypeParameter', description = tag })
  end
  for _, snip in ipairs(dialects.snippets(dialect)) do
    table.insert(items, { label = snip[1], kind = 'Snippet', description = snip[2] .. ' · ' .. tag, snippet = snip[3] })
  end

  local seen = {}
  for _, tbl in ipairs(tables) do
    table.insert(items, { label = tbl.name, kind = 'Class', description = tbl.source })
    for _, col in ipairs(tbl.columns) do
      if not seen[col] then
        seen[col] = true
        table.insert(items, { label = col, kind = 'Field', description = tbl.name .. ' · ' .. tbl.source })
      end
    end
  end
  return items
end

function source:get_completions(ctx, callback)
  local Kind = require('blink.cmp.types').CompletionItemKind
  local Format = vim.lsp.protocol.InsertTextFormat
  local row, col = ctx.cursor[1], ctx.cursor[2]
  local before = ctx.line:sub(1, col)
  local start = before:find('[%w_]*$')
  local range = {
    start = { line = row - 1, character = start - 1 },
    ['end'] = { line = row - 1, character = col },
  }

  local items = {}
  for _, c in ipairs(source.candidates(ctx.bufnr or vim.api.nvim_get_current_buf(), before)) do
    table.insert(items, {
      label = c.label,
      labelDetails = c.description and { description = c.description } or nil,
      filterText = c.label,
      kind = Kind[c.kind],
      insertTextFormat = c.snippet and Format.Snippet or Format.PlainText,
      textEdit = { newText = c.snippet or c.label, range = range },
    })
  end
  callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

return source
