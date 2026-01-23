return {
  "nvim-treesitter/nvim-treesitter",
  lazy = false,
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter").install({
      -- Web
      "javascript",
      "jsx",
      "typescript",
      "tsx",
      "css",
      -- Data
      "json",
      "yaml",
      "toml",
      "markdown",
      "markdown_inline",
      -- Script
      "lua",
      "powershell",
      -- Infra
      "dockerfile",
    })
  end,
}
