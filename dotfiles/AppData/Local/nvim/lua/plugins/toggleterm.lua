return {
  "akinsho/toggleterm.nvim",
  version = "*",
  keys = {
    { "<C-t>", "<cmd>ToggleTerm<CR>", mode = { "n", "t" } },
    { "<leader>gg", function()
      require("toggleterm.terminal").Terminal
        :new({ cmd = "lazygit", direction = "float", hidden = true })
        :toggle()
    end },
  },
  opts = {
    size = function(term)
      local sizes = { horizontal = 15, vertical = vim.o.columns * 0.4 }
      return sizes[term.direction]
    end,
    open_mapping = [[<C-t>]],
    direction = "float",
    float_opts = { border = "rounded" },
    shell = vim.o.shell,
  },
}
