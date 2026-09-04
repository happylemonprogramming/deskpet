# Deskpet

An animated companion that lives on the bottom of your Omarchy desktop and
reacts while your coding agents work. Lean by design: one Quickshell plugin
running inside the shell you already have — no extra processes, no Electron,
no control center. Click-through everywhere except the pet itself.

- Strolls, sits, and lazes while your agent is idle
- Paces while the agent works, frets and waves when it needs your input
- Jumps on success, despairs on errors
- Pet it (click), drag it around (it falls back down with a bounce)
- Speaks in a themed bubble, never echoing agent output

Compatible with the Codex/OpenPets pet package format, so pets from
[OpenPets](https://openpets.dev), [Petdex](https://petdex.dev), and
[Codex Pets](https://codex-pets.net) all work. Ships with
[Yuzu](https://openpets.dev) (an OpenPets Original) as the default pet.

## Install

```bash
omarchy plugin add https://github.com/happylemonprogramming/deskpet.git --enable --yes
```

The pet appears immediately along the bottom of your screen.

## Install more pets

```bash
~/.config/omarchy/plugins/deskpet/bin/install-pet fenne-fox      # OpenPets id
~/.config/omarchy/plugins/deskpet/bin/install-pet <zip-url>      # any pet ZIP
```

Right-click the pet (or `omarchy-shell deskpet next`) to cycle through
installed pets. Pets installed by the OmaPets bar widget
(`~/.config/omapets/pets`) are picked up too.

## Interactions

| Input | Effect |
|---|---|
| Left click | Pet it (hearts) |
| Drag | Carry it anywhere along the bottom strip; it bounces back to the floor |
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

Bind a toggle in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER SHIFT", "Y", "Toggle deskpet", "omarchy-shell deskpet toggle")
```

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
{ "id": "deskpet", "scale": 1.0, "frameIntervalMs": 140, "bottomMargin": 0, "petPath": "" }
```

- `scale` — pet size multiplier (0.4–3.0)
- `frameIntervalMs` — animation speed
- `bottomMargin` — lift the pet above a bottom bar
- `petPath` — pet id (in `~/.local/share/deskpet/pets`) or absolute folder path; empty = bundled Yuzu

## Credits

- Sprite format and reaction taxonomy from the
  [OpenPets](https://github.com/alvinunreal/openpets) /
  [Codex pets](https://github.com/mySebbe/malou-codex-pet) ecosystem.
- Hook event mapping inspired by the MIT-licensed
  [OmaPets](https://github.com/yesmeck/OmaPets) bar widget; deskpet reads its
  status file for zero-config compatibility.
- Default pet: Yuzu, an OpenPets Original. Pets installed from public
  catalogs may be fan-made content; see each catalog's terms.

MIT licensed.
