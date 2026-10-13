local M = {}

local HELP_PROBE_TIMEOUT_MS = 5000

local INTEGRATIONS = {
  {
    module = "overseer",
    wiring = 'add "pns.report" to a component alias in overseer\'s setup',
  },
  {
    module = "xcodebuild",
    wiring = 'armed by require("pns").setup()',
  },
  {
    module = "neotest",
    wiring = 'pass consumers = { pns = require("pns.integrations.neotest").consumer } to neotest.setup',
  },
}

local function flags_sent(binary)
  local argv = require("pns").send_argv(binary, "done", 0, { project = "-", detail = "-", pane = "-" })
  local flags = {}
  for position = 3, #argv, 2 do
    flags[#flags + 1] = argv[position]
  end

  return flags
end

local function probe_send_help(binary)
  local result = vim.system({ binary, "send", "--help" }, { text = true }):wait(HELP_PROBE_TIMEOUT_MS)
  local listed = {}
  for line in (result.stdout or ""):gmatch("[^\n]+") do
    local flag = line:match("^%s*(%-%-[%w%-]+)")
    if flag then
      listed[flag] = true
    end
  end

  return result.code, listed
end

local function check_binary()
  local binary = vim.fs.normalize(require("pns").options.binary)

  if vim.fn.executable(binary) ~= 1 then
    vim.health.error(("the pns binary %s was not found"):format(binary), {
      "Install pns, or set the binary option to where it lives.",
      'For example require("pns").setup({ binary = "~/.cargo/bin/pns" }).',
    })
    return
  end

  vim.health.ok(("the pns binary is %s"):format(binary))

  local spawned, code, listed = pcall(probe_send_help, binary)
  if not spawned then
    vim.health.error(("%s could not be run: %s"):format(binary, tostring(code)))
    return
  end

  if code ~= 0 then
    vim.health.error(("%s send --help exited %d"):format(binary, code), {
      "Upgrade pns. Every report goes through pns send.",
    })
    return
  end

  local sent = flags_sent(binary)
  local missing = vim.tbl_filter(function(flag)
    return not listed[flag]
  end, sent)

  if #missing == 0 then
    vim.health.ok(("pns send takes every flag a report uses: %s"):format(table.concat(sent, " ")))
  else
    vim.health.error(("pns send does not take %s"):format(table.concat(missing, " ")), {
      "Upgrade pns. Until then it refuses every report this plugin sends.",
    })
  end
end

local function check_integrations()
  for _, integration in ipairs(INTEGRATIONS) do
    if pcall(require, integration.module) then
      vim.health.ok(("%s is loadable: %s"):format(integration.module, integration.wiring))
    else
      vim.health.info(("%s is not installed, so its integration is inert"):format(integration.module))
    end
  end
end

function M.check()
  vim.health.start("pns.nvim")
  check_binary()
  check_integrations()
end

return M
