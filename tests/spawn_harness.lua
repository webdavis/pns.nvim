local pns = require("pns")

local function fake_spawns(options, body)
  local real_system, real_notify, real_options = vim.system, vim.notify, pns.options
  local commands, notices = {}, {}

  pns.options = vim.tbl_extend("force", vim.deepcopy(real_options), options or {})
  vim.system = function(cmd)
    commands[#commands + 1] = cmd
    return {}
  end
  vim.notify = function(message)
    notices[#notices + 1] = message
  end

  local ok, err = pcall(body)

  vim.system, vim.notify, pns.options = real_system, real_notify, real_options

  if not ok then
    error(err, 0)
  end

  return commands, notices
end

local function wait_for_a_notice_from_the_event_loop(notices)
  vim.wait(3000, function()
    return #notices > 0
  end)
end

local function give_a_second_notice_time_to_arrive()
  vim.wait(150)
end

local function notices_from_real_spawns(options, body)
  local real_notify, real_options = vim.notify, pns.options
  local notices = {}

  pns.options = vim.tbl_extend("force", vim.deepcopy(real_options), options or {})
  vim.notify = function(message)
    notices[#notices + 1] = message
  end

  local ok, err = pcall(body)

  wait_for_a_notice_from_the_event_loop(notices)
  give_a_second_notice_time_to_arrive()

  vim.notify, pns.options = real_notify, real_options

  if not ok then
    error(err, 0)
  end

  return notices
end

local function assert_command(actual, expected)
  assert(
    vim.deep_equal(actual, expected),
    ("argv was %s\nexpected  %s"):format(vim.inspect(actual), vim.inspect(expected))
  )
end

return {
  fake_spawns = fake_spawns,
  notices_from_real_spawns = notices_from_real_spawns,
  assert_command = assert_command,
}
