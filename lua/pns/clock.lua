local M = {}

M.monotonic_nanoseconds = vim.uv.hrtime

function M.seconds_since(started_at_nanoseconds)
  return (M.monotonic_nanoseconds() - started_at_nanoseconds) / 1e9
end

return M
