if vim.g.snippets ~= "luasnip" then
  return
end

local ls = require "luasnip"

ls.config.set_config {
  history = true,
  updateevents = "TextChanged,TextChangedI",
  enable_autosnippets = true,
}

vim.keymap.set({ "i", "s" }, "<Tab>", function()
  if ls.expand_or_jumpable() then
    ls.expand_or_jump()
  -- else
  --   vim.fn.feedkeys(vim.api.nvim_replace_termcodes(vim.fn['copilot#Accept'](), true, true, true), '')
  end
end, {silent = true});

vim.keymap.set({ "i", "s" }, "<S-Tab>", function()
  if ls.jumpable(-1) then
    ls.jump(-1)
  end
end, {silent = true});

vim.keymap.set({ "i", "s" }, "<C-Tab>", function()
  if ls.choice_active() then
    ls.change_choice(1)
  end
end, {silent = true});
require("luasnip.loaders.from_snipmate").lazy_load()
