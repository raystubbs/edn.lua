-- Copyright 2024 Ray Stubbs
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the “Software”), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local function char_reader_from_string (s)
  local i = 1
  return {
    current = function ()
      if i <= string.len(s) then
        return string.sub(s, i, i)
      else
        return nil
      end
    end,
    advance = function ()
      if i <= string.len(s) then
        i = i + 1
      end
    end,
    peek = function (n)
      local j = i + n
      if j <= string.len(s) and j >= 1 then
        return string.sub(s, j, j)
      else
        return nil
      end
    end,
    pos = function ()
      return i
    end
  }
end

local function char_reader_from_file (f)
  return char_reader_from_string(f:read('a'))
end

local function take_symbol (cr)
  local chars = {}
  local current = cr.current()
  while current ~= nil and string.match(current, "[A-Za-z0-9.*+!_?$%&=<>/-]") do
    table.insert(chars, current)
    cr.advance()
    current = cr.current()
  end
  return table.concat(chars)
end

local function read_token(cr)
  local c = cr.current()
  local n = cr.peek(1)
  local from = cr.pos()
  if c == nil then
    return nil
  elseif c == ";" then
    -- Skip comment until newline
    while c ~= nil and c ~= "\n" do
      cr.advance()
      c = cr.current()
    end
    return read_token(cr)
  elseif c == "(" or c == ")" or c == "[" or c == "]" or c == "{" or c == "}" then
    cr.advance()
    return {c, nil, from, cr.pos()}
  elseif c == "#" and cr.peek(1) == "{" then
    cr.advance()
    cr.advance()
    return {"#{", nil, from, cr.pos()}
  elseif c == "#" and cr.peek(1) == "_" then
    cr.advance()
    cr.advance()
    return {"#_", nil, from, cr.pos()}
  elseif c == "#" and string.match(cr.peek(1), "%a") then
    cr.advance()
    local tag_name = take_symbol(cr)
    return {"tag", tag_name, from, cr.pos()}
  elseif c == ":" then
    cr.advance();
    local kw = take_symbol(cr)
    return {"keyword", kw, from, cr.pos()}
  elseif (c == "-" and n ~= nil and string.match(n, "%d")) or string.match(c, "%d") then
    local num = take_symbol(cr)
    return {"num", tonumber(num), from, cr.pos()}
  elseif string.match(c, "%s") or c == "," then
    while c ~= nil and (string.match(c, "%s") or c == ",") do
      cr.advance()
      c = cr.current()
    end
    return read_token(cr)
  elseif c == '"' then
    cr.advance()
    local chars = {}
    local current = cr.current()
    while current ~= '"' do
      if current == '\\' then
        cr.advance()
        local escaped = cr.current()
        if escaped == "t" then
          table.insert(chars, "\t")
          cr.advance()
        elseif escaped == "r" then
          table.insert(chars, "\r")
          cr.advance()
        elseif escaped == "n" then
          table.insert(chars, "\n")
          cr.advance()
        elseif escaped == "\\" then
          table.insert(chars, "\\")
          cr.advance()
        elseif escaped == '"' then
          table.insert(chars, '"')
          cr.advance()
        elseif escaped == 'u' then
          error("Unicode escape sequences not yet supported @ " .. (cr.pos() - 1))
        else
          error("Invalid escape sequence @ " .. (cr.pos() - 1))
        end
      elseif current == nil then
        error("Unterminated string @ " .. cr.pos())
      else
        table.insert(chars, current)
        cr.advance()
      end
      current = cr.current()
    end
    cr.advance()
    return {"string", table.concat(chars), from, cr.pos()}
  elseif c == "\\" then
    local pos = cr.pos()
    cr.advance()
    local charname = take_symbol(cr)
    if string.len(charname) == 0 then
      error("Invalid character literal @ " .. pos)
    elseif string.len(charname) == 1 then
      return {"char", charname, from, cr.pos()}
    elseif charname == "newline" then
      return {"char", "\n", from, cr.pos()}
    elseif charname == "return" then
      return {"char", "\r", from, cr.pos()}
    elseif charname == "space" then
      return {"char", " ", from, cr.pos()}
    elseif charname == "tab" then
      return {"char", "\t", from, cr.pos()}
    else
      error("Invalid character name '" .. charname .. "' @ " .. pos)
    end
  else
    local sym = take_symbol(cr)
    if string.len(sym) == 0 then
      error(string.format("Unexpected character '%s' @ %s", cr.current(), cr.pos()))
    end
    return {"symbol", sym, from, cr.pos()}
  end
end

local function token_reader_from_char_reader (cr)
  local current = read_token(cr)
  return {
    current = function ()
      return current
    end,
    advance = function ()
      current = read_token(cr)
    end
  }
end

local parse_list_tail, parse_map_tail, parse_vector_tail,
      parse_set_tail, parse_seq_tail

local function identity(x)
  return x
end

local function parse_form (tr, opts)
  local tk = tr.current()
  if tk == nil then
    error("Unexpected end of text")
  end

  tr.advance()

  local tk_id, tk_value = (_G.unpack or table.unpack)(tk)
  if tk_id == '(' then
    return parse_list_tail(tr, opts)
  elseif tk_id == '{' then
    return parse_map_tail(tr, opts)
  elseif tk_id == '[' then
    return parse_vector_tail(tr, opts)
  elseif tk_id == '#{' then
    return parse_set_tail(tr, opts)
  elseif tk_id == 'num' then
    return tk_value
  elseif tk_id == 'string' then
    return tk_value
  elseif tk_id == 'keyword' then
    return (opts['keyword'] or identity)(tk_value)
  elseif tk_id == 'symbol' then
    if tk_value == 'true' then
      return true
    elseif tk_value == 'false' then
      return false
    elseif tk_value == 'nil' then
      return nil
    else
      return (opts['symbol'] or identity)(tk_value)
    end
  elseif tk_id == '#_' then
    local skip_count = 1
    while tk ~= nil and tk[1] == '#_' do
      skip_count = skip_count + 1
      tr.advance()
      tk = tr.current()
    end
    for _ = 1, skip_count do
      parse_form(tr, opts)
    end
    return parse_form(tr, opts)
  elseif tk_id == "tag" then
    local tags = opts['tags'] or {}
    return (tags[tk_value] or identity)(parse_form(tr, opts))
  end
end

function parse_list_tail (tr, opts)
  local seq = parse_seq_tail(tr, opts, ')')
  return (opts['list'] or identity)(seq)
end

function parse_map_tail (tr, opts)
  local start_tk = tr.current()

  local seq = parse_seq_tail(tr, opts, '}')
  if #seq % 2 == 1 then
    error("Map has odd number of items @ " .. start_tk[3])
  end

  local map = {}
  for i = 1, #seq, 2 do
    map[seq[i]] = seq[i+1]
  end
  return (opts['map'] or identity)(map)
end

function parse_set_tail (tr, opts)
  local seq = parse_seq_tail(tr, opts, '}')

  local set = {}
  for i = 1, #seq do
    set[seq[i]] = seq[i]
  end
  return (opts['set'] or identity)(set)
end

function parse_vector_tail (tr, opts)
  local seq = parse_seq_tail(tr, opts, ']')
  return (opts['vector'] or identity)(seq)
end

function parse_seq_tail (tr, opts, end_tk)
  local tk = tr.current()
  local seq = {}
  while tk ~= nil and tk[1] ~= end_tk do
    table.insert(seq, parse_form(tr, opts))
    tk = tr.current()
  end
  tr.advance()
  return seq
end

local api = {}

function api.decode (x, opts)
  local cr
  if type(x) == 'string' then
    cr = char_reader_from_string(x)
  elseif io.type(x) == 'file' then
    cr = char_reader_from_file(x)
  else
    error("Can't parse from given value, requires file or string")
  end
  return parse_form(token_reader_from_char_reader(cr), opts or {})
end

return api
