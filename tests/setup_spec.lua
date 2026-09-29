local harness = require("spawn_harness")
local pns = require("pns")

local fake_spawns = harness.fake_spawns

return {
  ["names nvim as the producer when the config names none"] = function()
    local commands = fake_spawns({ project = "dotfiles" }, function()
      pns.report({ state = "done", detail = "overseer: build", elapsed = 1 })
    end)

    assert(commands[1][4] == "nvim", "the default producer is nvim: " .. tostring(commands[1][4]))
  end,

  ["warns once and keeps the default producer when setup is given the retired agent option"] = function()
    local commands, notices = fake_spawns({ project = "dotfiles" }, function()
      pns.setup({ agent = "editor" })
      pns.setup({ agent = "editor" })
      pns.report({ state = "done", detail = "overseer: build", elapsed = 1 })
    end)

    assert(commands[1][4] == "nvim", "the retired option was sent as the producer: " .. tostring(commands[1][4]))
    assert(#notices == 1, "one warning for two setups, not " .. #notices)
    assert(notices[1]:find("agent", 1, true), "the warning names the retired option: " .. notices[1])
    assert(notices[1]:find("producer", 1, true), "the warning names its replacement: " .. notices[1])
  end,

  ["raises no warning when setup is given only the options it reads"] = function()
    local _, notices = fake_spawns({}, function()
      pns.setup({ producer = "editor" })
    end)

    assert(#notices == 0, "a current config raised " .. vim.inspect(notices))
  end,
}
