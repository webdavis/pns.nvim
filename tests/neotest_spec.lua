local harness = require("integration_harness")
local neotest = require("pns.integrations.neotest")

local reports_requested, assert_report = harness.reports_requested, harness.assert_report

local function client_with_write_only_listeners()
  local assigned = {}
  local listeners = setmetatable({}, {
    __newindex = function(_, event, listener)
      assigned[event] = listener
    end,
    __index = function()
      error("Cannot access existing listeners")
    end,
  })

  return { listeners = listeners }, assigned
end

return {
  ["neotest reports a passing run, named for what was run"] = function()
    local reports = reports_requested(function(advance_seconds)
      local client, listeners = client_with_write_only_listeners()

      neotest.consumer(client)
      listeners.run(1, "/Users/x/project/tests/report_spec.lua", {})
      advance_seconds(21)
      listeners.results(1, { ["one"] = { status = "passed" }, ["two"] = { status = "passed" } }, false)
    end)

    assert_report(reports[1], { state = "done", detail = "neotest: report_spec.lua", elapsed = 21 })
  end,

  ["neotest reports a run with any failure as failed"] = function()
    local reports = reports_requested(function(advance_seconds)
      local client, listeners = client_with_write_only_listeners()

      neotest.consumer(client)
      listeners.run(1, "/Users/x/project/tests/report_spec.lua", {})
      advance_seconds(4)
      listeners.results(1, { ["one"] = { status = "passed" }, ["two"] = { status = "failed" } }, false)
    end)

    assert_report(reports[1], { state = "failed", detail = "neotest: report_spec.lua", elapsed = 4 })
  end,

  ["neotest says nothing while results are still streaming in"] = function()
    local reports = reports_requested(function(advance_seconds)
      local client, listeners = client_with_write_only_listeners()

      neotest.consumer(client)
      listeners.run(1, "/Users/x/project/tests/report_spec.lua", {})
      advance_seconds(4)
      listeners.results(1, { ["one"] = { status = "passed" } }, true)
    end)

    assert(#reports == 0, "a partial result reported nothing, not " .. #reports)
  end,

  ["neotest says nothing about a run that produced no results"] = function()
    local reports = reports_requested(function(advance_seconds)
      local client, listeners = client_with_write_only_listeners()

      neotest.consumer(client)
      listeners.run(1, "/Users/x/project/tests/report_spec.lua", {})
      advance_seconds(3)
      listeners.results(1, {}, false)
    end)

    assert(#reports == 0, "an empty run reported nothing, not " .. #reports)
  end,

  ["neotest says nothing about results with no run behind them"] = function()
    local reports = reports_requested(function()
      local client, listeners = client_with_write_only_listeners()

      neotest.consumer(client)
      listeners.results(1, { ["one"] = { status = "passed" } }, false)
    end)

    assert(#reports == 0, "results with no run reported nothing, not " .. #reports)
  end,

  ["neotest reports each run once, not once per burst of results"] = function()
    local reports = reports_requested(function(advance_seconds)
      local client, listeners = client_with_write_only_listeners()

      neotest.consumer(client)
      listeners.run(1, "/Users/x/project/tests/report_spec.lua", {})
      advance_seconds(4)
      listeners.results(1, { ["one"] = { status = "passed" } }, false)
      listeners.results(1, { ["one"] = { status = "passed" } }, false)
    end)

    assert(#reports == 1, "one report for one run, not " .. #reports)
  end,

  ["neotest counts a skipped test as neither a pass nor a failure"] = function()
    local reports = reports_requested(function(advance_seconds)
      local client, listeners = client_with_write_only_listeners()

      neotest.consumer(client)
      listeners.run(1, "/Users/x/project/tests/report_spec.lua", {})
      advance_seconds(2)
      listeners.results(1, { ["one"] = { status = "skipped" } }, false)
    end)

    assert_report(reports[1], { state = "done", detail = "neotest: report_spec.lua", elapsed = 2 })
  end,
}
