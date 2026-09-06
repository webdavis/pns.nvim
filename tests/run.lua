-- Headless Lua test runner.
--
-- Usage: nvim --headless --clean -l tests/run.lua [<name>_spec]
--
-- `--clean` keeps every plugin out, which is the point: this plugin has to hold
-- with overseer, xcodebuild.nvim and neotest all absent, and each integration is
-- driven here by the events its host would have fired rather than by the host.
-- A spec file returns a table of `["what it does"] = function() ... end` cases
-- and asserts with plain `assert`. No plenary, no busted.

local tests_dir = arg[0]:match("(.*)/") or "."
local project_root = tests_dir .. "/.."
local only = arg[1]

package.path = ("%s/lua/?.lua;%s/lua/?/init.lua;%s"):format(project_root, project_root, package.path)

local spec_files
if only then
  spec_files = { ("%s/%s.lua"):format(tests_dir, only) }
else
  spec_files = vim.fn.glob(tests_dir .. "/*_spec.lua", false, true)
end

-- A run that found nothing to do would otherwise exit 0 and read as a pass.
if #spec_files == 0 then
  error("no spec files matched under " .. tests_dir)
end

local failures = 0
local passes = 0

-- Not `print`: under `nvim -l` that routes through the message system, which
-- swallows the newline after a line exactly `columns` wide and leaves the final
-- line unterminated. `io.write` goes straight to stdout.
local function report(line)
  io.write(line, "\n")
end

local started_at = vim.uv.hrtime()

for _, path in ipairs(spec_files) do
  local spec = path:match("([^/]+)%.lua$")
  local cases = dofile(path)

  -- A spec with no cases reports nothing and adds nothing to the failure count,
  -- so gutting one would leave the run green and silent.
  if type(cases) ~= "table" or next(cases) == nil then
    error(spec .. " returned no cases")
  end

  -- Sorted, so a run reports its cases in the same order every time.
  local names = {}
  for name in pairs(cases) do
    table.insert(names, name)
  end
  table.sort(names)

  for _, name in ipairs(names) do
    local ok, err = pcall(cases[name])
    if ok then
      passes = passes + 1
      report(("ok %s: %s"):format(spec, name))
    else
      failures = failures + 1
      report(("FAIL %s: %s: %s"):format(spec, name, err))
    end
  end
end

report(("%d passed, %d failed in %.2fs"):format(passes, failures, (vim.uv.hrtime() - started_at) / 1e9))

os.exit(failures == 0 and 0 or 1)
