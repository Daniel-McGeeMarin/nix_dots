{ lib, config, inputs, pkgs, ... }:
let
  # caelestia-nvim ships its module at the repo root instead of under lua/,
  # which breaks lazy-loading. We fix the directory layout here so
  # require("caelestia") works without any manual intervention.
  caelestia-nvim = pkgs.vimUtils.buildVimPlugin {
    name = "caelestia-nvim";
    src = pkgs.runCommand "caelestia-nvim-fixed" { } ''
      cp -rT --no-preserve=mode ${pkgs.fetchFromGitHub {
        owner = "atdma";
        repo = "caelestia-nvim";
        rev = "03a7f68c1026335faf699c8bb7ff7b3c1b6d776a";
        sha256 = "1hjhilq75zcyy7m81grr2yqaqhxbwcpxiabn0ki5z492ln514890";
      }} $out
      mkdir -p $out/lua
      mv $out/caelestia $out/lua/caelestia
    '';
  };
in
{
  imports = [ inputs.nixvim.homeModules.nixvim ];

  config = lib.mkIf config.tui.enable {
    programs.nixvim = {
      enable = true;
      package = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.neovim-unwrapped;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;

      # ── Options ────────────────────────────────────────────────────────────
      opts = {
        relativenumber = true;
        number = true;
        signcolumn = "yes";
        wrap = true;
        linebreak = true;
        breakindent = true;
        termguicolors = true;
        expandtab = true;
        shiftwidth = 2;
        tabstop = 2;
        scrolloff = 8;
        updatetime = 250;
        undofile = true;
      };

      globals = {
        mapleader = " ";
        maplocalleader = ",";
        # VimTeX — use mkForce to override nixvim's vimtex module defaults
        vimtex_view_method            = lib.mkForce "zathura";
        vimtex_compiler_method        = lib.mkForce "latexmk";
        vimtex_quickfix_mode          = lib.mkForce 0;
        vimtex_view_forward_search_on_start = lib.mkForce 1;
        vimtex_view_automatic         = lib.mkForce 1;
      };

      # ── Packages available inside neovim's env ──────────────────────────────
      extraPackages = with pkgs; [
        stylua
        python312Packages.flake8
        shellcheck
        rustup
        gcc
        tree-sitter
        luajitPackages.magick
        clang-tools
        lua-language-server
        nixd
        pyright
        lazygit
      ];

      # ── Plugins not covered by nixvim modules ───────────────────────────────
      extraPlugins = with pkgs.vimPlugins; [
        caelestia-nvim
        presence-nvim
        lsp_signature-nvim
        nvim-window-picker
        lazygit-nvim
        nvim-highlight-colors
      ];

      # ── Init lua (runs after all plugin setups) ──────────────────────────────
      extraConfigLua = ''
        -- caelestia: reads ~/.local/state/caelestia/scheme.json and applies
        -- highlights directly — no named vim colorscheme, setup() is all we need
        require("caelestia").setup()

        -- lsp_signature: show function signature as you type
        require("lsp_signature").setup({ hint_enable = false })

        -- presence.nvim: Discord rich presence
        require("presence").setup()

        -- nvim-highlight-colors: inline colour swatches
        require("nvim-highlight-colors").setup()

        -- LuaSnip: treat JS files as JSX for snippet purposes
        require("luasnip").filetype_extend("javascript", { "javascriptreact" })

        -- nvim-autopairs: LaTeX $…$ pair rules
        local npairs = require("nvim-autopairs")
        local Rule   = require("nvim-autopairs.rule")
        local cond   = require("nvim-autopairs.conds")
        npairs.add_rules({
          Rule("$", "$", { "tex", "latex" })
            :with_pair(cond.not_after_regex("%%"))
            :with_pair(cond.not_before_regex("xxx", 3))
            :with_move(cond.none())
            :with_del(cond.not_after_regex("xx"))
            :with_cr(cond.none()),
        })

        -- Alt+1..9: jump to Nth buffer
        local function goto_buffer(n)
          vim.cmd("bfirst")
          for _ = 2, n do vim.cmd("bnext") end
        end
        for i = 1, 9 do
          vim.keymap.set("n", "<A-" .. i .. ">",
            function() goto_buffer(i) end,
            { desc = "Go to buffer " .. i })
        end
      '';

      # ── Autocmds ────────────────────────────────────────────────────────────
      autoCmd = [
        {
          event = "FileType";
          pattern = "tex";
          desc = "VimTeX buffer-local keymaps";
          callback.__raw = ''
            function()
              -- <leader>lp  compile and open in Zathura
              vim.keymap.set("n", "<leader>lp", function()
                vim.cmd("VimtexCompile")
                vim.fn.jobstart(
                  "zathura " .. vim.fn.expand("%:r") .. ".pdf",
                  { detach = true })
              end, { desc = "Compile LaTeX and open Zathura", buffer = true })

              -- <leader>le  compile, export to resume pipeline, quit
              vim.keymap.set("n", "<leader>le", function()
                local base    = vim.fn.expand("%:t:r")
                local src_pdf = vim.fn.expand("%:p:r") .. ".pdf"
                local dest1   = vim.fn.expand("~/MyApps/resume-pipeline/resume-pdf/" .. base .. ".pdf")
                local dest2   = vim.fn.expand("~/MyApps/resume-pipeline/current-resume/Daniel McGee Resume.pdf")

                vim.cmd("VimtexCompile")
                vim.fn.jobstart({ "cp", "-f", src_pdf, dest1 })
                vim.fn.jobstart({ "cp", "-f", src_pdf, dest2 })

                vim.defer_fn(function()
                  vim.fn.jobstart({
                    "sh", "-c",
                    "for pid in $(pgrep -x zathura); do "
                      .. "lsof -p $pid 2>/dev/null | grep '" .. src_pdf .. "' "
                      .. "&& kill $pid; done",
                  })
                  vim.fn.jobstart({ "pkill", "-P", tostring(vim.fn.getpid()) })
                  vim.fn.jobstart({
                    "sh", "-c",
                    "for pid in $(hyprctl clients -j | jq -r "
                      .. "'.[] | select(.workspace.id == 11 and "
                      .. "(.class == \"kitty\" or .class == \"org.pwmt.zathura\")) | .pid'); "
                      .. "do kill $pid; done",
                  }, { detach = true })
                  vim.cmd("qa!")
                end, 1500)
              end, { desc = "Compile and export resume PDF, quit", buffer = true })
            end
          '';
        }
      ];

      # ── Keymaps ─────────────────────────────────────────────────────────────
      keymaps = [
        # Telescope
        { mode = "n"; key = "<C-p>";   action = "<cmd>Telescope find_files<cr>";  options.desc = "Quick open"; }
        { mode = "n"; key = "<C-S-p>"; action = "<cmd>Telescope commands<cr>";    options.desc = "Command palette"; }
        { mode = "n"; key = "<C-S-f>"; action = "<cmd>Telescope live_grep<cr>";   options.desc = "Search in files"; }

        # File tree
        { mode = "n"; key = "<C-b>"; action = "<cmd>Neotree toggle<cr>"; options.desc = "Explorer"; }

        # Buffer navigation
        { mode = "n"; key = "<C-Tab>";   action = "<cmd>bnext<cr>";     options.desc = "Next buffer"; }
        { mode = "n"; key = "<C-S-Tab>"; action = "<cmd>bprevious<cr>"; options.desc = "Prev buffer"; }
        { mode = "n"; key = "]b";        action = "<cmd>bnext<cr>";     options.desc = "Next buffer"; }
        { mode = "n"; key = "[b";        action = "<cmd>bprevious<cr>"; options.desc = "Prev buffer"; }
        { mode = "n"; key = "<Leader>bd"; action.__raw = ''
            function()
              local bufnr = vim.api.nvim_get_current_buf()
              vim.cmd("bnext")
              vim.cmd("bdelete " .. bufnr)
            end
          ''; options.desc = "Close buffer"; }

        # Splits
        { mode = "n"; key = "<C-w>v"; action = "<cmd>vsplit<cr>"; options.desc = "Split vertical"; }
        { mode = "n"; key = "<C-w>s"; action = "<cmd>split<cr>";  options.desc = "Split horizontal"; }

        # Comment
        { mode = "n"; key = "<C-/>"; action.__raw = "function() require('Comment.api').toggle.linewise.current() end"; options.desc = "Toggle comment"; }
        { mode = "v"; key = "<C-/>"; action.__raw = "function() require('Comment.api').toggle.linewise(vim.fn.visualmode()) end"; options.desc = "Toggle comment"; }

        # Terminal
        { mode = "n"; key = "<C-t>t"; action = "<cmd>ToggleTerm<cr>"; options.desc = "Toggle terminal"; }

        # Git (lazygit)
        { mode = "n"; key = "<C-g>g"; action = "<cmd>LazyGit<cr>"; options.desc = "Git panel"; }

        # LSP
        { mode = "n"; key = "<C-g>d"; action.__raw = "vim.lsp.buf.definition";  options.desc = "Go to definition"; }
        { mode = "n"; key = "<C-g>r"; action = "<cmd>Telescope lsp_references<cr>"; options.desc = "References"; }
        { mode = "n"; key = "<C-g>n"; action.__raw = "vim.lsp.buf.rename";       options.desc = "Rename symbol"; }
        { mode = "n"; key = "<C-g>f"; action.__raw = "function() pcall(vim.lsp.buf.format, { async = true }) end"; options.desc = "Format"; }
        { mode = "n"; key = "<C-g>k"; action.__raw = "vim.lsp.buf.hover";        options.desc = "Hover docs"; }
        { mode = "n"; key = "gD";     action.__raw = "vim.lsp.buf.declaration";  options.desc = "Declaration"; }

        # Select all
        { mode = "n"; key = "<C-a>"; action = "<cmd>keepjumps normal! gg0vG$<cr>"; options.desc = "Select all"; }
      ];

      # ── Plugins ─────────────────────────────────────────────────────────────
      plugins = {

        # Fuzzy finder
        telescope = {
          enable = true;
          extensions.fzf-native.enable = true;
        };

        # File tree
        neo-tree = {
          enable = true;
          settings.window.position = "left";
          settings.window.width = 30;
        };

        # Syntax / AST
        treesitter = {
          enable = true;
          settings = {
            highlight.enable = true;
            indent.enable = true;
            ensure_installed = [
              "bash" "c" "cpp" "css" "html" "javascript" "json"
              "latex" "lua" "markdown" "nix" "python" "rust"
              "toml" "typescript" "vim" "vimdoc" "yaml"
            ];
          };
        };
        treesitter-textobjects.enable = true;

        # Completion
        blink-cmp = {
          enable = true;
          settings = {
            keymap.preset = "default";
            sources.default = [ "lsp" "path" "snippets" "buffer" ];
            appearance.use_nvim_cmp_as_default = true;
          };
        };

        # Snippets
        luasnip.enable = true;
        friendly-snippets.enable = true;

        # LSP
        lsp = {
          enable = true;
          servers = {
            lua_ls.enable = true;
            clangd.enable = true;
            rust_analyzer = {
              enable = true;
              installRustc = false;
              installCargo = false;
            };
            pyright.enable = true;
            nixd.enable = true;
          };
        };

        # Statusline
        lualine = {
          enable = true;
          settings.options.theme = "auto";
        };

        # Buffer tabs
        bufferline.enable = true;

        # Git decorations
        gitsigns = {
          enable = true;
          settings.signs = {
            add.text          = "│";
            change.text       = "│";
            delete.text       = "_";
            topdelete.text    = "‾";
            changedelete.text = "~";
          };
        };

        # Keybinding hints
        which-key.enable = true;

        # Floating terminal
        toggleterm = {
          enable = true;
          settings = {
            direction = "float";
            float_opts.border = "curved";
          };
        };

        # TODO / FIXME highlighting
        todo-comments.enable = true;

        # Auto close brackets/quotes
        nvim-autopairs.enable = true;

        # LaTeX
        vimtex.enable = true;

        # Code outline sidebar
        aerial.enable = true;

        # Dashboard + various utilities (notifications, picker, etc.)
        snacks = {
          enable = true;
          settings = {
            notifier.enable = true;
            dashboard = {
              # omit "startup" — it requires lazy.stats which doesn't exist without lazy.nvim
              sections = [
                { section = "header"; }
                { section = "keys"; gap = 1; padding = 1; }
                { section = "recent_files"; padding = 1; }
                { section = "projects"; padding = 1; }
              ];
            };
          };
        };

        # Word highlight under cursor
        illuminate.enable = true;

        # Smarter pane splits
        smart-splits.enable = true;

        # Icons (used by neo-tree, lualine, etc.)
        mini = {
          enable = true;
          modules.icons = { };
        };

        # Auto-detect indentation style
        guess-indent.enable = true;

        # Debugger
        dap.enable = true;
        dap-ui.enable = true;
        dap-virtual-text.enable = true;

        # Lua LSP enhancements (neovim API types)
        lazydev.enable = true;

        # gc / gcc commenting
        comment.enable = true;

      };
    };
  };
}
