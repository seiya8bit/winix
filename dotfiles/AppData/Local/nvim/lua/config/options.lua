local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Indentation
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true

-- Display
opt.termguicolors = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.wrap = false
opt.scrolloff = 8
opt.sidescrolloff = 8

-- Splits
opt.splitbelow = true
opt.splitright = true

-- Files
opt.swapfile = false
opt.backup = false
opt.undofile = true

-- Misc
opt.clipboard = "unnamedplus"
opt.updatetime = 250
opt.timeoutlen = 300
opt.completeopt = { "menu", "menuone", "noselect" }

-- Windows shell
if vim.fn.has("win32") == 1 then
  opt.shell = "pwsh"
  opt.shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command"
  opt.shellquote = ""
  opt.shellxquote = ""
end
