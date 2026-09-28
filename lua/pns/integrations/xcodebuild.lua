local clock = require("pns.clock")

local M = {}

M.GROUP = "pns.nvim.xcodebuild"

M.started_at = { build = nil, tests = nil }

local function data_or_empty(event)
  return (event or {}).data or {}
end

local function report_if_started(started_at, state, detail)
  if not started_at then
    return
  end

  require("pns").report({ state = state, detail = detail, elapsed = clock.seconds_since(started_at) })
end

function M.build_started()
  M.started_at.build = clock.monotonic_nanoseconds()
  M.started_at.tests = nil
end

function M.build_finished(event)
  local finished = data_or_empty(event)
  local started_at = M.started_at.build
  M.started_at.build = nil

  if finished.cancelled then
    return
  end

  local test_run_follows = finished.forTesting and finished.success
  if test_run_follows then
    M.started_at.tests = started_at
    return
  end

  report_if_started(started_at, finished.success and "done" or "failed", "xcodebuild: build")
end

function M.tests_started()
  M.started_at.tests = M.started_at.tests or clock.monotonic_nanoseconds()
end

function M.tests_finished(event)
  local finished = data_or_empty(event)
  local started_at = M.started_at.tests
  M.started_at.tests = nil

  if finished.cancelled then
    return
  end

  report_if_started(started_at, (finished.failedCount or 0) == 0 and "done" or "failed", "xcodebuild: tests")
end

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
