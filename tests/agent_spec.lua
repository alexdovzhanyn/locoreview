package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

describe("locoreview agent", function()
  local old_vim
  local state

  before_each(function()
    state = {
      cmd_calls = {},
      termopen_arg = nil,
      system_arg = nil,
      shell_error = 0,
    }

    old_vim = _G.vim
    _G.vim = {
      fn = {
        shellescape = function(value)
          return "'" .. value:gsub("'", "'\\''") .. "'"
        end,
        termopen = function(arg)
          state.termopen_arg = arg
          return 1
        end,
        system = function(arg)
          state.system_arg = arg
          return ""
        end,
      },
      cmd = function(command)
        table.insert(state.cmd_calls, command)
      end,
      v = {
        shell_error = 0,
      },
    }
  end)

  after_each(function()
    _G.vim = old_vim
    package.loaded["locoreview.agent"] = nil
  end)

  it("opens terminal via termopen in a split", function()
    local agent = require("locoreview.agent")
    local ok = agent.run({}, "/repo", "/repo/review.md", {
      cmd = "codex",
      open_in_split = true,
    })

    assert.is_true(ok)
    assert.are.same({ "botright new" }, state.cmd_calls)
    assert.is_truthy(state.termopen_arg)
    assert.is_truthy(state.termopen_arg:match("^codex "))
  end)

  it("runs synchronously when split mode is disabled", function()
    local agent = require("locoreview.agent")
    local ok, prompt = agent.run({}, "/repo", "/repo/review.md", {
      cmd = "codex",
      open_in_split = false,
    })

    assert.is_true(ok)
    assert.is_truthy(prompt:match("Repository: /repo"))
    assert.is_truthy(state.system_arg)
    assert.is_nil(state.termopen_arg)
  end)
end)
