local harness = require("integration_harness")
local xcodebuild = require("pns.integrations.xcodebuild")

local recorded, assert_report = harness.recorded, harness.assert_report

return {
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
}
