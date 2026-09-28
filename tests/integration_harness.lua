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
local xcodebuild = require("pns.integrations.xcodebuild")

--- Run `body` with a recording `pns` and a clock that advances only when told.
---
--- `tick` moves the clock on by a whole number of seconds. Everything is put
--- back however `body` ends.
---@return table[] reports
local function recorded(body)
  local real_pns, real_now = package.loaded["pns"], clock.monotonic_nanoseconds
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

  local function tick(seconds)
    nanoseconds = nanoseconds + seconds * 1e9
  end

  local ok, err = pcall(body, tick)

  package.loaded["pns"] = real_pns
  clock.monotonic_nanoseconds = real_now
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
  recorded = recorded,
  assert_report = assert_report,
}
