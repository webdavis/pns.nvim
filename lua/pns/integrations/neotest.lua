-- The neotest integration: a consumer that watches one run from start to
-- results.
--
-- neotest hands every consumer its client and lets the consumer assign event
-- listeners (`lua/neotest/client/events/init.lua`, verified at commit 27bf921).
-- `run` fires when a run begins and names what is being run; `results` fires
-- with a map of position id to result, and with `partial` set while results are
-- still streaming in.
--
-- The consumer is named in neotest's own `setup` rather than armed from here.
-- neotest builds its client inside that call and reads its consumer list at the
-- same moment, so a plugin that wrote itself in would be racing a table it does
-- not own, and losing that race would fail silently.

local clock = require("pns.clock")

local M = {}

--- Whether any result in `results` failed.
---
--- A skipped test is not a failure and an empty run is not a success worth
--- reporting, so the count of results is answered alongside it.
---@param results table<string, table>
---@return integer total
---@return integer failed
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

--- neotest's consumer contract: a function given the client, called once from
--- `neotest.setup`.
---
--- The listener table only accepts assignment. Reading a listener back raises
--- inside neotest's own wrapper, so the run's start is remembered here rather
--- than asked for later.
---@param client table
function M.consumer(client)
  local started_at, target

  client.listeners.run = function(_, root_id)
    started_at = clock.now()
    target = root_id
  end

  client.listeners.results = function(_, results, partial)
    -- Results still streaming in. The run is not over, and reporting on it
    -- would be reporting on a run that is still going.
    if partial then
      return
    end

    local total, failed = M.tally(results)

    -- Results with no run behind them, or a run that produced none. Neither
    -- has a duration to state, which is the whole of what pns tiers on.
    if not started_at or total == 0 then
      return
    end

    local elapsed = clock.since(started_at)
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
