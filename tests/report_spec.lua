local pns = require("pns")

local function fake_spawns(options, body)
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

local function wait_for_a_notice_from_the_event_loop(notices)
  vim.wait(3000, function()
    return #notices > 0
  end)
end

local function give_a_second_notice_time_to_arrive()
  vim.wait(150)
end

local function notices_from_real_spawns(options, body)
  local real_notify, real_options = vim.notify, pns.options
  local notices = {}

  pns.options = vim.tbl_extend("force", vim.deepcopy(real_options), options or {})
  vim.notify = function(message)
    notices[#notices + 1] = message
  end

  local ok, err = pcall(body)

  wait_for_a_notice_from_the_event_loop(notices)
  give_a_second_notice_time_to_arrive()

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

local function with_herdr_pane_id(pane, body)
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
    local commands = fake_spawns({ binary = "pns", agent = "nvim", project = "dotfiles", pane = "%7" }, function()
      pns.report({ state = "done", detail = "overseer: build", elapsed = 42 })
    end)

    assert(#commands == 1, "one process was spawned")
    assert_command(commands[1], {
      "pns",
      "send",
      "--producer",
      "nvim",
      "--state",
      "done",
      "--project",
      "dotfiles",
      "--detail",
      "overseer: build",
      "--elapsed",
      "42s",
      "--pane",
      "%7",
    })
  end,

  ["carries a failure through as the failed state"] = function()
    local commands = fake_spawns({ project = "dotfiles", pane = "%7" }, function()
      pns.report({ state = "failed", detail = "neotest: init_spec.lua", elapsed = 7 })
    end)

    assert_command(commands[1], {
      "pns",
      "send",
      "--producer",
      "nvim",
      "--state",
      "failed",
      "--project",
      "dotfiles",
      "--detail",
      "neotest: init_spec.lua",
      "--elapsed",
      "7s",
      "--pane",
      "%7",
    })
  end,

  ["leaves out the pane and the project when there are none"] = function()
    with_herdr_pane_id(nil, function()
      local commands = fake_spawns({ project = "" }, function()
        pns.report({ state = "done", detail = "overseer: build", elapsed = 42 })
      end)

      assert_command(commands[1], {
        "pns",
        "send",
        "--producer",
        "nvim",
        "--state",
        "done",
        "--detail",
        "overseer: build",
        "--elapsed",
        "42s",
      })
    end)
  end,

  ["defaults the project to the working directory and the pane to the environment"] = function()
    with_herdr_pane_id("%12", function()
      local commands = fake_spawns({}, function()
        pns.report({ state = "done", detail = "overseer: build", elapsed = 1 })
      end)

      local argv = commands[1]
      assert(argv[8] == vim.fs.basename(vim.uv.cwd()), "the project is the working directory's name: " .. argv[8])
      assert(argv[14] == "%12", "the pane came from HERDR_PANE_ID: " .. tostring(argv[14]))
    end)
  end,

  ["prefers the report's own project and pane over every default"] = function()
    with_herdr_pane_id("%12", function()
      local commands = fake_spawns({ project = "from-setup", pane = "%99" }, function()
        pns.report({ state = "done", detail = "overseer: build", elapsed = 1, project = "from-call", pane = "%1" })
      end)

      local argv = commands[1]
      assert(argv[8] == "from-call", "the call's project won: " .. argv[8])
      assert(argv[14] == "%1", "the call's pane won: " .. argv[14])
    end)
  end,

  ["expands a tilde in the binary, which vim.system never would"] = function()
    local commands = fake_spawns({ binary = "~/.local/libexec/pns/pns", project = "dotfiles" }, function()
      pns.report({ state = "done", detail = "overseer: build", elapsed = 1 })
    end)

    assert(
      commands[1][1] == vim.fs.normalize("~/.local/libexec/pns/pns"),
      "the binary was expanded: " .. commands[1][1]
    )
    assert(not commands[1][1]:find("~", 1, true), "no tilde survived")
  end,

  ["rounds a fractional duration down to whole seconds"] = function()
    local commands = fake_spawns({ project = "dotfiles" }, function()
      pns.report({ state = "done", detail = "overseer: build", elapsed = 42.9 })
    end)

    assert(commands[1][12] == "42s", "the seconds were floored: " .. commands[1][12])
  end,

  ["refuses a duration that is not a number, and spawns nothing"] = function()
    local commands, notices = fake_spawns({}, function()
      local started, reason = pns.report({ state = "done", detail = "overseer: build", elapsed = "soon" })

      assert(started == false, "the report was refused")
      assert(reason:find("elapsed", 1, true), "the reason names the field: " .. reason)
    end)

    assert(#commands == 0, "nothing was spawned")
    assert(#notices == 1, "one warning was raised, not " .. #notices)
    assert(notices[1]:find("elapsed", 1, true), "the warning names the field: " .. notices[1])
  end,

  ["accepts a duration given as a string of seconds"] = function()
    local commands = fake_spawns({ project = "dotfiles" }, function()
      assert(pns.report({ state = "done", detail = "overseer: build", elapsed = "42" }))
    end)

    assert(commands[1][12] == "42s", "the string was read as seconds: " .. tostring(commands[1][12]))
  end,

  ["refuses an infinite or not-a-number duration"] = function()
    local commands = fake_spawns({}, function()
      for _, elapsed in ipairs({ math.huge, "inf", 0 / 0 }) do
        local started = pns.report({ state = "done", detail = "overseer: build", elapsed = elapsed })

        assert(started == false, "the report was refused for " .. tostring(elapsed))
      end
    end)

    assert(#commands == 0, "nothing was spawned")
  end,

  ["warns once per exit code even when the engine's message differs each time"] = function()
    local binary = vim.fn.tempname()
    vim.fn.writefile({ "#!/bin/sh", 'echo "engine failed in process $$" >&2', "exit 7" }, binary)
    vim.fn.setfperm(binary, "rwx------")

    local ok, notices = pcall(notices_from_real_spawns, { binary = binary }, function()
      assert(pns.report({ state = "done", detail = "overseer: build", elapsed = 1 }))
      assert(pns.report({ state = "done", detail = "overseer: test", elapsed = 1 }))
    end)
    vim.fn.delete(binary)

    assert(ok, notices)
    assert(#notices == 1, "one warning for two differently worded failures, not " .. #notices)
    assert(notices[1]:find("exited 7", 1, true), "the warning names the exit code: " .. notices[1])
  end,

  ["refuses a negative duration"] = function()
    local commands = fake_spawns({}, function()
      local started = pns.report({ state = "done", detail = "overseer: build", elapsed = -1 })

      assert(started == false, "the report was refused")
    end)

    assert(#commands == 0, "nothing was spawned")
  end,

  ["refuses a state the engine does not know"] = function()
    local commands, notices = fake_spawns({}, function()
      local started, reason = pns.report({ state = "running", detail = "overseer: build", elapsed = 1 })

      assert(started == false, "the report was refused")
      assert(reason:find("state", 1, true), "the reason names the field: " .. reason)
    end)

    assert(#commands == 0, "nothing was spawned")
    assert(#notices == 1, "one warning was raised, not " .. #notices)
  end,

  ["warns once when the binary is not there, however many tasks finish"] = function()
    local missing = "pns-nvim-no-such-binary-77e1"
    local notices = notices_from_real_spawns({ binary = missing }, function()
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
    local binary_that_always_exits_1 = "false"
    local notices = notices_from_real_spawns({ binary = binary_that_always_exits_1 }, function()
      assert(pns.report({ state = "done", detail = "overseer: build", elapsed = 1 }))
      assert(pns.report({ state = "done", detail = "overseer: test", elapsed = 1 }))
    end)

    assert(#notices == 1, "one warning for two failures, not " .. #notices)
    assert(notices[1]:find("exited 1", 1, true), "the warning names the exit code: " .. notices[1])
  end,
}
