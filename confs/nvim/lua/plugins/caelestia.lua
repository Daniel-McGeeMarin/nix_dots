return {
  {
    "atdma/caelestia-nvim",
    lazy = false,
    priority = 1000,
    config = function() require("caelestia").setup() end,
  },
}

--[[
FIX NOTE:
This plugin ships its module at the repo root instead of under lua/.
Lazy.nvim only adds lua/ to runtimepath, so require("caelestia") fails.

Workaround:
Create lua/ and move the caelestia folder into it:
  ~/.local/share/nvim/lazy/caelestia-nvim/caelestia
→ ~/.local/share/nvim/lazy/caelestia-nvim/lua/caelestia

The build() hook below automates this after install/update.
]]
