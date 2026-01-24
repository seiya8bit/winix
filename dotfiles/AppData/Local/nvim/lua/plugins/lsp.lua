local buf_events = { "BufReadPre", "BufNewFile" }

return {
  -- Mason: LSP server manager
  {
    "mason-org/mason.nvim",
    cmd = "Mason",
    build = ":MasonUpdate",
    opts = {
      ui = {
        border = "rounded",
        icons = { package_installed = "✓", package_pending = "➜", package_uninstalled = "✗" },
      },
    },
  },

  -- Mason LSP Config
  {
    "mason-org/mason-lspconfig.nvim",
    event = buf_events,
    dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
    opts = {
      ensure_installed = {
        "lua_ls",
        "ts_ls",
        "cssls",
        "jsonls",
        "yamlls",
        "taplo",
        "marksman",
        "dockerls",
        "powershell_es",
      },
    },
  },

  -- LSP Config
  {
    "neovim/nvim-lspconfig",
    event = buf_events,
    dependencies = { "mason-org/mason.nvim" },
    config = function()
      vim.diagnostic.config({
        virtual_text = { prefix = "●" },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = " ",
            [vim.diagnostic.severity.WARN] = " ",
            [vim.diagnostic.severity.HINT] = "󰌵 ",
            [vim.diagnostic.severity.INFO] = " ",
          },
        },
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        float = { border = "rounded", source = true },
      })

      -- LSP keymaps on attach
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", {}),
        callback = function(ev)
          local o = { buffer = ev.buf }
          local map = vim.keymap.set

          map("n", "gd", vim.lsp.buf.definition, o)
          map("n", "gD", vim.lsp.buf.declaration, o)
          map("n", "gr", vim.lsp.buf.references, o)
          map("n", "gi", vim.lsp.buf.implementation, o)
          map("n", "gt", vim.lsp.buf.type_definition, o)
          map("n", "K", vim.lsp.buf.hover, o)
          map("n", "<C-k>", vim.lsp.buf.signature_help, o)
          map("n", "<leader>rn", vim.lsp.buf.rename, o)
          map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, o)
        end,
      })

      -- Mason-managed servers: auto-enabled by mason-lspconfig
      -- Custom settings only for servers that need them
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            runtime = { version = "LuaJIT" },
            diagnostics = { globals = { "vim" } },
            workspace = {
              library = vim.api.nvim_get_runtime_file("", true),
              checkThirdParty = false,
            },
            telemetry = { enable = false },
          },
        },
      })

      -- Godot GDScript LSP (requires Godot Editor running)
      vim.lsp.config("gdscript", {
        cmd = vim.lsp.rpc.connect("127.0.0.1", 6005),
        filetypes = { "gdscript" },
        root_markers = { "project.godot" },
      })
      vim.lsp.enable("gdscript")
    end,
  },
}
