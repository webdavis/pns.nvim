-- pns.nvim: tell the pns notification engine that an editor task finished.
--
-- One public call, `report`, which spawns the pns binary with the producer
-- flags pns already understands. The plugin states WHAT happened and HOW LONG
-- it took; pns decides whether that earns a banner, a phone push or the lights.
-- No threshold lives here, on purpose: the shell notifier, the agent hooks and
-- this plugin are all producers of the same engine, and a duration rule copied
-- into each of them is a rule that can disagree with itself.
--
-- The spawn is fire and forget. Nothing here blocks the editor, waits for the
-- engine, or reads its output beyond noticing that it failed.

local M = {}

--- Every option at its default, so the plugin works with no `setup` call.
---
--- `project` and `pane` are nil rather than resolved here: both are read at
--- report time, which is what lets one Neovim serve several directories and
--- still name the right one.
---@class pns.Options
---@field binary string the pns executable, a bare name looked up on PATH or a path
---@field agent string the producer name pns records
---@field project string? overrides the working directory's basename
---@field pane string? overrides $HERDR_PANE_ID
---@field minimum_version string the oldest pns `:checkhealth pns` accepts
M.options = {
  binary = "pns",
  agent = "nvim",
  project = nil,
  pane = nil,
  minimum_version = "0.1.0",
}

--- Causes already reported, so a failing engine warns once instead of once per
--- finished task.
---
--- NOT `vim.notify_once`, which dedupes on the whole message: a message
--- carrying the engine's own stderr line varies between calls, and every
--- variation would arrive as a fresh notification. The cause is what has to be
--- reported once, and the message is free to say more than the cause does.
local warned = {}

---@param cause string
---@param message string
local function warn_once(cause, message)
  if warned[cause] then
    return
  end
  warned[cause] = true

  vim.notify("pns.nvim: " .. message, vim.log.levels.WARN)
end

--- The first line of a raised error or a captured stderr. A `vim.system` raise
--- and a usage dump both run to several lines, which buries the one sentence
--- that says what went wrong.
---@param text string?
---@return string
local function first_line(text)
  return (tostring(text or ""):match("^[^\n]*")) or ""
end

--- Append `flag` and its value, unless the value is absent.
---
--- An absent flag is not the same as an empty one: `--pane ""` reaches pns as a
--- pane id of the empty string, which is a pane it will never find, while
--- leaving the flag out says there is no pane. The rule is one rule for every
--- flag, so a missing project behaves the way a missing pane does.
---@param argv string[]
---@param flag string
---@param value string|number|nil
local function append(argv, flag, value)
  if value == nil or value == "" then
    return
  end

  argv[#argv + 1] = flag
  argv[#argv + 1] = tostring(value)
end

---@param opts pns.Options?
function M.setup(opts)
  M.options = vim.tbl_extend("force", M.options, opts or {})

  -- The one integration that can arm itself. `xcodebuild.nvim` announces its
  -- own progress through `User` autocommands, so listening costs nothing and
  -- needs no cooperation from it. The overseer and neotest integrations are
  -- named in those plugins' own configuration instead, because each of them
  -- decides at its own setup which extensions it runs, and a plugin that armed
  -- itself by writing into their tables would either lose a race or overwrite
  -- a choice the user made.
  require("pns.integrations.xcodebuild").arm()
end

--- Report a finished task to pns.
---
--- Returns false and the reason when the report was refused before any process
--- was started. A refusal and a failed spawn each raise ONE warning per cause
--- for the life of the session.
---@class pns.Report
---@field state "done"|"failed"
---@field detail string what finished, as `"<tool>: <task>"`
---@field elapsed number how long it took, in seconds; pns is told the duration
---@field project string? overrides the option and the working directory
---@field pane string? overrides the option and $HERDR_PANE_ID
---
---@param report pns.Report
---@return boolean started
---@return string? reason
function M.report(report)
  local state = report.state
  if state ~= "done" and state ~= "failed" then
    local reason = ('state must be "done" or "failed", got %s'):format(vim.inspect(state))
    warn_once("state:" .. tostring(state), reason)
    return false, reason
  end

  -- `tonumber` rather than a type test, so a caller holding the seconds as a
  -- string is still understood. Everything else is refused, the two comparisons
  -- covering infinity and NaN as well as a negative duration: NaN fails both.
  local elapsed = tonumber(report.elapsed)
  if not elapsed or not (elapsed >= 0 and elapsed < math.huge) then
    local reason = ("elapsed must be a number of seconds, got %s"):format(vim.inspect(report.elapsed))
    warn_once("elapsed:" .. type(report.elapsed), reason)
    return false, reason
  end

  -- `vim.fs.normalize` is what makes `binary = "~/.local/libexec/pns/pns"`
  -- work: `vim.system` runs the string as given and never expands a tilde, so
  -- an unexpanded path fails to spawn. A bare name passes through untouched and
  -- is looked up on PATH.
  local binary = vim.fs.normalize(M.options.binary)

  -- The flag order pns's own usage lists. Kept fixed so a command line read out
  -- of a log matches the one in the documentation.
  local argv = { binary }
  append(argv, "--producer", M.options.agent)
  append(argv, "--state", state)
  append(argv, "--project", report.project or M.options.project or vim.fs.basename(vim.uv.cwd() or ""))
  append(argv, "--detail", report.detail)
  append(argv, "--elapsed", math.floor(elapsed) .. "s")
  append(argv, "--pane", report.pane or M.options.pane or vim.env.HERDR_PANE_ID)

  -- `vim.system` RAISES on a binary that is not there (measured on 0.12.5:
  -- `ENOENT: no such file or directory (cmd)`), so the spawn is wrapped rather
  -- than checked with `executable()` first. One question asked of the operating
  -- system instead of two, and no window between the check and the spawn.
  local spawned, err = pcall(vim.system, argv, { text = true }, function(out)
    if out.code == 0 then
      return
    end

    -- `vim.system` calls this in a fast event context, where the notification
    -- API is not safe to touch.
    vim.schedule(function()
      warn_once("exit:" .. tostring(out.code), ("%s exited %d: %s"):format(binary, out.code, first_line(out.stderr)))
    end)
  end)

  if not spawned then
    local reason = ("could not run %s: %s"):format(binary, first_line(err))
    warn_once("spawn:" .. binary, reason)
    return false, reason
  end

  return true
end

return M
