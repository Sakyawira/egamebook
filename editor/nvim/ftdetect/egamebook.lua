vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.egb.txt",
  callback = function()
    vim.bo.filetype = "egamebook"
  end,
})
