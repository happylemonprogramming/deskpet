// Pure model data for the deskpet: atlas layout, behavior policies, speech.
//
// Sprite format: the Codex/OpenPets V1 atlas — 8 columns of 192x208 frames,
// nine rows in a fixed order. V2 atlases add two gaze rows below but keep
// rows 0-8 unchanged, so both load with the same table.
.pragma library

var FRAME_W = 192
var FRAME_H = 208
var COLUMNS = 8

var SPRITES = {
  idle:     { row: 0, frames: 6 },
  runRight: { row: 1, frames: 8 },
  runLeft:  { row: 2, frames: 8 },
  wave:     { row: 3, frames: 6 },
  jump:     { row: 4, frames: 6 },
  failed:   { row: 5, frames: 8 },
  waiting:  { row: 6, frames: 6 },
  active:   { row: 7, frames: 6 },
  review:   { row: 8, frames: 6 }
}

// What the pet is doing -> which atlas animation plays. "Actions" are pet
// behaviors; several share a row.
var ACTION_SPRITES = {
  stand:     "idle",
  walkRight: "runRight",
  walkLeft:  "runLeft",
  wave:      "wave",
  jump:      "jump",
  sit:       "review",
  buzz:      "active",
  fret:      "waiting",
  crash:     "failed",
  held:      "jump"
}

function spriteFor(action) {
  return SPRITES[ACTION_SPRITES[action] || "idle"]
}

function isWalking(action) {
  return action === "walkLeft" || action === "walkRight"
}

// Weighted action policies per agent state. The behavior timer draws from
// the active policy, so an idle pet mostly stands, sits, and strolls, a
// working pet paces, and a waiting pet frets and waves for attention.
var POLICIES = {
  idle:    [["stand", 38], ["walkLeft", 15], ["walkRight", 15], ["sit", 22], ["wave", 5], ["jump", 5]],
  working: [["walkLeft", 30], ["walkRight", 30], ["buzz", 40]],
  waiting: [["fret", 75], ["wave", 25]],
  success: [["jump", 55], ["wave", 45]],
  error:   [["crash", 100]]
}

function pickAction(agentState) {
  var policy = POLICIES[agentState] || POLICIES.idle
  var total = 0
  for (var i = 0; i < policy.length; i++) total += policy[i][1]
  var roll = Math.random() * total
  for (var j = 0; j < policy.length; j++) {
    roll -= policy[j][1]
    if (roll <= 0) return policy[j][0]
  }
  return policy[0][0]
}

// How long an action runs before the next draw, in ms.
function actionDuration(agentState) {
  function between(lo, hi) { return lo + Math.round(Math.random() * (hi - lo)) }
  if (agentState === "working") return between(1500, 3500)
  if (agentState === "waiting") return between(2500, 5000)
  if (agentState === "success") return between(1800, 2600)
  return between(3000, 8500)
}

// Curated speech pools. Never echo agent output: bubbles only ever show
// these strings or text passed explicitly through the `say` IPC verb.
var MESSAGES = {
  hello:   ["Hi! I live here now.", "Reporting for duty!", "What are we building today?", "*stretches*"],
  success: ["Done!", "All green!", "Shipped it!", "Nailed it.", "That went well!"],
  error:   ["Uh oh.", "That broke.", "Red. Very red.", "We do not talk about that build.", "Hmm. Not our best."],
  waiting: ["Your turn!", "Psst - input needed.", "Waiting on you, boss.", "*taps foot*"],
  pet:     ["Purr...", "Mrrp!", "More pets please.", "That is the spot.", "*happy wiggle*"]
}

function pickMessage(kind) {
  var pool = MESSAGES[kind]
  if (!pool || pool.length === 0) return ""
  return pool[Math.floor(Math.random() * pool.length)]
}

// Agent states the pet understands; anything else normalizes to idle.
function normalizeState(value) {
  var state = String(value || "").toLowerCase()
  return POLICIES[state] !== undefined ? state : "idle"
}
