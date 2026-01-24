-- Prefer local node_modules/.bin over global (monorepo-aware)
local function local_bin(cmd)
  local buf_dir = vim.fn.expand("%:p:h")
  local path = vim.fn.findfile("node_modules/.bin/" .. cmd, buf_dir .. ";")
  return path ~= "" and vim.fn.fnamemodify(path, ":p") or cmd
end

return {
  -- Formatter
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    cmd = "ConformInfo",
    keys = {
      { "<leader>cf", function()
        require("conform").format({ async = true, lsp_format = "fallback" })
      end },
    },
    opts = {
      formatters_by_ft = {
        javascript = { "oxfmt" },
        javascriptreact = { "oxfmt" },
        typescript = { "oxfmt" },
        typescriptreact = { "oxfmt" },
        json = { "oxfmt" },
        jsonc = { "oxfmt" },
        yaml = { "oxfmt" },
        toml = { "oxfmt" },
        markdown = { "oxfmt" },
        css = { "oxfmt" },
        lua = { "stylua" },
      },
      formatters = {
        oxfmt = { command = function() return local_bin("oxfmt") end },
      },
      format_on_save = { timeout_ms = 500, lsp_format = "fallback" },
    },
  },

  -- Linter
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufWritePost" },
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = {
        javascript = { "oxlint" },
        javascriptreact = { "oxlint" },
        typescript = { "oxlint" },
        typescriptreact = { "oxlint" },
        json = { "jsonlint" },
        yaml = { "yamllint" },
        css = { "stylelint" },
        markdown = { "markdownlint" },
        lua = { "selene" },
        dockerfile = { "hadolint" },
      }

      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
        group = vim.api.nvim_create_augroup("NvimLint", { clear = true }),
        callback = function()
          for _, name in ipairs({ "oxlint", "stylelint", "markdownlint" }) do
            lint.linters[name].cmd = local_bin(name)
          end
          lint.try_lint()
        end,
      })
    end,
  },
}
