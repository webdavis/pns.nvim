local tests_dir = arg[0]:match("(.*)/") or "."
local project_root = tests_dir .. "/.."
local only = arg[1]

package.path = table.concat({
  project_root .. "/lua/?.lua",
  project_root .. "/lua/?/init.lua",
  tests_dir .. "/?.lua",
  package.path,
}, ";")

local spec_files
if only then
  spec_files = { ("%s/%s.lua"):format(tests_dir, only) }
else
  spec_files = vim.fn.glob(tests_dir .. "/*_spec.lua", false, true)
end

if #spec_files == 0 then
  error("no spec files matched under " .. tests_dir)
end

local failures = 0
local passes = 0

local function write_line_straight_to_stdout(line)
  io.write(line, "\n")
end

local function sorted_case_names(cases)
  local names = {}
  for name in pairs(cases) do
    table.insert(names, name)
  end
  table.sort(names)

  return names
end

local started_at = vim.uv.hrtime()

for _, path in ipairs(spec_files) do
  local spec = path:match("([^/]+)%.lua$")
  local cases = dofile(path)

  if type(cases) ~= "table" or next(cases) == nil then
    error(spec .. " returned no cases")
  end

  for _, name in ipairs(sorted_case_names(cases)) do
    local ok, err = pcall(cases[name])
    if ok then
      passes = passes + 1
      write_line_straight_to_stdout(("ok %s: %s"):format(spec, name))
    else
      failures = failures + 1
      write_line_straight_to_stdout(("FAIL %s: %s: %s"):format(spec, name, err))
    end
  end
end

write_line_straight_to_stdout(
  ("%d passed, %d failed in %.2fs"):format(passes, failures, (vim.uv.hrtime() - started_at) / 1e9)
)

os.exit(failures == 0 and 0 or 1)
