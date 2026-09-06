-- The overseer integration: one component that reports a task's completion.
--
-- overseer finds components by requiring them out of its own `overseer.component`
-- namespace off the runtimepath, which is the extension point its guide
-- documents. `lua/overseer/component/pns/report.lua` in this repository is that
-- file, and it hands back the definition below; the definition lives here so it
-- can be built and driven with no overseer installed at all.
--
-- Nothing arms this. A component runs when a task carries it, which is a choice
-- made in overseer's own setup, where the component alias lives.

local clock = require("pns.clock")

local M = {}

--- overseer's terminal statuses, and what each one means to pns.
---
--- `CANCELED` is deliberately absent. The operator who stopped a task is at the
--- keyboard by definition, so telling them it stopped is a notification about
--- their own keystroke.
M.STATES = {
  SUCCESS = "done",
  FAILURE = "failed",
}

---@type overseer.ComponentFileDefinition
M.component = {
  desc = "Report the task's completion to pns",
  constructor = function()
    return {
      started_at = nil,

      on_start = function(self)
        self.started_at = clock.now()
      end,

      on_complete = function(self, task, status)
        local started_at = self.started_at
        self.started_at = nil

        local state = M.STATES[status]

        -- A task that reached a terminal status without ever starting has no
        -- duration to state, and pns's tier rule is entirely about duration.
        if not state or not started_at then
          return
        end

        require("pns").report({
          state = state,
          detail = "overseer: " .. tostring(task.name),
          elapsed = clock.since(started_at),
        })
      end,
    }
  end,
}

return M
