// Deskpet integration for opencode.
//
// Install: copy (or symlink) this file into ~/.config/opencode/plugin/
// It forwards agent lifecycle events to the deskpet Omarchy shell plugin
// via its hook script. Fire-and-forget: failures never affect the agent.

const HOOK = `${process.env.HOME}/.config/omarchy/plugins/deskpet/bin/deskpet-hook`

async function send(event) {
  try {
    Bun.spawn([HOOK, event, "opencode"], {
      stdin: "ignore",
      stdout: "ignore",
      stderr: "ignore",
    }).unref()
  } catch {}
}

export const DeskpetPlugin = async () => ({
  "tool.execute.before": async () => send("tool-start"),
  "tool.execute.after": async () => send("tool-end"),
  event: async ({ event }) => {
    if (event.type === "session.idle") await send("stop")
    else if (event.type === "session.error") await send("error")
    else if (event.type === "permission.updated") await send("permission")
  },
})
