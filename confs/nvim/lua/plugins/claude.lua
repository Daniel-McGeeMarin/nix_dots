return {
  --   "anthropic/claude-code.nvim",
  --   config = function()
  --     require("claude-code").setup {
  --       keymaps = {
  --         chat = "<leader>a", -- Open Claude chat window
  --         explain = "<leader>e", -- Explain selected code
  --         rewrite = "<leader>r", -- Rewrite selection
  --       },
  --       window = "split", -- "float" for floating window or "split" for side panel
  --     }
  --   end,
}
