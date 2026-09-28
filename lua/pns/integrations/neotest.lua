local clock = require("pns.clock")

local M = {}

function M.tally(results)
  local total, failed = 0, 0

  for _, result in pairs(results or {}) do
    total = total + 1
    if result.status == "failed" then
      failed = failed + 1
    end
  end

  return total, failed
end

function M.consumer(client)
  local started_at, target

  client.listeners.run = function(_, root_id)
    started_at = clock.monotonic_nanoseconds()
    target = root_id
  end

  client.listeners.results = function(_, results, still_streaming)
    if still_streaming then
      return
    end

    local total, failed = M.tally(results)
    if not started_at or total == 0 then
      return
    end

    local elapsed = clock.seconds_since(started_at)
    local name = vim.fs.basename(tostring(target))
    started_at, target = nil, nil

    require("pns").report({
      state = failed > 0 and "failed" or "done",
      detail = "neotest: " .. name,
      elapsed = elapsed,
    })
  end
end

return M
