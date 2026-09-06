-- `:checkhealth pns`
--
-- The plugin and the engine are separate programs on separate release
-- schedules, so the flags one emits and the flags the other accepts can drift.
-- The handshake is here rather than in `report`: a version probe on every
-- finished task would spawn a second process to answer a question whose answer
-- cannot change while Neovim is running, and reporting is the path that has to
-- stay out of the way.

local M = {}

--- How long to wait for the engine to state its version. Generous: this runs
--- when the operator asked for a health report, not on a hot path.
local VERSION_TIMEOUT_MS = 5000

--- The three plugins with a built-in integration, and where each one is named
--- so that it runs.
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

--- Pull a version out of whatever the engine printed.
---
--- Deliberately loose about the shape of the line: `pns 0.2.0`, `0.2.0` and
--- `pns version 0.2` all answer the same question, and pinning the plugin to
--- one spelling of it would turn a cosmetic change in the engine's output into
--- a health failure.
---@param output string?
---@return integer[]? version as major, minor, patch
function M.parse_version(output)
  local major, minor, patch = tostring(output or ""):match("(%d+)%.(%d+)%.?(%d*)")
  if not major then
    return nil
  end

  return { tonumber(major), tonumber(minor), tonumber(patch) or 0 }
end

--- Whether `found` is `wanted` or newer.
---@param found integer[]
---@param wanted integer[]
---@return boolean
function M.at_least(found, wanted)
  for position = 1, math.max(#found, #wanted) do
    local one, other = found[position] or 0, wanted[position] or 0
    if one ~= other then
      return one > other
    end
  end

  return true
end

--- Ask the engine for its version, blocking until it answers.
---
--- Usage text counts: an engine too old to know `--version` prints its help and
--- exits non-zero, which is itself the answer that it predates the handshake.
---@param binary string
---@return integer code
---@return string output stdout, or stderr when stdout was empty
local function probe(binary)
  local result = vim.system({ binary, "--version" }, { text = true }):wait(VERSION_TIMEOUT_MS)
  local output = result.stdout or ""

  if output == "" then
    output = result.stderr or ""
  end

  return result.code, output
end

local function check_binary()
  local options = require("pns").options
  local binary = vim.fs.normalize(options.binary)

  if vim.fn.executable(binary) ~= 1 then
    vim.health.error(("the pns binary %s was not found"):format(binary), {
      "Install pns, or set the binary option to where it lives.",
      'For example require("pns").setup({ binary = "~/.local/libexec/pns/pns" }).',
    })
    return
  end

  vim.health.ok(("the pns binary is %s"):format(binary))

  local wanted = M.parse_version(options.minimum_version)
  if not wanted then
    vim.health.error(("minimum_version is not a version: %s"):format(vim.inspect(options.minimum_version)))
    return
  end

  local spawned, code, output = pcall(probe, binary)
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

function M.check()
  vim.health.start("pns.nvim")
  check_binary()
  check_integrations()
end

return M
