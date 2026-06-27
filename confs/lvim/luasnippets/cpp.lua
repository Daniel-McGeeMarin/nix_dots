local ls = require("luasnip") --{{{
local s, i, t = ls.s, ls.i, ls.t

local d, c, f, sn = ls.dynamic_node, ls.choice_node, ls.function_node, ls.snippet_node

local fmt, rep, conds = require("luasnip.extras.fmt").fmt, require("luasnip.extras").rep, require("luasnip.extras.expand_conditions")

local snippets, autosnippets = {}, {} --}}}

local group = vim.api.nvim_create_augroup("Lua Snippets", { clear = true })
local file_pattern = "*.lua"

-- Start Refactoring --

local gsv = s("gsv",
  fmt(
    [[
{} {};
{}
{} const get_{}() {{return {};}}
void set_{}(const {} &_{}) {{{} = _{};}}
]], {
    i(1, "Type"),
    i(2, "varName"),
    i(3, "public:"),
    rep(1),
    rep(2),
    rep(2),
    rep(2),
    rep(1),
    rep(2),
    rep(2),
    rep(2),
    }
  )
) table.insert(snippets, gsv)

local class = s({ trig = "cls"}, --condition = function(...) return conds.expand.line_end(...) or conds.expand.line_begin(...) end},
  fmt(
    [[
class {} {{
  {}
}};
]], {
    i(1, "Name"),
    i(2, "// TODO"),
    }
  )
) table.insert(snippets, class)

local classI = s({ trig = "clsi"}, --condition = function(...) return conds.expand.line_end(...) or conds.expand.line_begin(...) end},
  fmt(
    [[
class {} : public {} {{
  {}
}};
]], {
    i(1, "Name"),
    i(2, "inheritClass"),
    i(3, "// TODO"),
    }
  )
) table.insert(snippets, classI)

local init = s({ trig = "init"}, --condition = function(...) return conds.expand.line_end(...) or conds.expand.line_begin(...) end},
  fmt([[
// Benjamin P. McIntyre
#include <iostream>
#include <math.h>

using std::cout;
using std::endl;
using std::cin;
using std::string;

{}

int main(int argc, char *argv[]) {{
  {}
}}
]], {
    i(1, ""),
    i(2, "//TODO"),
    }
  )
) table.insert(snippets, init)

local init = s({ trig = "init"}, --condition = function(...) return conds.expand.line_end(...) or conds.expand.line_begin(...) end},
  fmt([[
// Benjamin P. McIntyre
#include <iostream>
#include <math.h>

using std::cout;
using std::endl;
using std::cin;
using std::string;

{}

int main(int argc, char *argv[]) {{
  {}
}}
]], {
    i(1, ""),
    i(2, "//TODO"),
    }
  )
) table.insert(snippets, init)

-- End Refactoring --

return snippets, autosnippets
