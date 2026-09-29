local M = {}

local VERSION_PROBE_TIMEOUT_MS = 5000

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

function M.parse_version(output)
  local major, minor, patch = tostring(output or ""):match("(%d+)%.(%d+)%.?(%d*)")
  if not major then
    return nil
  end

  return { tonumber(major), tonumber(minor), tonumber(patch) or 0 }
end

function M.at_least(found, wanted)
  for position = 1, math.max(#found, #wanted) do
    local one, other = found[position] or 0, wanted[position] or 0
    if one ~= other then
      return one > other
    end
  end

  return true
end

local function probe_version(binary)
  local result = vim.system({ binary, "--version" }, { text = true }):wait(VERSION_PROBE_TIMEOUT_MS)
  local stdout_or_stderr = result.stdout or ""
  if stdout_or_stderr == "" then
    stdout_or_stderr = result.stderr or ""
  end

  return result.code, stdout_or_stderr
end

local function check_binary()
  local options = require("pns").options
  local binary = vim.fs.normalize(options.binary)

  if vim.fn.executable(binary) ~= 1 then
    vim.health.error(("the pns binary %s was not found"):format(binary), {
      "Install pns, or set the binary option to where it lives.",
      'For example require("pns").setup({ binary = "~/.cargo/bin/pns" }).',
    })
    return
  end

  vim.health.ok(("the pns binary is %s"):format(binary))

  local wanted = M.parse_version(options.minimum_version)
  if not wanted then
    vim.health.error(("minimum_version is not a version: %s"):format(vim.inspect(options.minimum_version)))
    return
  end

  local spawned, code, output = pcall(probe_version, binary)
  if not spawned then
    vim.health.error(("%s could not be run: %s"):format(binary, tostring(code)))
    return
  end

  local found = code == 0 and M.parse_version(output) or nil
  if not found then
    vim.health.error(("%s did not state a version"):format(binary), {
      ("This plugin needs pns %s or newer, which reports one."):format(options.minimum_version),
      "An older pns answers --version with its usage text and a non-zero exit.",
    })
    return
  end

  local version = table.concat(found, ".")
  if M.at_least(found, wanted) then
    vim.health.ok(("pns %s meets the minimum of %s"):format(version, options.minimum_version))
  else
    vim.health.error(("pns %s is older than the minimum of %s"):format(version, options.minimum_version), {
      "Upgrade pns. Reports would be sent with flags this one rejects.",
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

local function check_options()
  local pns = require("pns")
  local retired = pns.retired_option_warning(pns.options)
  if retired then
    vim.health.warn(retired)
  end
end

function M.check()
  vim.health.start("pns.nvim")
  check_options()
  check_binary()
  check_integrations()
end

return M
