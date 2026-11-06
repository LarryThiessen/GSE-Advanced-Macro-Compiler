-- A press of a sequence shows on the Blizzard action buttons that hold the
-- spell that press fired (GSE/API/Events.lua, showCastPress and
-- GSE.SequenceStepShown): the pushed art, shown and hidden again, on every
-- shown button whose slot holds the spell -- the same id, the one a talent
-- replaced, or the same spell by name where the bar holds another rank --
-- never on a button a sequence is on, and never an error on a value Midnight
-- keeps secret.
--
-- Events.lua cannot be loaded here, so this reads the functions out of it as
-- text and runs them against stand-in buttons.
--
-- Run: busted spec/castpress_spec.lua   /   lua5.1 spec/run51.lua
describe("A sequence's press shown as a button press", function()
  local GLOBALS = { "GSE", "GSEOptions", "GetActionInfo", "GetTime", "C_Timer", "FindBaseSpellByID", "UnitIsDeadOrGhost",
    "UnitExists", "UnitIsUnit", "C_Spell",
    "ActionButton1", "ActionButton2", "MultiBar5Button3" }
  local saved, showCastPress, stepShown, timers, secret, now, dead, target, onSelf

  local function button(slot, fields)
    local b = fields or {}
    b.shown, b.state = 0, "NORMAL"
    local pushed = { Show = function() b.shown = b.shown + 1 end, Hide = function() b.shown = 0 end }
    b.IsVisible = function() return not b.hidden end
    b.GetAttribute = function(_, name) return name == "gse-button" and b.sequence or nil end
    b.GetPushedTexture = function() return pushed end
    b.GetButtonState = function() return b.state end
    b.slot = slot
    return b
  end

  setup(function()
    saved = {}
    for _, name in ipairs(GLOBALS) do saved[name] = _G[name] end
    local fh = assert(io.open("GSE/API/Events.lua", "r"))
    local src = fh:read("*a"):gsub("\r\n", "\n"):gsub("\r", "\n")
    fh:close()
    local bars = assert(src:match("\nlocal CAST_PRESS_BARS = (%b{})\n"), "CAST_PRESS_BARS not found")
    local holds = assert(src:match("\nlocal function slotHoldsSpell%(slot, spellID, base, name%)\n(.-)\nend\n"),
      "slotHoldsSpell not found")
    local body = assert(src:match("\nlocal function showCastPress%(spellID, name%)\n(.-)\nend\n"), "showCastPress not found")
    local shown = assert(src:match("\nfunction GSE%.SequenceStepShown%(sequenceId, spellID, name, pressed%)\n(.-)\nend\n"),
      "GSE.SequenceStepShown not found")
    secret = {}
    showCastPress, stepShown = assert((loadstring or load)(
      "local isSecretValue, getButtonEffectiveSlot, PRESS_FLASH_SECONDS = ...\n"
      .. "local CAST_PRESS_BARS = " .. bars .. "\n"
      .. "local function slotHoldsSpell(slot, spellID, base, name)\n" .. holds .. "\nend\n"
      .. "local pressShownUntil = {}\n"
      .. "local function showCastPress(spellID, name)\n" .. body .. "\nend\n"
      .. "local pressNext = {}\n"
      .. "return showCastPress, function(sequenceId, spellID, name, pressed)\n" .. shown .. "\nend"))(
      function(value) return value == secret end,
      function(b) return b.slot end,
      0.1)
    C_Timer = { After = function(delay, fn) timers[#timers + 1] = { due = now + delay, fn = fn } end }
    GetTime = function() return now end
    UnitIsDeadOrGhost = function(unit) return unit == "player" and dead end
    UnitExists = function(unit) return unit == "target" and target end
    UnitIsUnit = function(a, b) return a == "target" and b == "player" and onSelf end
    -- 100 only harms, 200 harms and helps (as a spell that heals a friend
    -- and hurts an enemy does), 300 only helps.
    C_Spell = {
      IsSpellHarmful = function(spell) return spell == 100 or spell == 200 end,
      IsSpellHelpful = function(spell) return spell == 200 or spell == 300 end,
    }
    -- Slots 1 and 147 hold spell 100; slot 2 holds 200, the base of 201 and
    -- another rank of 529; slot 3 holds an item with a spell's number.
    local slots = { [1] = { "spell", 100 }, [147] = { "spell", 100 }, [2] = { "spell", 200 }, [3] = { "item", 100 } }
    GetActionInfo = function(slot)
      local held = slots[slot]
      if held then return held[1], held[2] end
    end
    local names = { [100] = "Kill Command", [200] = "Lightning Bolt", [201] = "Tempest", [529] = "Lightning Bolt" }
    local byName = { ["Lightning Bolt(Rank 2)"] = 529 }
    GSE = { GetSpellInfo = function(spell)
      local id = byName[spell] or spell
      return names[id] and { name = names[id], spellID = id } or nil
    end }
    GSEOptions = { actionBarShowCastPress = true }
    FindBaseSpellByID = function(spellID) return spellID == 201 and 200 or spellID end
  end)

  teardown(function()
    for _, name in ipairs(GLOBALS) do _G[name] = saved[name] end
  end)

  before_each(function()
    timers, now, dead, target, onSelf = {}, 10, false, true, false
    GSEOptions.actionBarShowCastPress = true
    ActionButton1, ActionButton2, MultiBar5Button3 = button(1), button(2), button(147)
  end)

  -- Every timer due by then, as the game would run them.
  local function runTimers(at)
    now = at
    local waiting = timers
    timers = {}
    for _, timer in ipairs(waiting) do
      if timer.due <= at + 1e-9 then timer.fn() else timers[#timers + 1] = timer end
    end
  end

  it("shows the pushed art on every button holding the spell, then hides it", function()
    showCastPress(100)
    assert.are.equal(1, ActionButton1.shown)
    assert.are.equal(1, MultiBar5Button3.shown)
    assert.are.equal(0, ActionButton2.shown)
    runTimers(10.1)
    assert.are.equal(0, ActionButton1.shown)
  end)

  it("keeps the art up when the next press comes before it would go", function()
    showCastPress(100)
    now = 10.05
    showCastPress(100)
    runTimers(10.1) -- the first press's timer: the second still holds it up
    assert.is_true(ActionButton1.shown > 0)
    runTimers(10.15)
    assert.are.equal(0, ActionButton1.shown)
  end)

  it("leaves the art up for a button held down when the flash ends", function()
    showCastPress(100)
    ActionButton1.state = "PUSHED"
    runTimers(10.1)
    assert.are.equal(1, ActionButton1.shown)
  end)

  it("finds the button holding the spell a talent replaced", function()
    showCastPress(201)
    assert.are.equal(1, ActionButton2.shown)
  end)

  it("finds the button holding another rank of the spell, by its name", function()
    showCastPress(529)
    assert.are.equal(1, ActionButton2.shown)
    assert.are.equal(0, ActionButton1.shown)
  end)

  it("finds the button from a spell's name alone, rank and all", function()
    showCastPress(nil, "Lightning Bolt(Rank 2)")
    assert.are.equal(1, ActionButton2.shown)
  end)

  it("leaves a slot holding an item with the spell's number alone", function()
    ActionButton1.slot = 3
    showCastPress(100)
    assert.are.equal(0, ActionButton1.shown)
  end)

  it("skips a hidden button and one a sequence is on", function()
    ActionButton1.hidden = true
    MultiBar5Button3.sequence = "seqA"
    showCastPress(100)
    assert.are.equal(0, ActionButton1.shown)
    assert.are.equal(0, MultiBar5Button3.shown)
  end)

  it("does nothing for a spell on no bar, a secret spell, or no spell", function()
    showCastPress(999)
    showCastPress(secret)
    showCastPress(nil, nil)
    assert.are.equal(0, ActionButton1.shown + ActionButton2.shown + MultiBar5Button3.shown)
  end)

  it("shows nothing while the player is dead", function()
    dead = true
    showCastPress(100)
    assert.are.equal(0, ActionButton1.shown + MultiBar5Button3.shown)
  end)

  it("shows nothing without a target", function()
    target = false
    showCastPress(100)
    assert.are.equal(0, ActionButton1.shown + MultiBar5Button3.shown)
  end)

  it("shows nothing for a spell that only harms while the player targets themself", function()
    onSelf = true
    showCastPress(100)
    assert.are.equal(0, ActionButton1.shown + MultiBar5Button3.shown)
    showCastPress(200) -- harms and helps: it lands on the player
    assert.are.equal(1, ActionButton2.shown)
  end)

  it("shows the press where the game keeps who the target is secret", function()
    onSelf = secret
    showCastPress(100)
    assert.are.equal(1, ActionButton1.shown)
  end)

  it("shows a press on the spell of the step that press fired, not the next one", function()
    stepShown("seqA", 100, "Kill Command", false) -- at rest: the first press fires 100
    assert.are.equal(0, ActionButton1.shown)
    stepShown("seqA", 200, "Lightning Bolt", true) -- pressed: 100 fired, 200 is next
    assert.are.equal(1, ActionButton1.shown)
    assert.are.equal(0, ActionButton2.shown)
    stepShown("seqA", 100, "Kill Command", true) -- pressed: 200 fired
    assert.are.equal(1, ActionButton2.shown)
  end)

  it("keeps each sequence's own step, and shows nothing with the option off", function()
    stepShown("seqA", 100, "Kill Command", false)
    stepShown("seqB", 200, "Lightning Bolt", false)
    GSEOptions.actionBarShowCastPress = false
    stepShown("seqA", 100, "Kill Command", true)
    assert.are.equal(0, ActionButton1.shown)
    GSEOptions.actionBarShowCastPress = true
    stepShown("seqB", 200, "Lightning Bolt", true)
    assert.are.equal(1, ActionButton2.shown)
    assert.are.equal(0, ActionButton1.shown)
  end)
end)
