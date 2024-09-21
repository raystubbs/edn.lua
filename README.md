A very _very_ basic EDN parser for Lua.

Whipped this up because I needed an EDN parser, and
there didn't seem to be any in the Lua ecosystem.  Sharing
just in case anyone else is desperate.

It's a very dumb, low-effort implementation.  Didn't want
to dedicate much time to this side-quest.  But happy to
accept PRs for improvements.  Not sure I'll be adding much
myself, unless I get bored or run into a bug myself.

I got this just to the point that it's good enough for
what I need right now; so you can expect bugs if traversing
paths unknown.  Be ready to contribute fixes if you use this.

## Usage
Drop the `edn.lua` file into your project.
```lua
edn = require 'edn'
edn.decode '{:foo 1 :bar 2 :baz "meh"}' --> {foo = 1, bar = 2, baz = "meh"}

-- options can be passed to help it parse things
-- that aren't native to lua; e.g symbols, lists, etc.
edn.decode(
 '[foo :bar () {}]',
 {
    symbol = function (s) return 'sym:' .. s end,
    keyword = function (s) return ':' .. s end,
    list = function(t) return { type = 'list', children = t } end,
    map = function(t) return t end,
    vector = function(t) return t end
 }
)

-- tag readers can be given to handle things
-- like `#my-tag "some value"`, there aren't
-- any built-in tag readers, even though the
-- EDN spec defines some
edn.decode(
 '#str ["Hello" ", " "World" "!"]',
 {
    tags = {
        str = function (t) return table.concat(t) end
    }
 }
) --> "Hello, World!"
```

## Encoding
Not supported... yet.
