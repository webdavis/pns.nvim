local health = require("pns.health")

local function assert_version(output, expected)
  local found = health.parse_version(output)

  assert(
    vim.deep_equal(found, expected),
    ("%s parsed as %s\nexpected %s"):format(vim.inspect(output), vim.inspect(found), vim.inspect(expected))
  )
end

local MISSING_BINARY = "pns-nvim-no-such-binary-77e1"

local function health_messages(options)
  local pns = require("pns")
  local real_options, real_health = pns.options, vim.health
  local messages = { ok = {}, warn = {}, error = {}, info = {} }

  pns.options = vim.tbl_extend("force", real_options, options)
  vim.health = { start = function() end }
  for level, recorded in pairs(messages) do
    vim.health[level] = function(message)
      recorded[#recorded + 1] = message
    end
  end

  local ok, err = pcall(health.check)

  pns.options, vim.health = real_options, real_health

  if not ok then
    error(err, 0)
  end

  return messages
end

return {
  ["accepts pns 0.2.0 with the default minimum"] = function()
    local binary = vim.fn.tempname()
    vim.fn.writefile({ "#!/bin/sh", "printf '%s\\n' '0.2.0'" }, binary)
    vim.fn.setfperm(binary, "rwx------")

    local ok, messages = pcall(health_messages, { binary = binary })
    vim.fn.delete(binary)

    assert(ok, messages)
    assert(#messages.error == 0, table.concat(messages.error, "\n"))
    assert(
      vim.tbl_contains(messages.ok, "pns 0.2.0 meets the minimum of 0.2.0"),
      "the health check did not accept the supported engine: " .. vim.inspect(messages.ok)
    )
  end,

  ["warns by name when the config still sets the retired agent option"] = function()
    local messages = health_messages({ binary = MISSING_BINARY, agent = "editor" })

    assert(#messages.warn == 1, "one warning, not " .. vim.inspect(messages.warn))
    assert(messages.warn[1]:find("agent", 1, true), "the warning names the retired option: " .. messages.warn[1])
    assert(messages.warn[1]:find("producer", 1, true), "the warning names its replacement: " .. messages.warn[1])
  end,

  ["raises no warning when the config sets only the options it reads"] = function()
    local messages = health_messages({ binary = MISSING_BINARY, producer = "editor" })

    assert(#messages.warn == 0, "a current config raised " .. vim.inspect(messages.warn))
  end,

  ["reads a version however the engine spells the line around it"] = function()
    assert_version("0.2.0", { 0, 2, 0 })
    assert_version("pns 0.2.0", { 0, 2, 0 })
    assert_version("pns version 1.10.3\n", { 1, 10, 3 })
  end,

  ["treats a missing patch number as zero"] = function()
    assert_version("pns 0.2", { 0, 2, 0 })
  end,

  ["reads no version out of a line that has none"] = function()
    assert_version("pns: usage:\n  pns [<producer flags>]", nil)
    assert_version("", nil)
    assert_version(nil, nil)
  end,

  ["accepts an engine newer than the minimum"] = function()
    assert(health.at_least({ 0, 3, 0 }, { 0, 2, 0 }), "0.3.0 is newer than 0.2.0")
    assert(health.at_least({ 1, 0, 0 }, { 0, 9, 9 }), "1.0.0 is newer than 0.9.9")
    assert(health.at_least({ 0, 2, 1 }, { 0, 2, 0 }), "0.2.1 is newer than 0.2.0")
  end,

  ["accepts an engine exactly at the minimum"] = function()
    assert(health.at_least({ 0, 2, 0 }, { 0, 2, 0 }), "0.2.0 meets 0.2.0")
  end,

  ["refuses an engine older than the minimum"] = function()
    assert(not health.at_least({ 0, 1, 0 }, { 0, 2, 0 }), "0.1.0 is older than 0.2.0")
    assert(not health.at_least({ 0, 2, 0 }, { 0, 2, 1 }), "0.2.0 is older than 0.2.1")
    assert(not health.at_least({ 0, 9, 9 }, { 1, 0, 0 }), "0.9.9 is older than 1.0.0")
  end,

  ["compares each number rather than the text around it"] = function()
    assert(health.at_least({ 0, 10, 0 }, { 0, 9, 0 }), "0.10.0 is newer than 0.9.0")
    assert(not health.at_least({ 0, 9, 0 }, { 0, 10, 0 }), "0.9.0 is older than 0.10.0")
  end,
}
