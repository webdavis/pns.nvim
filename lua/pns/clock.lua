-- The one clock every integration times its work against.
--
-- Monotonic, not wall clock: `os.time` runs backwards when the machine syncs
-- its time or leaves a sleep, and a build that reports a negative duration or
-- an hour-long one because of that is worse than no report at all.

local M = {}

--- Monotonic nanoseconds since an arbitrary point.
---
--- A field rather than a direct call so a test can hand the integrations a
--- clock it controls and pin an exact number of seconds.
M.now = vim.uv.hrtime

--- Seconds between `started_at` and now.
---@param started_at integer nanoseconds, from `now`
---@return number
function M.since(started_at)
  return (M.now() - started_at) / 1e9
end

return M
