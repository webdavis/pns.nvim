-- The three integrations, driven by the events their hosts fire.
--
-- None of the three hosts is installed under `--clean`, and none of them needs
-- to be: an overseer component is a table with a constructor, xcodebuild's edge
-- is four `User` autocommand payloads, and neotest's is two listeners assigned
-- to a client. Each is called here with exactly what its host would pass.
--
-- `pns` itself is replaced in `package.loaded`, so what is pinned is the report
-- each integration asks for rather than a command line the report spec already
-- covers. The clock is replaced too, so a duration is an exact number of
-- seconds instead of however long the test took.

local clock = require("pns.clock")
local neotest = require("pns.integrations.neotest")
local overseer = require("pns.integrations.overseer")
local xcodebuild = require("pns.integrations.xcodebuild")

--- Run `body` with a recording `pns` and a clock that advances only when told.
---
--- `tick` moves the clock on by a whole number of seconds. Everything is put
--- back however `body` ends.
---@return table[] reports
local function recorded(body)
  local real_pns, real_now = package.loaded["pns"], clock.now
  local reports = {}
  local nanoseconds = 0

  xcodebuild.started = { build = nil, tests = nil }
  package.loaded["pns"] = {
    report = function(report)
      reports[#reports + 1] = report
      return true
    end,
  }
  clock.now = function()
    return nanoseconds
  end

  local function tick(seconds)
    nanoseconds = nanoseconds + seconds * 1e9
  end

  local ok, err = pcall(body, tick)

  package.loaded["pns"] = real_pns
  clock.now = real_now
  xcodebuild.started = { build = nil, tests = nil }

  if not ok then
    error(err, 0)
  end

  return reports
end

--- An overseer component instance, built the way overseer builds one.
local function component()
  return overseer.component.constructor({})
end

--- A stand-in for the client neotest hands a consumer. Its real one accepts
--- assignment to `listeners.<event>` and raises on any read, so this one only
--- ever has to record what was assigned.
local function client()
  return { listeners = {} }
end

local function assert_report(actual, expected)
  assert(actual, "a report was made")
  assert(
    vim.deep_equal(actual, expected),
    ("reported %s\nexpected %s"):format(vim.inspect(actual), vim.inspect(expected))
  )
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

  ["xcodebuild reports a plain build from started to finished"] = function()
    local reports = recorded(function(tick)
      xcodebuild.build_started()
      tick(95)
      xcodebuild.build_finished({ data = { forTesting = false, success = true, cancelled = false } })
    end)

    assert_report(reports[1], { state = "done", detail = "xcodebuild: build", elapsed = 95 })
  end,

  ["xcodebuild reports a build that failed as failed"] = function()
    local reports = recorded(function(tick)
      xcodebuild.build_started()
      tick(8)
      xcodebuild.build_finished({ data = { forTesting = false, success = false, cancelled = false } })
    end)

    assert_report(reports[1], { state = "failed", detail = "xcodebuild: build", elapsed = 8 })
  end,

  ["xcodebuild says nothing about a build the operator cancelled"] = function()
    local reports = recorded(function(tick)
      xcodebuild.build_started()
      tick(40)
      xcodebuild.build_finished({ data = { forTesting = true, success = false, cancelled = true } })
    end)

    assert(#reports == 0, "a cancelled build reported nothing, not " .. #reports)
  end,

  ["xcodebuild folds a test run's build into one report covering both"] = function()
    local reports = recorded(function(tick)
      xcodebuild.build_started()
      tick(30)
      xcodebuild.build_finished({ data = { forTesting = true, success = true, cancelled = false } })
      xcodebuild.tests_started()
      tick(12)
      xcodebuild.tests_finished({ data = { passedCount = 40, failedCount = 0, cancelled = false } })
    end)

    assert(#reports == 1, "one report for one keystroke, not " .. #reports)
    assert_report(reports[1], { state = "done", detail = "xcodebuild: tests", elapsed = 42 })
  end,

  ["xcodebuild reports the build when a test run cannot get past it"] = function()
    local reports = recorded(function(tick)
      xcodebuild.build_started()
      tick(30)
      xcodebuild.build_finished({ data = { forTesting = true, success = false, cancelled = false } })
    end)

    assert_report(reports[1], { state = "failed", detail = "xcodebuild: build", elapsed = 30 })
  end,

  ["xcodebuild reports a test run with a failure as failed"] = function()
    local reports = recorded(function(tick)
      xcodebuild.tests_started()
      tick(17)
      xcodebuild.tests_finished({ data = { passedCount = 38, failedCount = 2, cancelled = false } })
    end)

    assert_report(reports[1], { state = "failed", detail = "xcodebuild: tests", elapsed = 17 })
  end,

  ["xcodebuild says nothing about a finish it never saw start"] = function()
    local reports = recorded(function()
      xcodebuild.tests_finished({ data = { passedCount = 1, failedCount = 0, cancelled = false } })
      xcodebuild.build_finished({ data = { forTesting = false, success = true, cancelled = false } })
    end)

    assert(#reports == 0, "an unpaired finish reported nothing, not " .. #reports)
  end,

  ["xcodebuild lets a new build supersede a test start it carried forward"] = function()
    local reports = recorded(function(tick)
      xcodebuild.build_started()
      tick(300)
      xcodebuild.build_finished({ data = { forTesting = true, success = true, cancelled = false } })

      -- The test run never happens. The next build must not hand its stale
      -- start to a later one.
      xcodebuild.build_started()
      tick(5)
      xcodebuild.build_finished({ data = { forTesting = false, success = true, cancelled = false } })

      xcodebuild.tests_started()
      tick(3)
      xcodebuild.tests_finished({ data = { passedCount = 1, failedCount = 0, cancelled = false } })
    end)

    assert(#reports == 2, "the build and the test run, not " .. #reports)
    assert_report(reports[1], { state = "done", detail = "xcodebuild: build", elapsed = 5 })
    assert_report(reports[2], { state = "done", detail = "xcodebuild: tests", elapsed = 3 })
  end,

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
