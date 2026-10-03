-- nvim --headless -u NONE --cmd "set rtp+=." -l tests/run.lua
local failed, passed = 0, 0
local function eq(name, got, want)
  if vim.deep_equal(got, want) then
    passed = passed + 1
  else
    failed = failed + 1
    print(('FAIL %s\n  got:  %s\n  want: %s'):format(name, vim.inspect(got), vim.inspect(want)))
  end
end

local er = require('sqlcard.er')
local ddl = require('sqlcard.ddl')
local scan = require('sqlcard.scan')

eq('lowercase names stay', er.table_name('order_items'), 'order_items')
eq('USER -> users', er.table_name('USER'), 'users')
eq('OrderItem -> order_items', er.table_name('OrderItem'), 'order_items')
eq('CATEGORY -> categories', er.table_name('CATEGORY'), 'categories')
eq('BOX -> boxes', er.table_name('BOX'), 'boxes')

local schema = er.parse({
  '```mermaid',
  'erDiagram',
  '  users {',
  '    int id PK',
  '    string email UK "ログイン用"',
  '    datetime created_at',
  '  }',
  '  posts {',
  '    int id PK',
  '    int user_id FK',
  '    text body',
  '    geometry area',
  '  }',
  '  post_tags {',
  '    int post_id PK, FK',
  '    int tag_id PK, FK',
  '  }',
  '  %% コメント',
  '  users ||--o{ posts : writes',
  '  posts ||--o{ post_tags : has',
  '  tags ||--o{ post_tags : has',
  '```',
})
eq('table order', vim.tbl_map(function(t) return t.name end, schema.tables), { 'users', 'posts', 'post_tags', 'tags' })
eq('relations', schema.relations, {
  { child = 'posts', parent = 'users' },
  { child = 'post_tags', parent = 'posts' },
  { child = 'post_tags', parent = 'tags' },
})
eq('keys', { schema.by_name.users.columns[2].uk, schema.by_name.post_tags.columns[1].fk, schema.by_name.post_tags.columns[1].pk }, { true, true, true })

eq('postgres users', ddl.create_table(schema, schema.by_name.users, 'postgres', '  '), {
  'CREATE TABLE users (',
  '  id         INTEGER PRIMARY KEY,',
  '  email      TEXT UNIQUE,',
  '  created_at TIMESTAMPTZ',
  ');',
})
eq('postgres posts', ddl.create_table(schema, schema.by_name.posts, 'postgres', '  '), {
  'CREATE TABLE posts (',
  '  id      INTEGER PRIMARY KEY,',
  '  user_id INTEGER REFERENCES users (id),',
  '  body    TEXT,',
  '  area    geometry',
  ');',
})
eq('mysql posts', ddl.create_table(schema, schema.by_name.posts, 'mysql', '\t'), {
  'CREATE TABLE posts (',
  '\tid      INT PRIMARY KEY,',
  '\tuser_id INT,',
  '\tbody    TEXT,',
  '\tarea    geometry,',
  '\tFOREIGN KEY (user_id) REFERENCES users (id)',
  ');',
})
eq('sqlite composite key', ddl.create_table(schema, schema.by_name.post_tags, 'sqlite', '  '), {
  'CREATE TABLE post_tags (',
  '  post_id INTEGER REFERENCES posts (id),',
  '  tag_id  INTEGER REFERENCES tags (id),',
  '  PRIMARY KEY (post_id, tag_id)',
  ');',
})
local with_cols = vim.tbl_filter(function(t) return #t.columns > 0 end, schema.tables)
eq('parents first', vim.tbl_map(function(t) return t.name end, ddl.ordered(schema, { with_cols[3], with_cols[2], with_cols[1] })), { 'users', 'posts', 'post_tags' })

local single = er.parse({ 'erDiagram', '  USER {', '    int id PK', '  }', '  COMMENT {', '    int id PK', '    int author FK', '  }', '  USER ||--o{ COMMENT : writes' })
eq('fk by single relation', ddl.create_table(single, single.by_name.comments, 'postgres', '  ')[3], '  author INTEGER REFERENCES users (id)')
local loose = er.parse({ 'erDiagram', '  logs {', '    int id PK', '    int owner FK', '  }' })
eq('unresolved fk has no REFERENCES', ddl.create_table(loose, loose.by_name.logs, 'postgres', '  ')[3], '  owner INTEGER')

local parsed = scan.parse([[
-- CREATE TABLE ghosts (id INT);
CREATE TABLE IF NOT EXISTS public.users (
    id         UUID PRIMARY KEY,
    price      NUMERIC(10, 2) NOT NULL,
    "name"     TEXT,
    CONSTRAINT users_name UNIQUE (name),
    PRIMARY KEY (id)
);
create table `posts` (
  id int,
  user_id int references users (id)
);
ALTER TABLE users ADD COLUMN email TEXT, ADD age INT;
ALTER TABLE ONLY posts ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE posts ADD CONSTRAINT fk FOREIGN KEY (user_id) REFERENCES users (id);
]])
eq('scan', parsed, { users = { 'id', 'price', 'name', 'email', 'age' }, posts = { 'id', 'user_id', 'title' } })

print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
