local clock = require("pns.clock")
local xcodebuild = require("pns.integrations.xcodebuild")

local function reports_requested(body)
  local real_pns, real_clock = package.loaded["pns"], clock.monotonic_nanoseconds
  local reports = {}
  local nanoseconds = 0

  xcodebuild.started_at = { build = nil, tests = nil }
  package.loaded["pns"] = {
    report = function(report)
      reports[#reports + 1] = report
      return true
    end,
  }
  clock.monotonic_nanoseconds = function()
    return nanoseconds
  end

  local function advance_seconds(seconds)
    nanoseconds = nanoseconds + seconds * 1e9
  end

  local ok, err = pcall(body, advance_seconds)

  package.loaded["pns"] = real_pns
  clock.monotonic_nanoseconds = real_clock
  xcodebuild.started_at = { build = nil, tests = nil }

  if not ok then
    error(err, 0)
  end

  return reports
end

local function assert_report(actual, expected)
  assert(actual, "a report was made")
  assert(
    vim.deep_equal(actual, expected),
    ("reported %s\nexpected %s"):format(vim.inspect(actual), vim.inspect(expected))
  )
end

return {
  reports_requested = reports_requested,
  assert_report = assert_report,
}
