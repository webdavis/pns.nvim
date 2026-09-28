local harness = require("integration_harness")
local overseer = require("pns.integrations.overseer")

local recorded, assert_report = harness.recorded, harness.assert_report

--- An overseer component instance, built the way overseer builds one.
local function component()
  return overseer.component.constructor({})
end

return {
  ["overseer reports a successful task as done, timed from its start"] = function()
    local reports = recorded(function(tick)
      local task = component()

      task:on_start()
      tick(35)
      task:on_complete({ name = "just test-unit" }, "SUCCESS")
    end)

    assert_report(reports[1], { state = "done", detail = "overseer: just test-unit", elapsed = 35 })
  end,

  ["overseer reports a failed task as failed"] = function()
    local reports = recorded(function(tick)
      local task = component()

      task:on_start()
      tick(12)
      task:on_complete({ name = "just lint-check" }, "FAILURE")
    end)

    assert_report(reports[1], { state = "failed", detail = "overseer: just lint-check", elapsed = 12 })
  end,

  ["overseer says nothing about a task the operator cancelled"] = function()
    local reports = recorded(function(tick)
      local task = component()

      task:on_start()
      tick(60)
      task:on_complete({ name = "just test" }, "CANCELED")
    end)

    assert(#reports == 0, "a cancelled task reported nothing, not " .. #reports)
  end,

  ["overseer says nothing about a task that completed without starting"] = function()
    local reports = recorded(function()
      component():on_complete({ name = "just test" }, "SUCCESS")
    end)

    assert(#reports == 0, "a task with no start reported nothing, not " .. #reports)
  end,
}
