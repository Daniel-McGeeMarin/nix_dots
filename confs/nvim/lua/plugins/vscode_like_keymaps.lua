return {
  {
    "AstroNvim/astrocore",
    opts = function(_, opts)
      local n = (opts.mappings or {}).n or {}

      -- VS Code-like keymaps
      n["<C-p>"] = { "<cmd>Telescope find_files<cr>", desc = "Quick open" }
      n["<C-S-p>"] = { "<cmd>Telescope commands<cr>", desc = "Command palette" }
      n["<C-b>"] = { "<cmd>Neotree toggle<cr>", desc = "Explorer" }
      n["<C-S-f>"] = { "<cmd>Telescope live_grep<cr>", desc = "Search in files" }

      n["<C-Tab>"] = { "<cmd>bnext<cr>", desc = "Next buffer" }
      n["<C-S-Tab>"] = { "<cmd>bprevious<cr>", desc = "Prev buffer" }
      n["<C-b>n"] = { "<cmd>bnext<cr>", desc = "Next buffer (fallback)" }
      n["<C-b>p"] = { "<cmd>bprevious<cr>", desc = "Prev buffer (fallback)" }

      n["<C-w>v"] = { "<cmd>vsplit<cr>", desc = "Split vertical" }
      n["<C-w>s"] = { "<cmd>split<cr>", desc = "Split horizontal" }

      n["<C-/>"] = {
        function() require("Comment.api").toggle.linewise.current() end,
        desc = "Toggle line comment",
      }

      n["<C-t>t"] = { "<cmd>ToggleTerm<cr>", desc = "Toggle terminal" }
      n["<C-g>g"] = { "<cmd>LazyGit<cr>", desc = "Git panel" }

      n["<C-g>d"] = { function() vim.lsp.buf.definition() end, desc = "Go to definition" }
      n["<C-g>r"] = { "<cmd>Telescope lsp_references<cr>", desc = "References" }
      n["<C-g>n"] = { function() vim.lsp.buf.rename() end, desc = "Rename symbol" }
      n["<C-g>f"] = { function() pcall(vim.lsp.buf.format, { async = true }) end, desc = "Format" }
      n["<C-g>k"] = { function() vim.lsp.buf.hover() end, desc = "Hover" }

      -- Ctrl+1..9 to jump to buffers by position
      local function goto_buffer(nr)
        vim.cmd "bfirst"
        for _ = 2, nr do
          vim.cmd "bnext"
        end
      end
      for i = 1, 9 do
        n["<A-" .. i .. ">"] = {
          function() goto_buffer(i) end,
          desc = "Go to buffer " .. i,
        }
      end

      -- Ctrl+A = select all text in the buffer
      n["<C-a>"] = {
        "<cmd>keepjumps normal! gg0vG$<cr>",
        desc = "Select all",
      }

      opts.mappings = opts.mappings or {}
      opts.mappings.n = n
    end,
  },
}
