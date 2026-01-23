return {
  -- UI: load after first render
  {
    "nvim-mini/mini.icons",
    lazy = false,
    config = function()
      require("mini.icons").setup()
      MiniIcons.mock_nvim_web_devicons()
    end,
  },
  {
    "nvim-mini/mini.statusline",
    event = "VeryLazy",
    opts = { use_icons = true },
  },
  {
    "nvim-mini/mini.tabline",
    event = "VeryLazy",
    opts = {},
  },
  {
    "nvim-mini/mini.notify",
    event = "VeryLazy",
    config = function()
      require("mini.notify").setup()
      vim.notify = require("mini.notify").make_notify()
    end,
  },
  {
    "nvim-mini/mini.clue",
    event = "VeryLazy",
    config = function()
      local clue = require("mini.clue")
      -- Generate triggers for multiple modes
      local function triggers(modes, keys)
        local t = {}
        for _, m in ipairs(modes) do
          for _, k in ipairs(keys) do
            table.insert(t, { mode = m, keys = k })
          end
        end
        return t
      end
      local nx = { "n", "x" }
      local all_triggers = vim.iter({
        triggers(nx, { "<leader>", "g", "'", "`", '"', "z", "s" }),
        triggers({ "i", "c" }, { "<C-r>" }),
        triggers({ "n" }, { "<C-w>", "[", "]" }),
      }):flatten():totable()
      clue.setup({
        triggers = all_triggers,
        clues = {
          clue.gen_clues.builtin_completion(),
          clue.gen_clues.g(),
          clue.gen_clues.marks(),
          clue.gen_clues.registers(),
          clue.gen_clues.windows(),
          clue.gen_clues.z(),
          { mode = "n", keys = "<leader>b", desc = "+Buffer" },
          { mode = "n", keys = "<leader>c", desc = "+Code" },
          { mode = "n", keys = "<leader>f", desc = "+Find" },
          { mode = "n", keys = "<leader>g", desc = "+Git" },
          { mode = "n", keys = "<leader>r", desc = "+Rename" },
          { mode = "n", keys = "<leader>s", desc = "+Surround" },
          { mode = "n", keys = "s", desc = "+Surround" },
        },
        window = { delay = 300 },
      })
    end,
  },

  -- Fuzzy finder
  {
    "nvim-mini/mini.pick",
    keys = {
      { "<leader>ff", function() require("mini.pick").builtin.files() end },
      { "<leader>fg", function() require("mini.pick").builtin.grep_live() end },
      { "<leader>fb", function() require("mini.pick").builtin.buffers() end },
      { "<leader>fh", function() require("mini.pick").builtin.help() end },
      { "<leader>fr", function() require("mini.pick").builtin.resume() end },
    },
    opts = {},
  },

  -- Git diff signs
  {
    "nvim-mini/mini.diff",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      view = {
        style = "sign",
        signs = { add = "▎", change = "▎", delete = "" },
      },
    },
  },

  -- File explorer: load on keymap
  {
    "nvim-mini/mini.files",
    keys = {
      {
        "<leader>e",
        function()
          require("mini.files").open(vim.api.nvim_buf_get_name(0), true)
        end
      },
      {
        "<leader>E",
        function()
          require("mini.files").open(vim.uv.cwd(), true)
        end
      },
    },
    opts = {
      mappings = {
        close = "q", go_in = "l", go_in_plus = "<CR>",
        go_out = "h", go_out_plus = "H", reset = "<BS>",
        show_help = "g?", synchronize = "=",
        trim_left = "<", trim_right = ">",
      },
      windows = { preview = true, width_preview = 40 },
    },
  },

  -- Completion
  {
    "nvim-mini/mini.completion",
    event = "InsertEnter",
    opts = {
      delay = { completion = 50, info = 100, signature = 50 },
      window = {
        info = { border = "rounded" },
        signature = { border = "rounded" },
      },
      lsp_completion = { source_func = "omnifunc", auto_setup = true },
    },
  },

  -- Editing: load on InsertEnter or keymap
  {
    "nvim-mini/mini.pairs",
    event = "InsertEnter",
    opts = {},
  },
  {
    "nvim-mini/mini.comment",
    keys = { "gc", "gcc" },
    opts = {},
  },
  {
    "nvim-mini/mini.surround",
    keys = { "sa", "sd", "sf", "sF", "sh", "sr", "sn" },
    opts = {
      mappings = {
        add = "sa", delete = "sd", find = "sf", find_left = "sF",
        highlight = "sh", replace = "sr", update_n_lines = "sn",
      },
    },
  },
  {
    "nvim-mini/mini.move",
    keys = {
      { "<M-h>", mode = { "n", "v" } },
      { "<M-j>", mode = { "n", "v" } },
      { "<M-k>", mode = { "n", "v" } },
      { "<M-l>", mode = { "n", "v" } },
    },
    opts = {
      mappings = {
        left = "<M-h>", right = "<M-l>", down = "<M-j>", up = "<M-k>",
        line_left = "<M-h>", line_right = "<M-l>",
        line_down = "<M-j>", line_up = "<M-k>",
      },
    },
  },

  -- Visual: load on BufRead
  {
    "nvim-mini/mini.indentscope",
    event = { "BufReadPost", "BufNewFile" },
    opts = { symbol = "│", options = { try_as_border = true } },
  },
  {
    "nvim-mini/mini.cursorword",
    event = { "BufReadPost", "BufNewFile" },
    opts = {},
  },
}
