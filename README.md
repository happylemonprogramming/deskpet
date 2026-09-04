# Deskpet

An animated companion that lives on the bottom of your Omarchy desktop and
reacts while your coding agents work. Lean by design: one Quickshell plugin
running inside the shell you already have — no extra processes, no Electron,
no control center. Click-through everywhere except the pet itself.

- Strolls, sits, and lazes while your agent is idle
- Paces while the agent works, frets and waves when it needs your input
- Jumps on success, despairs on errors
- Pet it (click), drag it around (it falls back down with a bounce)
- Themed speech bubble driven only by the `say` verb — no canned dialog,
  never echoing agent output

Compatible with the Codex/OpenPets pet package format, so pets from
[OpenPets](https://openpets.dev), [Petdex](https://petdex.dev), and
[Codex Pets](https://codex-pets.net) all work.

## Install

```bash
omarchy plugin add https://github.com/happylemonprogramming/deskpet.git --enable --yes
npx -y install-pet cloud-puff
```

No pet art ships with the plugin; the second command installs Cloud Puff
(the default) using the official OpenPets installer. Any pet id from the
[OpenPets gallery](https://openpets.dev) works, and the pet appears along
the bottom of your screen as soon as one is installed.

## Install more pets

```bash
npx -y install-pet ribbit-scout                                  # OpenPets id
~/.config/omarchy/plugins/deskpet/bin/install-pet <id|zip-url>   # no Node needed
```

Right-click the pet (or `omarchy-shell deskpet next`) to cycle through
installed pets. Deskpet finds pets installed by the OpenPets CLI
(`~/.config/OpenPets/pets`), the OmaPets bar widget (`~/.config/omapets/pets`),
and its own installer (`~/.local/share/deskpet/pets`).

## Interactions

| Input | Effect |
|---|---|
| Left click | Pet it (it waves back) |
| Drag | Carry it anywhere on screen; it bounces back down to the floor |
| Right click | Switch to the next installed pet |
| Middle click | Preview the success reaction |

Everything is also keyboard/IPC driven:

```bash
omarchy-shell deskpet toggle        # hide/show
omarchy-shell deskpet next          # switch pet
omarchy-shell deskpet say "hi!"     # make it talk
omarchy-shell deskpet working ""    # drive states manually:
                                    # idle|working|waiting|success|error
```

Bind a toggle in `~/.config/hypr/bindings.lua` (SUPER+ALT+P is free of
conflicts with Omarchy's default keybindings):

```lua
o.bind("SUPER + ALT + P", "Toggle deskpet", "omarchy-shell -q deskpet toggle")
```

Hiding is free: when toggled off, the pet's window surface is destroyed and
every timer in the plugin stops, so it costs zero CPU and zero rendering.

## Agent hooks

Deskpet reacts automatically when your coding agent reports lifecycle events
through `bin/deskpet-hook <event> [agent]` (events: `prompt`, `tool-start`,
`tool-end`, `permission`, `stop`, `error`, `session-start`, `session-end`).
The hook is fire-and-forget and never slows the agent. It also reads the
status file written by [OmaPets](https://github.com/yesmeck/OmaPets) agent
hooks, so if you already ran that installer you are done.

### Claude Code

Merge into `~/.claude/settings.json` (hook path shortened for readability):

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/.config/omarchy/plugins/deskpet/bin/deskpet-hook prompt claude" }] }],
    "PreToolUse":       [{ "hooks": [{ "type": "command", "command": "~/.config/omarchy/plugins/deskpet/bin/deskpet-hook tool-start claude" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "~/.config/omarchy/plugins/deskpet/bin/deskpet-hook permission claude" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "~/.config/omarchy/plugins/deskpet/bin/deskpet-hook stop claude" }] }]
  }
}
```

### opencode

```bash
mkdir -p ~/.config/opencode/plugin
ln -s ~/.config/omarchy/plugins/deskpet/integrations/opencode-deskpet.js \
      ~/.config/opencode/plugin/deskpet.js
```

### Anything else

Any tool that can run a shell command can drive the pet:

```bash
mytool build && omarchy-shell -q deskpet success "" || omarchy-shell -q deskpet error ""
```

## Settings

Stored inline on the plugin entry in `~/.config/omarchy/shell.json`
(hot-reloads on save):

```json
{ "id": "deskpet", "scale": 1.0, "frameIntervalMs": 140, "bottomMargin": 0, "petPath": "cloud-puff" }
```

- `scale` — pet size multiplier (0.4–3.0)
- `frameIntervalMs` — animation speed scale (140 = normal; lower is faster)
- `bottomMargin` — lift the pet above a bottom bar
- `petPath` — pet id (searched across all pets directories) or absolute
  folder path; defaults to `cloud-puff`. If the configured pet is not
  installed, deskpet adopts the first installed pet it finds.

## Uninstall

```bash
omarchy plugin remove deskpet --yes
```

Optional cleanup — deskpet never touches these without you:

```bash
rm -rf ~/.local/share/deskpet              # pets installed by the bundled script
rm -rf ~/.local/state/omarchy/deskpet      # agent status file
rm ~/.config/opencode/plugin/opencode-deskpet.js   # if you linked the opencode integration
```

Pets under `~/.config/OpenPets/pets` belong to the OpenPets CLI and pets
under `~/.config/omapets/pets` to the OmaPets widget; remove those with
their own tools if you no longer want them. If you added Claude Code hooks
from this README, delete those entries from `~/.claude/settings.json`.

## Credits

- Sprite format and reaction taxonomy from the
  [OpenPets](https://github.com/alvinunreal/openpets) /
  [Codex pets](https://github.com/mySebbe/malou-codex-pet) ecosystem.
- Hook event mapping inspired by the MIT-licensed
  [OmaPets](https://github.com/yesmeck/OmaPets) bar widget; deskpet reads its
  status file for zero-config compatibility.
- Pet installs use the official [`install-pet`](https://www.npmjs.com/package/install-pet)
  npm CLI or the bundled script. Pets installed from public catalogs may be
  fan-made content; see each catalog's terms.

MIT licensed.
