# eGameBook in Neovim

This project includes a Neovim filetype for `*.egb.txt`. It colors object and
field headers, Ink choices, references, conditionals, rule tags, media cues,
comments, and embedded Dart in `[[CODE]]` blocks. Colors follow your active
Neovim colorscheme.

Add this directory to your Neovim runtime path in `~/.config/nvim/init.lua`:

```lua
vim.opt.rtp:append(vim.fn.expand("~/Documents/Personal/egamebook/editor/nvim"))
vim.filetype.add({ pattern = { [".*%.egb%.txt"] = "egamebook" } })
vim.cmd("syntax enable")
```

Open an `.egb.txt` file and run `:EgbBuild` or press `<leader>eb` to save and
compile the story. The build runs in the background and requires the Dart SDK.
Errors appear in Neovim's quickfix
window; `:cnext` and `:cprev` move between locations when the compiler provides
them. Restart the TUI after a successful build to load the new story.
