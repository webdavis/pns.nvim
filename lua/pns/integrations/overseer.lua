local clock = require("pns.clock")

local M = {}

M.PNS_STATE_BY_STATUS = {
  SUCCESS = "done",
  FAILURE = "failed",
}

M.component = {
  desc = "Report the task's completion to pns",
  constructor = function()
    return {
      started_at = nil,

      on_start = function(self)
        self.started_at = clock.monotonic_nanoseconds()
      end,

      on_complete = function(self, task, status)
        local started_at = self.started_at
        self.started_at = nil

        local state = M.PNS_STATE_BY_STATUS[status]
        if not state or not started_at then
          return
        end

        require("pns").report({
          state = state,
          detail = "overseer: " .. tostring(task.name),
          elapsed = clock.seconds_since(started_at),
        })
      end,
    }
  end,
}

return M
