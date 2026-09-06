-- The xcodebuild.nvim integration: four `User` autocommands, two pairs.
--
-- xcodebuild.nvim announces its own progress by firing `User` autocommands
-- (`lua/xcodebuild/broadcasting/events.lua`, verified at commit 633eb71): a
-- build fires `XcodebuildBuildStarted` and `XcodebuildBuildFinished`, a test run
-- fires `XcodebuildTestsStarted` and `XcodebuildTestsFinished`. Listening costs
-- nothing while nothing fires them, which is why this is the one integration
-- that arms itself.
--
-- Running tests fires BOTH pairs: xcodebuild builds for testing first, so a
-- single keystroke produces a build pair and then a test pair. A successful
-- build for testing therefore reports nothing of its own and hands its start
-- time to the test pair, so the operator gets one report covering the wait they
-- actually had rather than two covering half of it each.

local clock = require("pns.clock")

local M = {}

M.GROUP = "pns.nvim.xcodebuild"

--- When the current build and the current test run began, in monotonic
--- nanoseconds, or nil when neither is running.
---
--- A field rather than an upvalue so a test can put it back to a session that
--- has seen nothing yet.
M.started = { build = nil, tests = nil }

--- What xcodebuild hands each autocommand, as the `data` field. A pattern that
--- carries none (`XcodebuildTestsStarted`) arrives with `data` unset.
---@param event table?
---@return table
local function data(event)
  return (event or {}).data or {}
end

---@param started_at integer? nanoseconds, from the matching started event
---@param state "done"|"failed"
---@param detail string
local function report(started_at, state, detail)
  -- A finish with no start behind it. It happens to the first event a freshly
  -- armed session sees, and there is no duration to state for it.
  if not started_at then
    return
  end

  require("pns").report({ state = state, detail = detail, elapsed = clock.since(started_at) })
end

function M.build_started()
  M.started.build = clock.now()

  -- Any build supersedes a test start carried forward from an earlier one, so
  -- a carry that never reached its test run cannot outlive the next build and
  -- inflate that run's duration.
  M.started.tests = nil
end

---@param event table? the autocommand argument, whose `data` carries
---  `forTesting`, `success` and `cancelled`
function M.build_finished(event)
  local finished = data(event)
  local started_at = M.started.build
  M.started.build = nil

  -- The operator stopped it themselves, so they already know.
  if finished.cancelled then
    return
  end

  -- The build half of a test run. It succeeded, so the test run is what the
  -- operator is still waiting for, and its start time is this build's.
  if finished.forTesting and finished.success then
    M.started.tests = started_at
    return
  end

  report(started_at, finished.success and "done" or "failed", "xcodebuild: build")
end

function M.tests_started()
  -- Only when no start was carried forward from the build that produced this
  -- test run, so the reported duration covers that build as well.
  M.started.tests = M.started.tests or clock.now()
end

---@param event table? the autocommand argument, whose `data` carries
---  `passedCount`, `failedCount` and `cancelled`
function M.tests_finished(event)
  local finished = data(event)
  local started_at = M.started.tests
  M.started.tests = nil

  if finished.cancelled then
    return
  end

  report(started_at, (finished.failedCount or 0) == 0 and "done" or "failed", "xcodebuild: tests")
end

--- Listen for xcodebuild's four events, once.
---
--- Re-arming replaces the autocommands rather than adding a second set, because
--- the group is cleared on creation; a second `setup` call therefore does not
--- double every report.
---@return boolean armed false when xcodebuild.nvim is not installed
function M.arm()
  if not pcall(require, "xcodebuild") then
    return false
  end

  local group = vim.api.nvim_create_augroup(M.GROUP, { clear = true })

  local handlers = {
    XcodebuildBuildStarted = M.build_started,
    XcodebuildBuildFinished = M.build_finished,
    XcodebuildTestsStarted = M.tests_started,
    XcodebuildTestsFinished = M.tests_finished,
  }

  for pattern, handler in pairs(handlers) do
    vim.api.nvim_create_autocmd("User", { group = group, pattern = pattern, callback = handler })
  end

  return true
end

return M
