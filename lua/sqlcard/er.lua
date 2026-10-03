-- mermaid の erDiagram を読んで、テーブル・カラム・リレーションを取り出す。
local M = {}

local NAME = '[%w_%-]+'

local function pluralize(s)
  if s:match('s$') then return s end
  if s:match('[^aeiou]y$') then return s:sub(1, -2) .. 'ies' end
  if s:match('x$') or s:match('ch$') or s:match('sh$') then return s .. 'es' end
  return s .. 's'
end
M.pluralize = pluralize

--- `USER` や `OrderItem` のような単数形の書き方だけ、複数形のスネークケースに直す。
function M.table_name(entity)
  if not entity:match('%u') then return entity end
  local snake = entity:gsub('(%l)(%u)', '%1_%2'):gsub('%-', '_'):lower()
  return pluralize(snake)
end

local function parse_attribute(line)
  local body = line:gsub('"[^"]*"', '')
  local type_, name, rest = body:match('^%s*(%S+)%s+(%S+)%s*(.-)%s*$')
  if not type_ then return nil end
  local keys = {}
  for key in rest:gmatch('%a+') do
    keys[key:upper()] = true
  end
  return { name = name, type = type_, pk = keys.PK, fk = keys.FK, uk = keys.UK }
end

---@return { tables: table[], by_name: table<string, table>, relations: table[] }
function M.parse(lines)
  local tables, by_name, relations = {}, {}, {}
  local function ensure(entity)
    local name = M.table_name(entity)
    if not by_name[name] then
      by_name[name] = { name = name, columns = {} }
      table.insert(tables, by_name[name])
    end
    return by_name[name]
  end

  local current
  for _, line in ipairs(lines) do
    local text = line:gsub('%%%%.*$', '')
    if current then
      if text:match('^%s*}') then
        current = nil
      else
        local col = parse_attribute(text)
        if col then table.insert(current.columns, col) end
      end
    else
      local entity = text:match('^%s*(' .. NAME .. ')%s*{%s*$') or text:match('^%s*(' .. NAME .. ')%s*%[.-%]%s*{%s*$')
      local a, left, right, b = text:match('^%s*(' .. NAME .. ')%s*([|}][|o])[%-%.][%-%.]([|o][|{])%s*(' .. NAME .. ')')
      if entity then
        current = ensure(entity)
      elseif a then
        local ta, tb = ensure(a), ensure(b)
        local many_a, many_b = left:sub(1, 1) == '}', right:sub(2, 2) == '{'
        -- 外部キーを持つのは「多」の側
        if many_b and not many_a then
          table.insert(relations, { child = tb.name, parent = ta.name })
        elseif many_a and not many_b then
          table.insert(relations, { child = ta.name, parent = tb.name })
        end
      end
    end
  end
  return { tables = tables, by_name = by_name, relations = relations }
end

return M
