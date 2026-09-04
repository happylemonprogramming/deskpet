import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "PetModel.js" as PetModel

// Deskpet: a desktop companion that lives on a click-through layer-shell
// strip along the bottom of the screen. Only the sprite itself is an input
// region, so the pet never eats a click meant for a window underneath it.
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell
  property var manifest
  property var pluginRegistry
  property var barWidgetRegistry
  property string omarchyPath

  // ------------------------------------------------------------- settings

  // Panel plugins keep their settings inline on their `plugins[]` entry in
  // shell.json; rebinding through shell.shellConfig makes edits hot-reload.
  readonly property var entrySettings: {
    var cfg = shell && shell.shellConfig ? shell.shellConfig : null
    var arr = cfg && Array.isArray(cfg.plugins) ? cfg.plugins : []
    for (var i = 0; i < arr.length; i++)
      if (arr[i] && String(arr[i].id) === "deskpet") return arr[i]
    return ({})
  }
  function setting(key, fallback) {
    var value = entrySettings[key]
    return value === undefined ? fallback : value
  }

  readonly property real petScale: Math.max(0.4, Math.min(3, Number(setting("scale", 1.0))))
  readonly property int frameInterval: Math.max(60, Number(setting("frameIntervalMs", 140)))
  readonly property int bottomMargin: Math.max(0, Number(setting("bottomMargin", 0)))
  readonly property string configuredPet: String(setting("petPath", "cloud-puff"))
  readonly property bool startVisible: setting("visible", true) !== false

  // ------------------------------------------------------------ pet package

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || home + "/.local/share"
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
  readonly property string petsHome: dataHome + "/deskpet/pets"
  // Pets installed by the OmaPets bar widget and by the official OpenPets
  // CLI (`npx -y install-pet <id>`) load too; all share the sprite format.
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
  readonly property string compatPetsHome: configHome + "/omapets/pets"
  readonly property string openPetsHome: configHome + "/OpenPets/pets"

  function filePath(url) {
    return decodeURIComponent(String(url || "").replace(/^file:\/\//, ""))
  }
  function expandHome(path) {
    var value = String(path || "")
    if (value === "~") return home
    if (value.indexOf("~/") === 0) return home + value.slice(1)
    return value
  }

  // No pet ships with the plugin. The scanner is the single source of truth:
  // it lists every installed pet (dir, name, spritesheet, atlas version)
  // across the pets directories in priority order (ours, OmaPets', the
  // OpenPets CLI's). The configured pet is matched against that list; a
  // missing pet falls back to the first installed one.
  property var petRecords: []
  property string appliedPetDir: ""

  property bool petAvailable: false
  property string petName: ""
  property int atlasRows: 9
  property url spritesheetUrl: ""

  onConfiguredPetChanged: scanPets("apply")

  function applyPetRecord(rec) {
    if (!rec) {
      petAvailable = false
      petName = ""
      spritesheetUrl = ""
      appliedPetDir = ""
      return
    }
    var sheet = String(rec.sheet || "spritesheet.webp")
    if (sheet.indexOf("..") >= 0 || sheet.charAt(0) === "/") {
      console.warn("deskpet: spritesheetPath must stay inside the pet folder:", rec.dir)
      applyPetRecord(null)
      return
    }
    appliedPetDir = rec.dir
    petName = rec.name
    atlasRows = rec.version >= 2 ? 11 : 9
    spritesheetUrl = "file://" + rec.dir + "/" + sheet
    petAvailable = true
  }

  // The record the current settings ask for; adopts the first installed pet
  // when petPath is empty or points at something not installed.
  function desiredPetRecord() {
    var records = petRecords
    if (records.length === 0) return null
    var p = expandHome(configuredPet).replace(/\/$/, "")
    if (p !== "") {
      for (var i = 0; i < records.length; i++) {
        if (records[i].dir === p
            || (p.indexOf("/") < 0 && records[i].dir.split("/").pop() === p))
          return records[i]
      }
      console.info("deskpet: configured pet not installed, adopting", records[0].dir)
    }
    return records[0]
  }

  // ------------------------------------------------------------ pet state

  property bool petVisible: startVisible
  property string agentState: "idle"
  property string agentDetail: ""
  property double lastStatusEpoch: 0
  property string action: "stand"
  property int currentFrame: 0
  property int spriteRow: 0
  property int spriteFrames: 6
  property int spriteFrameMs: 170

  readonly property real frameH: 112 * petScale
  readonly property real frameW: frameH * PetModel.FRAME_W / PetModel.FRAME_H
  // The frameIntervalMs setting acts as a speed scale relative to the
  // per-animation defaults (140 = normal speed).
  readonly property real speedScale: frameInterval / 140

  function floorY() { return Math.max(0, panel.height - frameH - bottomMargin) }

  function setAction(name) {
    action = name
    var sprite = PetModel.spriteFor(name)
    spriteRow = sprite.row
    spriteFrames = sprite.frames
    spriteFrameMs = sprite.frameMs
    currentFrame = 0
  }

  function scheduleNextAction() {
    behaviorTimer.interval = PetModel.actionDuration(agentState)
    behaviorTimer.restart()
  }

  function advanceBehavior() {
    if (!petVisible || dragArea.drag.active) return
    setAction(PetModel.pickAction(agentState))
    scheduleNextAction()
  }

  // Hidden means dormant: every repeating timer in this file is gated on
  // petVisible (directly or via this handler), and the PanelWindow surface
  // is destroyed, so a hidden pet costs nothing at all.
  onPetVisibleChanged: {
    if (petVisible) advanceBehavior()
    else {
      behaviorTimer.stop()
      bubble.shown = false
    }
  }

  function setAgentState(state, detail, holdMs, epoch) {
    state = PetModel.normalizeState(state)
    agentDetail = String(detail || "")
    lastStatusEpoch = epoch !== undefined ? epoch : Date.now() / 1000

    var changed = state !== agentState
    agentState = state
    if (holdMs !== undefined && holdMs > 0) holdTimer.restart(holdMs)
    else holdTimer.stop()

    if (state === "success") {
      setAction("jump")
      scheduleNextAction()
    } else if (state === "error") {
      setAction("crash")
      scheduleNextAction()
    } else if (state === "waiting") {
      setAction("fret")
      scheduleNextAction()
    } else if (changed) {
      advanceBehavior()
    }
  }

  function showBubble(text) {
    var value = String(text || "").slice(0, 140)
    if (value === "") return
    bubble.text = value
    bubble.shown = true
    bubbleTimer.restart()
  }

  // Clicking just plays the pet's own wave animation: no bubbles or effect
  // overlays, since installed pets can be anything from kittens to dark
  // mages and canned reactions won't fit them all.
  function petThePet() {
    setAction("wave")
    scheduleNextAction()
  }

  // Status files written by agent hooks: ours, plus the one the OmaPets bar
  // widget's hook installer writes, so existing setups work with no changes.
  function applyStatusJson(rawText) {
    try {
      var status = JSON.parse(String(rawText || "{}"))
      var epoch = Number(status.updatedAtEpoch || 0)
      var ageSec = Date.now() / 1000 - epoch
      if (!(epoch > 0) || ageSec > 14400 || epoch <= lastStatusEpoch) return
      var state = PetModel.normalizeState(status.state)
      // One-shot states are only meaningful live; don't replay them when a
      // reload re-reads an old status file.
      if ((state === "success" || state === "error") && ageSec > 30) return
      var hold = state === "success" ? 6000 : (state === "error" ? 10000 : 0)
      setAgentState(state, status.detail, hold, epoch)
    } catch (ignored) {}
  }

  Timer {
    id: behaviorTimer
    interval: 4000
    repeat: false
    running: false
    onTriggered: root.advanceBehavior()
  }

  Timer {
    id: holdTimer
    repeat: false
    function restart(ms) { interval = ms; stop(); start() }
    onTriggered: root.setAgentState("idle", "", 0)
  }

  Timer {
    id: bubbleTimer
    interval: 6500
    onTriggered: bubble.shown = false
  }

  // Frame clock: advances the sprite at the active animation's own rate.
  // Runs only while the pet is actually on screen.
  Timer {
    id: frameTimer
    interval: Math.max(50, Math.round(root.spriteFrameMs * root.speedScale))
    repeat: true
    running: root.petVisible && root.petAvailable
    onTriggered: root.currentFrame = (root.currentFrame + 1) % root.spriteFrames
  }

  // Movement clock: slides the pet smoothly while a walk action is active,
  // independent of the sprite frame rate so motion never looks steppy.
  Timer {
    id: moveTimer
    interval: 33
    repeat: true
    running: root.petVisible && root.petAvailable && PetModel.isWalking(root.action)
             && !dragArea.drag.active && !fallAnim.running
    onTriggered: {
      var speed = (root.agentState === "working" ? 64 : 36) * root.petScale
      var dx = speed * interval / 1000
      var next = petBody.x + (root.action === "walkRight" ? dx : -dx)
      var maxX = panel.width - root.frameW
      if (next <= 0) {
        next = 0
        root.setAction("walkRight")
      } else if (next >= maxX) {
        next = maxX
        root.setAction("walkLeft")
      }
      petBody.x = next
    }
  }

  // Revert to idle when hook-driven busy states go quiet for 15 minutes
  // (an agent that died mid-run never sends its final event).
  Timer {
    interval: 60000
    repeat: true
    running: root.petVisible && (root.agentState === "working" || root.agentState === "waiting")
    onTriggered: {
      if (Date.now() / 1000 - root.lastStatusEpoch > 900)
        root.setAgentState("idle", "", 0)
    }
  }

  // Backstop for FileView watches that miss events (file created after
  // startup, editors that replace instead of write).
  Timer {
    interval: 5000
    repeat: true
    running: root.petVisible
    onTriggered: {
      deskpetStatus.reload()
      omapetsStatus.reload()
    }
  }

  FileView {
    id: deskpetStatus
    path: "file://" + root.stateHome + "/deskpet/status.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyStatusJson(text())
  }

  FileView {
    id: omapetsStatus
    path: "file://" + root.stateHome + "/omarchy/omapets/status.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyStatusJson(text())
  }

  // ------------------------------------------------------- pet switching

  property string scanPurpose: "apply"

  Process {
    id: petScanner
    running: false
    command: [root.filePath(Qt.resolvedUrl("bin/scan-pets")), root.petsHome, root.compatPetsHome, root.openPetsHome]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var records = []
        var lines = String(text || "").trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
          var fields = lines[i].split("\t")
          if (!fields[0]) continue
          records.push({
            dir: fields[0],
            name: fields[1] || fields[0].split("/").pop(),
            sheet: fields[2] || "spritesheet.webp",
            version: Number(fields[3]) || 1
          })
        }
        root.petRecords = records
        if (records.length === 0) {
          root.applyPetRecord(null)
          console.info("deskpet: no pets installed; try `npx -y install-pet cloud-puff`")
          return
        }
        if (root.scanPurpose === "cycle") {
          if (records.length < 2) {
            root.showBubble("No other pets installed yet.")
            return
          }
          var index = -1
          for (var j = 0; j < records.length; j++)
            if (records[j].dir === root.appliedPetDir) index = j
          var next = records[(index + 1) % records.length]
          root.applyPetRecord(next)
          root.persistPetSelection(next.dir)
          return
        }
        root.applyPetRecord(root.desiredPetRecord())
      }
    }
  }

  function scanPets(purpose) {
    scanPurpose = purpose
    if (!petScanner.running) petScanner.running = true
  }

  function cyclePet() { scanPets("cycle") }

  function persistPetSelection(dir) {
    var entry = { id: "deskpet" }
    for (var key in entrySettings)
      if (key !== "id") entry[key] = entrySettings[key]
    entry.petPath = dir
    // A false return only means the config already pointed at this pet; the
    // switch itself was already applied directly.
    if (shell && typeof shell.updateEntryInline === "function")
      shell.updateEntryInline("deskpet", entry)
    else console.warn("deskpet: cannot persist pet selection")
  }

  Component.onCompleted: {
    advanceBehavior()
    scanPets("apply")
  }



  // ---------------------------------------------------------------- IPC

  IpcHandler {
    target: "deskpet"

    function idle(detail: string): string { root.setAgentState("idle", detail, 0); return "ok" }
    function working(detail: string): string { root.setAgentState("working", detail, 0); return "ok" }
    function waiting(detail: string): string { root.setAgentState("waiting", detail, 0); return "ok" }
    function success(detail: string): string { root.setAgentState("success", detail, 6000); return "ok" }
    function error(detail: string): string { root.setAgentState("error", detail, 10000); return "ok" }
    function say(text: string): string { root.showBubble(text); return "ok" }
    function pet(): string { root.petThePet(); return "ok" }
    function next(): string { root.cyclePet(); return "ok" }
    function toggle(): string { root.petVisible = !root.petVisible; return root.petVisible ? "shown" : "hidden" }
    function show(): string { root.petVisible = true; return "ok" }
    function hide(): string { root.petVisible = false; return "ok" }
    function state(): string { return root.agentState + ":" + root.action + ":" + root.petName }
    function ping(): string { return "ok" }
    function debug(): string {
      return JSON.stringify({
        running: petScanner.running,
        purpose: root.scanPurpose,
        records: root.petRecords,
        applied: root.appliedPetDir,
        configured: root.configuredPet,
        avail: root.petAvailable
      })
    }
  }

  // ------------------------------------------------------------- window

  PanelWindow {
    id: panel
    visible: root.petVisible && root.petAvailable
    // Full-screen so the pet can be dragged anywhere; the mask keeps
    // everything except the sprite itself click-through.
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    WlrLayershell.namespace: "deskpet"
    // Top, not Overlay: fullscreen apps and the lock screen should cover
    // the pet rather than the other way around.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Only the sprite is clickable; everything else passes through.
    mask: Region { item: petBody }

    onWidthChanged: {
      if (petBody.x > width - root.frameW)
        petBody.x = Math.max(0, width - root.frameW)
    }

    Item {
      id: petBody
      width: root.frameW
      height: root.frameH
      x: Math.max(0, (panel.width - root.frameW) / 2)
      y: root.floorY()

      Item {
        id: frameViewport
        anchors.fill: parent
        clip: true

        Image {
          id: atlas
          width: root.frameW * PetModel.COLUMNS
          height: root.frameH * root.atlasRows
          x: -root.currentFrame * root.frameW
          y: -root.spriteRow * root.frameH
          source: root.spritesheetUrl
          cache: false
          smooth: true
          mipmap: true
          asynchronous: true
          visible: root.petAvailable
        }
      }

      NumberAnimation {
        id: fallAnim
        target: petBody
        property: "y"
        duration: 620
        easing.type: Easing.OutBounce
      }

      MouseArea {
        id: dragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        drag.target: petBody
        drag.axis: Drag.XAndYAxis
        drag.minimumX: 0
        drag.maximumX: Math.max(0, panel.width - root.frameW)
        drag.minimumY: 0
        drag.maximumY: root.floorY()
        drag.threshold: 6

        onPressed: fallAnim.stop()
        onReleased: {
          if (petBody.y < root.floorY() - 1) {
            root.setAction("stand")
            fallAnim.to = root.floorY()
            fallAnim.restart()
            root.scheduleNextAction()
          }
        }
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.cyclePet()
          else if (mouse.button === Qt.MiddleButton) root.setAgentState("success", "demo", 4000)
          else root.petThePet()
        }
        onPressAndHold: root.setAction("held")
      }
    }

    // Speech bubble floats above the pet, clamped to the screen edges.
    Rectangle {
      id: bubble
      property bool shown: false
      property alias text: bubbleText.text
      visible: opacity > 0
      opacity: shown ? 1 : 0
      width: bubbleText.implicitWidth + Style.space(20)
      height: bubbleText.implicitHeight + Style.space(12)
      x: Math.max(8, Math.min(panel.width - width - 8,
           petBody.x + (root.frameW - width) / 2))
      // Above the pet normally; below it when dragged near the top edge.
      y: petBody.y - height - Style.space(8) < 8
           ? petBody.y + root.frameH + Style.space(8)
           : petBody.y - height - Style.space(8)
      radius: Style.cornerRadius
      color: Util.alpha(Color.background, 0.95)
      border.width: Math.max(1, Style.space(1))
      border.color: Color.popups.border

      Behavior on opacity { NumberAnimation { duration: 180 } }

      Text {
        id: bubbleText
        anchors.centerIn: parent
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }
    }
  }
}
