local config = require("review.config")
local commands = require("review.commands")
local keymaps = require("review.keymaps")
local signs = require("review.signs")

local M = {}

function M.setup(opts)
  local merged, err = config.setup(opts or {})
  if not merged then
    return nil, err
  end

  commands.register()
  signs.setup()
  keymaps.setup(merged)

  return merged
end

return M
