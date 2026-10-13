local health = require("pns.health")

local function check_against(script)
  local pns = require("pns")
  local binary = vim.fn.tempname()
  vim.fn.writefile(vim.list_extend({ "#!/bin/sh" }, script), binary)
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
  return vim.fs.normalize(binary), accepted, errors
end

local function send_help_listing(flags)
  local script = { '[ "$1 $2" = "send --help" ] || exit 2', "cat <<'EOF'", "PRODUCER FLAGS" }
  for _, flag in ipairs(flags) do
    script[#script + 1] = ("  %s <value>  what it carries"):format(flag)
  end
  script[#script + 1] = "EOF"

  return script
end

local function assert_equal(found, expected)
  assert(vim.deep_equal(found, expected), ("got %s\nexpected %s"):format(vim.inspect(found), vim.inspect(expected)))
end

return {
  ["accepts a pns whose send help lists every flag a report uses"] = function()
    local _, accepted, errors = check_against(
      send_help_listing({ "--producer", "--state", "--project", "--branch", "--detail", "--pane", "--elapsed" })
    )

    assert_equal(errors, {})
    assert(
      vim.tbl_contains(
        accepted,
        "pns send takes every flag a report uses: --producer --state --project --detail --elapsed --pane"
      ),
      "the health check did not accept the engine: " .. vim.inspect(accepted)
    )
  end,

  ["names each flag the engine's send help leaves out"] = function()
    local _, _, errors = check_against(send_help_listing({ "--producer", "--state", "--project", "--detail" }))

    assert_equal(errors, { "pns send does not take --elapsed --pane" })
  end,

  ["does not take a longer flag for the one a report uses"] = function()
    local _, _, errors =
      check_against(send_help_listing({ "--producer", "--state", "--project-root", "--detail", "--elapsed", "--pane" }))

    assert_equal(errors, { "pns send does not take --project" })
  end,

  ["does not count a flag the help page only mentions in prose"] = function()
    local script = send_help_listing({ "--producer", "--state", "--project", "--detail", "--elapsed" })
    table.insert(script, #script, "  $ pns send --producer ci --pane w1")
    table.insert(script, #script, "Pass --pane to name where a click lands.")
    local _, _, errors = check_against(script)

    assert_equal(errors, { "pns send does not take --pane" })
  end,

  ["reports an engine whose send has no help page"] = function()
    local binary, _, errors = check_against({ "exit 2" })

    assert_equal(errors, { binary .. " send --help exited 2" })
  end,
}
