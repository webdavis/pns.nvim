local harness = require("integration_harness")
local neotest = require("pns.integrations.neotest")

local recorded, assert_report = harness.recorded, harness.assert_report

--- A stand-in for the client neotest hands a consumer. Its real one accepts
--- assignment to `listeners.<event>` and raises on any read, so this one only
--- ever has to record what was assigned.
local function client()
  return { listeners = {} }
end

return {
  ["neotest reports a passing run, named for what was run"] = function()
    local reports = recorded(function(tick)
      local events = client()

      neotest.consumer(events)
      events.listeners.run(1, "/Users/x/project/tests/report_spec.lua", {})
      tick(21)
      events.listeners.results(1, { ["one"] = { status = "passed" }, ["two"] = { status = "passed" } }, false)
    end)

    assert_report(reports[1], { state = "done", detail = "neotest: report_spec.lua", elapsed = 21 })
  end,

  ["neotest reports a run with any failure as failed"] = function()
    local reports = recorded(function(tick)
      local events = client()

      neotest.consumer(events)
      events.listeners.run(1, "/Users/x/project/tests/report_spec.lua", {})
      tick(4)
      events.listeners.results(1, { ["one"] = { status = "passed" }, ["two"] = { status = "failed" } }, false)
    end)

    assert_report(reports[1], { state = "failed", detail = "neotest: report_spec.lua", elapsed = 4 })
  end,

  ["neotest says nothing while results are still streaming in"] = function()
    local reports = recorded(function(tick)
      local events = client()

      neotest.consumer(events)
      events.listeners.run(1, "/Users/x/project/tests/report_spec.lua", {})
      tick(4)
      events.listeners.results(1, { ["one"] = { status = "passed" } }, true)
    end)

    assert(#reports == 0, "a partial result reported nothing, not " .. #reports)
  end,

  ["neotest says nothing about results with no run behind them"] = function()
    local reports = recorded(function()
      local events = client()

      neotest.consumer(events)
      events.listeners.results(1, { ["one"] = { status = "passed" } }, false)
    end)

    assert(#reports == 0, "results with no run reported nothing, not " .. #reports)
  end,

  ["neotest reports each run once, not once per burst of results"] = function()
    local reports = recorded(function(tick)
      local events = client()

      neotest.consumer(events)
      events.listeners.run(1, "/Users/x/project/tests/report_spec.lua", {})
      tick(4)
      events.listeners.results(1, { ["one"] = { status = "passed" } }, false)
      events.listeners.results(1, { ["one"] = { status = "passed" } }, false)
    end)

    assert(#reports == 1, "one report for one run, not " .. #reports)
  end,

  ["neotest counts a skipped test as neither a pass nor a failure"] = function()
    local reports = recorded(function(tick)
      local events = client()

      neotest.consumer(events)
      events.listeners.run(1, "/Users/x/project/tests/report_spec.lua", {})
      tick(2)
      events.listeners.results(1, { ["one"] = { status = "skipped" } }, false)
    end)

    assert_report(reports[1], { state = "done", detail = "neotest: report_spec.lua", elapsed = 2 })
  end,
}
