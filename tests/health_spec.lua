-- The version handshake: reading a version out of whatever the engine prints,
-- and deciding whether it is new enough.
--
-- This is the half of `:checkhealth pns` that has a right answer. The rest of
-- the check reports what it found through `vim.health`, which is Neovim's to
-- render.

local health = require("pns.health")

local function assert_version(output, expected)
  local found = health.parse_version(output)

  assert(
    vim.deep_equal(found, expected),
    ("%s parsed as %s\nexpected %s"):format(vim.inspect(output), vim.inspect(found), vim.inspect(expected))
  )
end

return {
  ["accepts pns 0.1.0 with the default minimum"] = function()
    local pns = require("pns")
    local binary = vim.fn.tempname()
    vim.fn.writefile({ "#!/bin/sh", "printf '%s\\n' '0.1.0'" }, binary)
    vim.fn.setfperm(binary, "rwx------")

    local real_options, real_health = pns.options, vim.health
    local accepted, errors = {}, {}
    pns.options = vim.tbl_extend("force", real_options, { binary = binary })
    vim.health = {
      start = function() end,
      info = function() end,
      ok = function(message)
        accepted[#accepted + 1] = message
      end,
      error = function(message)
        errors[#errors + 1] = message
      end,
    }

    local ok, err = pcall(health.check)
    pns.options, vim.health = real_options, real_health
    vim.fn.delete(binary)

    assert(ok, err)
    assert(#errors == 0, table.concat(errors, "\n"))
    assert(
      vim.tbl_contains(accepted, "pns 0.1.0 meets the minimum of 0.1.0"),
      "the health check did not accept the supported engine: " .. vim.inspect(accepted)
    )
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
    -- The case a string comparison gets wrong, and the reason this is not one.
    assert(health.at_least({ 0, 10, 0 }, { 0, 9, 0 }), "0.10.0 is newer than 0.9.0")
    assert(not health.at_least({ 0, 9, 0 }, { 0, 10, 0 }), "0.9.0 is older than 0.10.0")
  end,
}
