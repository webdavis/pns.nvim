local M = {}

M.options = {
  binary = "pns",
  producer = "nvim",
  project = nil,
  pane = nil,
  minimum_version = "0.2.0",
}

local warned_causes = {}

local function warn_once_per_cause(cause, message)
  if warned_causes[cause] then
    return
  end
  warned_causes[cause] = true

  vim.notify("pns.nvim: " .. message, vim.log.levels.WARN)
end

local function warn_from_fast_event(cause, message)
  vim.schedule(function()
    warn_once_per_cause(cause, message)
  end)
end

local function first_line(text)
  return (tostring(text or ""):match("^[^\n]*")) or ""
end

local function finite_nonnegative_seconds(value)
  local seconds = tonumber(value)
  if seconds and seconds >= 0 and seconds < math.huge then
    return seconds
  end

  return nil
end

local function append_unless_empty(argv, flag, value)
  if value == nil or value == "" then
    return
  end

  argv[#argv + 1] = flag
  argv[#argv + 1] = tostring(value)
end

local function send_argv(binary, state, elapsed, report)
  local argv = { binary, "send" }
  append_unless_empty(argv, "--producer", M.options.producer)
  append_unless_empty(argv, "--state", state)
  append_unless_empty(argv, "--project", report.project or M.options.project or vim.fs.basename(vim.uv.cwd() or ""))
  append_unless_empty(argv, "--detail", report.detail)
  append_unless_empty(argv, "--elapsed", math.floor(elapsed) .. "s")
  append_unless_empty(argv, "--pane", report.pane or M.options.pane or vim.env.HERDR_PANE_ID)

  return argv
end

function M.retired_option_warning(options)
  if options.agent == nil then
    return nil
  end

  return ("the agent option is no longer read; set producer = %s instead"):format(vim.inspect(options.agent))
end

function M.setup(opts)
  M.options = vim.tbl_extend("force", M.options, opts or {})

  local retired = M.retired_option_warning(M.options)
  if retired then
    warn_once_per_cause("retired-option", retired)
  end

  require("pns.integrations.xcodebuild").arm()
end

function M.report(report)
  local state = report.state
  if state ~= "done" and state ~= "failed" then
    local reason = ('state must be "done" or "failed", got %s'):format(vim.inspect(state))
    warn_once_per_cause("state:" .. tostring(state), reason)
    return false, reason
  end

  local elapsed = finite_nonnegative_seconds(report.elapsed)
  if not elapsed then
    local reason = ("elapsed must be a number of seconds, got %s"):format(vim.inspect(report.elapsed))
    warn_once_per_cause("elapsed:" .. type(report.elapsed), reason)
    return false, reason
  end

  local binary = vim.fs.normalize(M.options.binary)
  local argv = send_argv(binary, state, elapsed, report)

  local spawned, spawn_error = pcall(vim.system, argv, { text = true }, function(out)
    if out.code ~= 0 then
      local message = ("%s exited %d: %s"):format(binary, out.code, first_line(out.stderr))
      warn_from_fast_event("exit:" .. tostring(out.code), message)
    end
  end)

  if not spawned then
    local reason = ("could not run %s: %s"):format(binary, first_line(spawn_error))
    warn_once_per_cause("spawn:" .. binary, reason)
    return false, reason
  end

  return true
end

return M
