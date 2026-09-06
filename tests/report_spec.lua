-- The one public call: what it puts on the engine's command line, what it
-- refuses before spawning anything, and what it says when the spawn fails.
--
-- The argv cases substitute `vim.system` and read the command back. The two
-- failure cases do not: a binary that is not there and a binary that exits
-- non-zero are both answered by the operating system, and a fake would only
-- pin what this file believes about them.

local pns = require("pns")

--- Run `body` with `vim.system` and `vim.notify` recorded rather than real,
--- and with the options restored afterwards however it ends.
---@return string[][] commands
---@return string[] notices
local function captured(options, body)
  local real_system, real_notify, real_options = vim.system, vim.notify, pns.options
  local commands, notices = {}, {}

  pns.options = vim.tbl_extend("force", vim.deepcopy(real_options), options or {})
  vim.system = function(cmd)
    commands[#commands + 1] = cmd
    return {}
  end
  vim.notify = function(message)
    notices[#notices + 1] = message
  end

  local ok, err = pcall(body)

  vim.system, vim.notify, pns.options = real_system, real_notify, real_options

  if not ok then
    error(err, 0)
  end

  return commands, notices
end

--- The same, with the real `vim.system` left alone.
---@return string[] notices
local function notices_from(options, body)
  local real_notify, real_options = vim.notify, pns.options
  local notices = {}

  pns.options = vim.tbl_extend("force", vim.deepcopy(real_options), options or {})
  vim.notify = function(message)
    notices[#notices + 1] = message
  end

  local ok, err = pcall(body)

  -- The engine's own exit arrives on the event loop, so the notice cannot be
  -- read until the loop has run. The second wait is what proves the SECOND
  -- failure stayed quiet rather than merely arriving late.
  vim.wait(3000, function()
    return #notices > 0
  end)
  vim.wait(150)

  vim.notify, pns.options = real_notify, real_options

  if not ok then
    error(err, 0)
  end

  return notices
end

local function assert_command(actual, expected)
  assert(
    vim.deep_equal(actual, expected),
    ("argv was %s\nexpected  %s"):format(vim.inspect(actual), vim.inspect(expected))
  )
end

--- Set `HERDR_PANE_ID` for the duration of `body`, or unset it when `pane` is
--- nil, and put back whatever the environment had.
local function with_pane(pane, body)
  local real = vim.env.HERDR_PANE_ID
  vim.env.HERDR_PANE_ID = pane

  local ok, err = pcall(body)

  vim.env.HERDR_PANE_ID = real

  if not ok then
    error(err, 0)
  end
end

return {
  ["builds the engine's command line for a finished task"] = function()
    local commands = captured({ binary = "pns", agent = "nvim", project = "dotfiles", pane = "%7" }, function()
      pns.report({ state = "done", detail = "overseer: build", elapsed = 42 })
    end)

    assert(#commands == 1, "one process was spawned")
    assert_command(commands[1], {
      "pns",
      "--agent",
      "nvim",
      "--state",
      "done",
      "--project",
      "dotfiles",
      "--detail",
      "overseer: build",
      "--elapsed",
      "42",
      "--pane",
      "%7",
    })
  end,

  ["carries a failure through as the failed state"] = function()
    local commands = captured({ project = "dotfiles", pane = "%7" }, function()
      pns.report({ state = "failed", detail = "neotest: init_spec.lua", elapsed = 7 })
    end)

    assert_command(commands[1], {
      "pns",
      "--agent",
      "nvim",
      "--state",
      "failed",
      "--project",
      "dotfiles",
      "--detail",
      "neotest: init_spec.lua",
      "--elapsed",
      "7",
      "--pane",
      "%7",
    })
  end,

  ["leaves out the pane and the project when there are none"] = function()
    with_pane(nil, function()
      local commands = captured({ project = "" }, function()
        pns.report({ state = "done", detail = "overseer: build", elapsed = 42 })
      end)

      assert_command(commands[1], {
        "pns",
        "--agent",
        "nvim",
        "--state",
        "done",
        "--detail",
        "overseer: build",
        "--elapsed",
        "42",
      })
    end)
  end,

  ["defaults the project to the working directory and the pane to the environment"] = function()
    with_pane("%12", function()
      local commands = captured({}, function()
        pns.report({ state = "done", detail = "overseer: build", elapsed = 1 })
      end)

      local argv = commands[1]
      assert(argv[7] == vim.fs.basename(vim.uv.cwd()), "the project is the working directory's name: " .. argv[7])
      assert(argv[13] == "%12", "the pane came from HERDR_PANE_ID: " .. tostring(argv[13]))
    end)
  end,

  ["prefers the report's own project and pane over every default"] = function()
    with_pane("%12", function()
      local commands = captured({ project = "from-setup", pane = "%99" }, function()
        pns.report({ state = "done", detail = "overseer: build", elapsed = 1, project = "from-call", pane = "%1" })
      end)

      local argv = commands[1]
      assert(argv[7] == "from-call", "the call's project won: " .. argv[7])
      assert(argv[13] == "%1", "the call's pane won: " .. argv[13])
    end)
  end,

  ["expands a tilde in the binary, which vim.system never would"] = function()
    local commands = captured({ binary = "~/.local/libexec/pns/pns", project = "dotfiles" }, function()
      pns.report({ state = "done", detail = "overseer: build", elapsed = 1 })
    end)

    assert(
      commands[1][1] == vim.fs.normalize("~/.local/libexec/pns/pns"),
      "the binary was expanded: " .. commands[1][1]
    )
    assert(not commands[1][1]:find("~", 1, true), "no tilde survived")
  end,

  ["rounds a fractional duration down to whole seconds"] = function()
    local commands = captured({ project = "dotfiles" }, function()
      pns.report({ state = "done", detail = "overseer: build", elapsed = 42.9 })
    end)

    assert(commands[1][11] == "42", "the seconds were floored: " .. commands[1][11])
  end,

  ["refuses a duration that is not a number, and spawns nothing"] = function()
    local commands, notices = captured({}, function()
      local started, reason = pns.report({ state = "done", detail = "overseer: build", elapsed = "soon" })

      assert(started == false, "the report was refused")
      assert(reason:find("elapsed", 1, true), "the reason names the field: " .. reason)
    end)

    assert(#commands == 0, "nothing was spawned")
    assert(#notices == 1, "one warning was raised, not " .. #notices)
    assert(notices[1]:find("elapsed", 1, true), "the warning names the field: " .. notices[1])
  end,

  ["refuses a negative duration"] = function()
    local commands = captured({}, function()
      local started = pns.report({ state = "done", detail = "overseer: build", elapsed = -1 })

      assert(started == false, "the report was refused")
    end)

    assert(#commands == 0, "nothing was spawned")
  end,

  ["refuses a state the engine does not know"] = function()
    local commands, notices = captured({}, function()
      local started, reason = pns.report({ state = "running", detail = "overseer: build", elapsed = 1 })

      assert(started == false, "the report was refused")
      assert(reason:find("state", 1, true), "the reason names the field: " .. reason)
    end)

    assert(#commands == 0, "nothing was spawned")
    assert(#notices == 1, "one warning was raised, not " .. #notices)
  end,

  ["warns once when the binary is not there, however many tasks finish"] = function()
    local missing = "pns-nvim-no-such-binary-77e1"
    local notices = notices_from({ binary = missing }, function()
      local started, reason = pns.report({ state = "done", detail = "overseer: build", elapsed = 1 })

      assert(started == false, "the report was refused")
      assert(reason:find(missing, 1, true), "the reason names the binary: " .. reason)

      pns.report({ state = "done", detail = "overseer: build", elapsed = 1 })
      pns.report({ state = "failed", detail = "overseer: test", elapsed = 1 })
    end)

    assert(#notices == 1, "one warning for three reports, not " .. #notices)
    assert(notices[1]:find(missing, 1, true), "the warning names the binary: " .. notices[1])
  end,

  ["warns once when the engine exits non-zero, however many tasks finish"] = function()
    -- `false` exits 1 whatever it is handed, which is the failing engine this
    -- case is about without needing one.
    local notices = notices_from({ binary = "false" }, function()
      assert(pns.report({ state = "done", detail = "overseer: build", elapsed = 1 }))
      assert(pns.report({ state = "done", detail = "overseer: test", elapsed = 1 }))
    end)

    assert(#notices == 1, "one warning for two failures, not " .. #notices)
    assert(notices[1]:find("exited 1", 1, true), "the warning names the exit code: " .. notices[1])
  end,
}
