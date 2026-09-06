# pns.nvim

Tell [pns](https://github.com/webdavis/pns) when a slow build or test run in Neovim has finished, so
the notification reaches you wherever you went while it ran.

pns is a notification engine. Producers hand it a finished piece of work and it decides what that
deserves: a banner in the terminal, a card in Discord, a push to a phone when you are away from the
desk, and a colour on the lights when the wait was long. A shell already reports to it that way.
This plugin makes the editor a producer too.

The plugin carries no duration thresholds. It states how long the work took and lets pns apply the
one rule it already applies to every other producer, so one program owns the rule instead of
every producer keeping a copy.

## Requirements

- Neovim with `vim.system`, `vim.uv`, `vim.fs` and `vim.health`. Developed and tested on 0.12.5.
- pns, new enough to accept `--elapsed`. See [the version handshake](#the-version-handshake) below.
- Optionally [overseer.nvim](https://github.com/stevearc/overseer.nvim),
  [xcodebuild.nvim](https://github.com/wojciech-kulik/xcodebuild.nvim) and
  [neotest](https://github.com/nvim-neotest/neotest). Each has a built-in integration, and each one
  is inert when its plugin is not installed.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "webdavis/pns.nvim",
  opts = {},
}
```

`opts = {}` is enough. It calls `setup()`, which is what arms the xcodebuild integration.

On a machine where pns is not on `PATH`, name it:

```lua
{
  "webdavis/pns.nvim",
  opts = { binary = "~/.local/libexec/pns/pns" },
}
```

## Options

| Option            | Default   | What it does                                              |
| ----------------- | --------- | --------------------------------------------------------- |
| `binary`          | `"pns"`   | The engine to run. A bare name is found on `PATH`, a path is expanded. |
| `agent`           | `"nvim"`  | The producer name pns records against every report.       |
| `project`         | unset     | Overrides the working directory's basename.               |
| `pane`            | unset     | Overrides `$HERDR_PANE_ID`.                               |
| `minimum_version` | `"0.2.0"` | The oldest pns `:checkhealth pns` accepts.                |

`project` and `pane` are read when a report is made rather than when `setup` runs, so one Neovim
serving several directories still names the right one.

## Integrations

Three tools have a built-in integration. Each reports once, timed by the tool's own start and
finish events, on a monotonic clock so a machine that changes its time mid-build cannot produce a
nonsense duration.

### overseer.nvim

A component. overseer resolves a component by name off the runtimepath, so add `"pns.report"` to the
alias its tasks already use:

```lua
require("overseer").setup({
  component_aliases = {
    default = {
      "on_exit_set_status",
      "on_complete_notify",
      { "on_complete_dispose", require_view = { "SUCCESS", "FAILURE" } },
      "pns.report",
    },
  },
})
```

A task that succeeds reports `done`, one that fails reports `failed`, and one you cancelled reports
nothing, since you were at the keyboard when you cancelled it.

Under lazy.nvim, make `pns.nvim` a dependency of your overseer spec so its runtimepath entry is there
when overseer looks the component up.

### xcodebuild.nvim

There is nothing to wire. `setup()` listens for the four `User` autocommands xcodebuild fires, and
reports a build or a test run when it ends.

Running tests builds first, so one keystroke fires both pairs of events. A successful build for
testing reports nothing of its own and hands its start time to the test run, so you get one report
covering the whole wait rather than two covering half of it each. A build that fails is reported on
its own, because the tests never ran.

### neotest

A consumer, named in neotest's own setup:

```lua
require("neotest").setup({
  consumers = {
    pns = require("pns.integrations.neotest").consumer,
  },
})
```

A run reports `failed` when any result failed and `done` otherwise. A skipped test is neither. Partial
results are ignored while they are still streaming in, so a run is reported once.

## What reaches pns

One process per report, spawned with argv rather than a shell string, and never waited on:

```
pns --agent nvim --state done --project dotfiles --detail "overseer: just test-unit" --elapsed 42 --pane %7
```

`--project` and `--pane` are left out when there is nothing to put in them, since an empty pane id is
a pane pns will never find. The other flags are always present.

The plugin hides neither kind of failure. A binary that is not there, and a binary that exits
non-zero, each raise one `vim.notify` at `WARN` naming the cause. Each cause warns once for the life
of the session, so a broken engine cannot turn every finished task into a fresh notification.

## The version handshake

The plugin and the engine are separate programs on separate release schedules, so the flags one emits
and the flags the other accepts can drift. The plugin declares the oldest pns it works against,
`:checkhealth pns` reads `pns --version` and compares, and a mismatch is reported there rather than
discovered as a rejected flag on every build.

The default minimum is `0.2.0`, which is provisional: at the time of writing pns has not yet released
the version that adds `--elapsed`, and it answers `--version` with its usage text and exit code 2.
Set `minimum_version` to the release that ships the flag once it exists.

The handshake runs only in the health check. Reporting never probes the engine's version, because the
answer cannot change while Neovim is running and the reporting path has to stay out of the way.

## Health

```vim
:checkhealth pns
```

The check reports whether the binary was found, what version it answered with, whether that meets
the minimum, and for each of the three host plugins whether it is installed and how its integration
is wired.

## Lua API

```lua
require("pns").setup(opts)
require("pns").report({
  state = "done",                       -- or "failed"
  detail = "overseer: just test-unit",  -- "<tool>: <task>"
  elapsed = 42,                         -- seconds
  project = "dotfiles",                 -- optional, overrides the default
  pane = "%7",                          -- optional, overrides the default
})
```

`report` returns `true` once the process is on its way. It returns `false` and a reason without
spawning anything when the state is neither `done` nor `failed`, or when the duration is not a number
of seconds. Fractions are rounded down, so anything under a second reports as zero.

Call it from anywhere. A fourth tool needs a call, not a fourth copy of the command line.

## Tests

```bash
nvim --headless --clean -l tests/run.lua
```

`--clean` matters. None of the three host plugins is on the runtimepath, and none needs to be: each
integration is driven by exactly what its host would pass it.

## License

MIT. See [LICENSE](LICENSE).
