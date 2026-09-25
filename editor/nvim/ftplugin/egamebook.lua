local buffer = vim.api.nvim_get_current_buf()
vim.bo[buffer].commentstring = "// %s"

local function build_story()
  if vim.bo[buffer].modified then
    local saved, error_message = pcall(vim.api.nvim_buf_call, buffer, function()
      vim.cmd("write")
    end)
    if not saved then
      vim.notify("Save the story before compiling: " .. tostring(error_message), vim.log.levels.ERROR)
      return
    end
  end

  local source = vim.api.nvim_buf_get_name(buffer)
  local build_file = vim.fs.find("build.yaml", {
    path = vim.fs.dirname(source),
    upward = true,
  })[1]
  if not build_file then
    vim.notify("No eGameBook build.yaml found above this file", vim.log.levels.ERROR)
    return
  end

  if vim.b[buffer].egb_building then
    vim.notify("eGameBook build is already running", vim.log.levels.WARN)
    return
  end

  if vim.fn.executable("dart") ~= 1 then
    vim.notify("Dart is required for :EgbBuild (https://dart.dev/get-dart)", vim.log.levels.ERROR)
    return
  end

  local game_dir = vim.fs.dirname(build_file)
  vim.b[buffer].egb_building = true
  vim.notify("Compiling eGameBook story…", vim.log.levels.INFO)

  vim.system(
    { "dart", "run", "build_runner", "build", "--delete-conflicting-outputs" },
    { cwd = game_dir, text = true },
    function(result)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buffer) then
          vim.b[buffer].egb_building = false
        end

        local output = (result.stdout or "") .. "\n" .. (result.stderr or "")
        local items = {}
        for line in output:gmatch("[^\r\n]+") do
          local path, row, column, message = line:match("^([^:]+):(%d+):(%d+):%s*(.*)$")
          if path then
            local filename = path:sub(1, 1) == "/" and path or vim.fs.joinpath(game_dir, path)
            items[#items + 1] = {
              filename = filename,
              lnum = tonumber(row),
              col = tonumber(column),
              text = message,
              type = "E",
            }
          else
            items[#items + 1] = { text = line }
          end
        end

        vim.fn.setqflist({}, "r", { title = "eGameBook build", items = result.code == 0 and {} or items })
        if result.code == 0 then
          vim.notify("eGameBook story compiled. Restart the TUI to load it.", vim.log.levels.INFO)
        else
          vim.cmd("copen")
          vim.notify("eGameBook build failed; see quickfix", vim.log.levels.ERROR)
        end
      end)
    end
  )
end

vim.api.nvim_buf_create_user_command(buffer, "EgbBuild", build_story, {
  desc = "Compile the eGameBook story",
})
vim.keymap.set("n", "<leader>eb", build_story, {
  buffer = buffer,
  desc = "Compile the eGameBook story",
})
