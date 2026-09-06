-- Where overseer looks for a component named `pns.report`.
--
-- overseer resolves a component name by requiring `overseer.component.<name>`
-- off the runtimepath, so a plugin that ships one puts a file here under a
-- directory of its own. The definition itself lives in `pns.integrations.overseer`,
-- which is testable without overseer on the runtimepath at all.

---@type overseer.ComponentFileDefinition
return require("pns.integrations.overseer").component
