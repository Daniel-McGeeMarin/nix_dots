---@type LazySpec
return {
  -- Custom dashboard
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = {
          header = table.concat({
            " █████  ███████ ████████ ██████   ██████ ",
            "██   ██ ██         ██    ██   ██ ██    ██",
            "███████ ███████    ██    ██████  ██    ██",
            "██   ██      ██    ██    ██   ██ ██    ██",
            "██   ██ ███████    ██    ██   ██  ██████ ",
            "",
            "███    ██ ██    ██ ██ ███    ███",
            "████   ██ ██    ██ ██ ████  ████",
            "██ ██  ██ ██    ██ ██ ██ ████ ██",
            "██  ██ ██  ██  ██  ██ ██  ██  ██",
            "██   ████   ████   ██ ██      ██",
          }, "\n"),
        },
      },
    },
  },

  -- Example plugins (optional)
  "andweeb/presence.nvim",
  {
    "ray-x/lsp_signature.nvim",
    event = "BufRead",
    config = function() require("lsp_signature").setup() end,
  },

  -- Disable default plugin
  { "max397574/better-escape.nvim", enabled = false },

  -- LuaSnip: extend for React
  {
    "L3MON4D3/LuaSnip",
    config = function(plugin, opts)
      require "astronvim.plugins.configs.luasnip"(plugin, opts)
      local luasnip = require "luasnip"
      luasnip.filetype_extend("javascript", { "javascriptreact" })
    end,
  },

  -- :white_check_mark: VimTeX config with working <leader>pv keymap
  {
    "lervag/vimtex",
    ft = { "tex" },
    config = function()
      vim.g.vimtex_view_method = "zathura"
      vim.g.vimtex_compiler_method = "latexmk"
      vim.g.vimtex_quickfix_mode = 0
      vim.g.vimtex_view_forward_search_on_start = 1
      vim.g.vimtex_view_automatic = 1
    end,
    keys = {
      {
        "<leader>lp",
        function()
          vim.cmd "VimtexCompile"
          vim.fn.jobstart("zathura " .. vim.fn.expand "%:r" .. ".pdf", { detach = true })
        end,
        desc = "Compile LaTeX and open Zathura externally",
      },
    },
  },

  {
    "lervag/vimtex",
    ft = { "tex" },
    config = function()
      vim.g.vimtex_view_method = "zathura"
      vim.g.vimtex_compiler_method = "latexmk"
      vim.g.vimtex_quickfix_mode = 0
    end,
    keys = {
      {
        "<leader>le",
        function()
          local base = vim.fn.expand "%:t:r"
          local src_pdf = vim.fn.expand "%:p:r" .. ".pdf"
          local dest1 = vim.fn.expand("~/MyApps/resume-pipeline/resume-pdf/" .. base .. ".pdf")
          local dest2 = vim.fn.expand "~/MyApps/resume-pipeline/current-resume//Daniel McGee Resume.pdf"

          vim.cmd "VimtexCompile"
          vim.fn.jobstart { "cp", "-f", src_pdf, dest1 }
          vim.fn.jobstart { "cp", "-f", src_pdf, dest2 }

          vim.defer_fn(function()
            -- Kill Zathura if it's showing the current PDF
            vim.fn.jobstart {
              "sh",
              "-c",
              "zathura_pids=$(pgrep -x zathura); for pid in $zathura_pids; do "
                .. "lsof -p $pid 2>/dev/null | grep '"
                .. src_pdf
                .. "' && kill $pid; done",
            }

            -- Kill latexmk or other child jobs
            vim.fn.jobstart { "pkill", "-P", tostring(vim.fn.getpid()) }

            -- Close all terminal windows in workspace 11
            vim.fn.jobstart({
              "sh",
              "-c",
              [[for pid in $(hyprctl clients -j | jq -r '.[] | select(.workspace.id == 11 and (.class == "kitty" or .class == "org.pwmt.zathura")) | .pid'); do kill $pid; done]],
            }, { detach = true })

            -- Exit Neovim
            vim.cmd "qa!"
          end, 1500)
        end,
        desc = "Compile and export PDF, kill Zathura, quit Neovim, close terminal windows on workspace 11",
      },
    },
  },

  -- Autopairs config for LaTeX
  {
    "windwp/nvim-autopairs",
    config = function(plugin, opts)
      require "astronvim.plugins.configs.nvim-autopairs"(plugin, opts)
      local npairs = require "nvim-autopairs"
      local Rule = require "nvim-autopairs.rule"
      local cond = require "nvim-autopairs.conds"
      npairs.add_rules {
        Rule("$", "$", { "tex", "latex" })
          :with_pair(cond.not_after_regex "%%")
          :with_pair(cond.not_before_regex("xxx", 3))
          :with_move(cond.none())
          :with_del(cond.not_after_regex "xx")
          :with_cr(cond.none()),
      }
    end,
  },
}
