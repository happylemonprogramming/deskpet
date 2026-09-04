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
  readonly property string configuredPet: String(setting("petPath", ""))
  readonly property bool startVisible: setting("visible", true) !== false

  // ------------------------------------------------------------ pet package

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || home + "/.local/share"
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
  readonly property string petsHome: dataHome + "/deskpet/pets"
  // Pets installed by the OmaPets bar widget load too; same sprite format.
  readonly property string compatPetsHome: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/omapets/pets"

  function filePath(url) {
    return decodeURIComponent(String(url || "").replace(/^file:\/\//, ""))
  }
  function expandHome(path) {
    var value = String(path || "")
    if (value === "~") return home
    if (value.indexOf("~/") === 0) return home + value.slice(1)
    return value
  }

  readonly property string bundledPetDir: filePath(Qt.resolvedUrl("assets/pets/yuzu-golden-kitten"))
  // A bare id resolves inside petsHome first; when its manifest fails to
  // load we retry the OmaPets directory before giving up.
  property string petDirOverride: ""
  readonly property string resolvedPetDir: {
    var p = expandHome(configuredPet)
    if (p === "") return bundledPetDir
    if (p.indexOf("/") < 0) return petsHome + "/" + p
    return p.replace(/\/$/, "")
  }
  readonly property string effectivePetDir: petDirOverride !== "" ? petDirOverride : resolvedPetDir

  property bool petAvailable: false
  property string petName: ""
  property int atlasRows: 9
  property url spritesheetUrl: ""

  onConfiguredPetChanged: petDirOverride = ""

  Loader {
    id: petManifestLoader
    active: root.effectivePetDir !== ""

    sourceComponent: FileView {
      path: "file://" + root.effectivePetDir + "/pet.json"
      watchChanges: true
      printErrors: false
      onFileChanged: reload()
      onLoadFailed: {
        // Bare pet ids fall back to the OmaPets-installed pets directory.
        if (root.petDirOverride === "" && root.configuredPet !== ""
            && root.configuredPet.indexOf("/") < 0) {
          root.petDirOverride = root.compatPetsHome + "/" + root.configuredPet
          return
        }
        root.petAvailable = false
        root.spritesheetUrl = ""
      }
      onLoaded: {
        try {
          var pet = JSON.parse(String(text() || "{}"))
          var sheet = String(pet.spritesheetPath || "spritesheet.webp")
          if (sheet.indexOf("..") >= 0 || sheet.charAt(0) === "/")
            throw new Error("spritesheetPath must stay inside the pet folder")
          root.petName = String(pet.displayName || pet.id || "Pet")
          root.atlasRows = Number(pet.spriteVersionNumber || 1) >= 2 ? 11 : 9
          root.spritesheetUrl = "file://" + root.effectivePetDir + "/" + sheet
          root.petAvailable = true
        } catch (error) {
          console.warn("deskpet: invalid pet manifest at", root.effectivePetDir, error)
          root.petAvailable = false
          root.spritesheetUrl = ""
        }
      }
    }
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
  property bool greeted: false

  readonly property real frameH: 140 * petScale
  readonly property real frameW: frameH * PetModel.FRAME_W / PetModel.FRAME_H
  readonly property real bubbleHeadroom: 96
  readonly property real stripHeight: frameH * 2 + bubbleHeadroom + bottomMargin

  function floorY() { return stripHeight - frameH - bottomMargin }

  function setAction(name) {
    action = name
    var sprite = PetModel.spriteFor(name)
    spriteRow = sprite.row
    spriteFrames = sprite.frames
    currentFrame = 0
  }

  function scheduleNextAction() {
    behaviorTimer.interval = PetModel.actionDuration(agentState)
    behaviorTimer.restart()
  }

  function advanceBehavior() {
    if (dragArea.drag.active) return
    setAction(PetModel.pickAction(agentState))
    scheduleNextAction()
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
      if (changed) showBubble(PetModel.pickMessage("success"))
      scheduleNextAction()
    } else if (state === "error") {
      setAction("crash")
      if (changed) showBubble(PetModel.pickMessage("error"))
      scheduleNextAction()
    } else if (state === "waiting") {
      setAction("fret")
      if (changed) showBubble(PetModel.pickMessage("waiting"))
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

  function petThePet() {
    setAction("wave")
    showBubble(PetModel.pickMessage("pet"))
    heartBurst.restart()
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

  // Frame clock: advances the sprite and, while a walk action is active,
  // moves the pet. Runs only while the pet is actually on screen.
  Timer {
    id: frameTimer
    interval: root.frameInterval
    repeat: true
    running: root.petVisible && root.petAvailable
    onTriggered: {
      root.currentFrame = (root.currentFrame + 1) % root.spriteFrames
      if (PetModel.isWalking(root.action) && !dragArea.drag.active && !fallAnim.running) {
        var step = (root.agentState === "working" ? 9 : 5) * root.petScale
        var dx = root.action === "walkRight" ? step : -step
        var next = petBody.x + dx
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
  }

  // Revert to idle when hook-driven busy states go quiet for 15 minutes
  // (an agent that died mid-run never sends its final event).
  Timer {
    interval: 60000
    repeat: true
    running: root.agentState === "working" || root.agentState === "waiting"
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

  property var availablePets: []

  Process {
    id: petScanner
    running: false
    command: [root.filePath(Qt.resolvedUrl("bin/scan-pets")), root.petsHome, root.compatPetsHome]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var pets = [root.bundledPetDir]
        var lines = String(text || "").trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
          var dir = lines[i].split("\t")[0]
          if (dir && dir !== "") pets.push(dir)
        }
        root.availablePets = pets
        root.selectNextPet()
      }
    }
  }

  function cyclePet() {
    if (!petScanner.running) petScanner.running = true
  }

  function selectNextPet() {
    var pets = availablePets
    if (!pets || pets.length < 2) {
      showBubble("No other pets installed yet.")
      return
    }
    var index = pets.indexOf(effectivePetDir)
    var nextDir = pets[(index + 1) % pets.length]
    var petPath = nextDir === bundledPetDir ? "" : nextDir
    var entry = { id: "deskpet" }
    for (var key in entrySettings)
      if (key !== "id") entry[key] = entrySettings[key]
    entry.petPath = petPath
    if (!(shell && typeof shell.updateEntryInline === "function"
          && shell.updateEntryInline("deskpet", entry)))
      console.warn("deskpet: could not persist pet selection")
  }

  Component.onCompleted: advanceBehavior()

  onPetAvailableChanged: {
    if (petAvailable && !greeted) {
      greeted = true
      showBubble(PetModel.pickMessage("hello"))
    }
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
  }

  // ------------------------------------------------------------- window

  PanelWindow {
    id: panel
    visible: root.petVisible && root.petAvailable
    anchors { left: true; right: true; bottom: true }
    implicitHeight: root.stripHeight
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

      // Floating heart shown when the pet is petted.
      Text {
        id: heart
        text: "\u2764"
        color: "#e0507a"
        font.pixelSize: Math.round(20 * root.petScale)
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        opacity: 0

        SequentialAnimation {
          id: heartBurst
          ParallelAnimation {
            NumberAnimation { target: heart; property: "y"; from: 4; to: -34 * root.petScale; duration: 900; easing.type: Easing.OutCubic }
            SequentialAnimation {
              NumberAnimation { target: heart; property: "opacity"; from: 0; to: 1; duration: 150 }
              PauseAnimation { duration: 450 }
              NumberAnimation { target: heart; property: "opacity"; to: 0; duration: 300 }
            }
          }
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
      y: petBody.y - height - Style.space(8)
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
