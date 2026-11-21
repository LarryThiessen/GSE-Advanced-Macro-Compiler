-- The action buttons' right-click menu has a Keybind row that opens WoW's Key
-- Bindings at the button's section.
--
-- The menu is in GSE_Utils, which is always loaded; the code that opens the
-- page is in GSE_GUI, which loads on demand, so the menu calls it by name
-- through GSE.GUICall -- which does nothing, silently, for a name that is not
-- there. This holds the two ends to the same name. Read as text (line endings
-- normalised): neither file loads here.
local function readSource(path)
  local fh = assert(io.open(path, "r"))
  local src = fh:read("*a")
  fh:close()
  return (src:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

describe("action button right-click menu: Keybind", function()
  local menu = readSource("GSE_Utils/Utils.lua")
  local page = readSource("GSE_GUI/Editor_Keybind.lua")

  it("calls a function the Button Bindings page file defines", function()
    local name = assert(menu:match('L%["Keybind"%], function%(%)%s+GSE%.GUICall%("([%w_]+)", buttonName%)'),
      "the Keybind row's call not found")
    assert.truthy(page:find("function GSE." .. name .. "(buttonName)", 1, true), name .. " is not defined")
  end)

  it("opens Key Bindings at the button's own binding", function()
    local s = assert(page:find("function GSE.GUIOpenButtonKeyBindings(buttonName)", 1, true))
    local e = assert(page:find("\nend\n", s, true))
    assert.truthy(page:sub(s, e):find("openWoWKeyBindingsFor(bindingActionFor(buttonName))", 1, true))
  end)

  it("a cleared or moved sequence puts the States ticked for the next one back to Default", function()
    local events = readSource("GSE/API/Events.lua")
    local s = assert(events:find("local function forgetMenuStates()", 1, true))
    local forget = events:sub(s, assert(events:find("\nend\n", s, true)))
    assert.truthy(forget:find('if type(GSE_C) == "table" then GSE_C.ActionBarMenuStates = nil end', 1, true))
    for _, name in ipairs({ "function GSE.RemoveActionBarOverride(buttonName)", "function GSE.MoveActionBarOverride(fromName, toName)" }) do
      local from = assert(events:find(name, 1, true))
      local body = events:sub(from, assert(events:find("\nend\n", from, true)))
      local dropped = assert(body:find("forgetMenuStates()", 1, true), name .. " keeps the ticks")
      assert.is_true(dropped < assert(body:find("GSE.ReloadOverrides()", 1, true)))
    end
    -- The menu's Clear Override goes through the first of them.
    assert.truthy(menu:find('rootDescription:CreateButton(L["Clear Override"], function()\n                    GSE.RemoveActionBarOverride(buttonName)', 1, true))
    -- With none remembered, an empty button opens on the state it is in alone.
    assert.truthy(menu:find("toStates = { [first] = true }", 1, true))
    assert.truthy(menu:find('if type(last) == "table" and last[k] then toStates[k] = true end', 1, true))
  end)

  it("shows the row with and without sequences to list", function()
    local _, rows = menu:gsub("addKeybindRow%(rootDescription%)", "")
    assert.are.equal(2, rows, "after the pickers, and where the button has a sequence but none are left to pick")
  end)

  it("has its strings", function()
    local strings = readSource("GSE/Localization/ModL_enUS.lua")
    assert.truthy(strings:find('L["Keybind"] = true', 1, true))
    assert.truthy(strings:find('L["Open WoW\'s Key Bindings at this button, to set its key."] = true', 1, true))
  end)
end)

-- The menu's State pick takes more than one state (Larry, 2026-11-20: "a
-- Warrior can choice all 3 if they want"): the sequence goes on each ticked
-- state, a row apiece.
describe("action button right-click menu: more than one state", function()
  local menu = readSource("GSE_Utils/Utils.lua")
  local events = readSource("GSE/API/Events.lua")

  -- GSE.CreateActionBarOverrides as Events.lua has it, against a recorder.
  local function assign(states, inCombat)
    local calls = {}
    local GSE = {
      SetOverrideData = function(button, id, layer, state, loadout)
        calls[#calls + 1] = { "data", button, id, layer, state == nil and "nil" or state, loadout }
      end,
      CreateActionBarOverride = function(button, id, layer, state, loadout)
        calls[#calls + 1] = { "apply", button, id, layer, state == nil and "nil" or state, loadout }
        return layer
      end,
    }
    local s = assert(events:find("function GSE.CreateActionBarOverrides(buttonName, sequenceId, layer, states, loadout)", 1, true))
    local _, e = events:find("\nend\n", s, true)
    local code = events:sub(s, e) .. "\nreturn GSE.CreateActionBarOverrides"
    local env = { GSE = GSE, InCombatLockdown = function() return inCombat or false end }
    local chunk
    if loadstring then
      chunk = assert(loadstring(code))
      setfenv(chunk, env)
    else
      chunk = assert(load(code, "CreateActionBarOverrides", "t", env))
    end
    return chunk()("ActionButton1", "seq", "spec", states, "L1"), calls
  end

  it("writes a row for each ticked state, and applies once", function()
    local written, calls = assign({ "Default", "7", "9" })
    assert.are.equal("spec", written)
    assert.are.same({
      { "data", "ActionButton1", "seq", "spec", "nil", "L1" },
      { "data", "ActionButton1", "seq", "spec", "7", "L1" },
      { "apply", "ActionButton1", "seq", "spec", "9", "L1" },
    }, calls)
  end)

  it("writes the one state as before", function()
    local _, calls = assign({ "7" })
    assert.are.same({ { "apply", "ActionButton1", "seq", "spec", "7", "L1" } }, calls)
  end)

  it("puts it on the state the button is in where the button has no states to tick", function()
    local _, calls = assign({})
    assert.are.same({ { "apply", "ActionButton1", "seq", "spec", "nil", "L1" } }, calls)
  end)

  it("writes nothing in combat", function()
    local written, calls = assign({ "Default", "7" }, true)
    assert.is_nil(written)
    assert.are.same({}, calls)
  end)

  it("opens with every state that holds the sequence shown ticked", function()
    assert.truthy(menu:find("if holds == existingSequence then toStates[k] = true end", 1, true))
  end)

  it("opens an empty button with the states ticked at the last assignment, beside its own", function()
    assert.truthy(menu:find("local last = type(GSE_C) == \"table\" and GSE_C.ActionBarMenuStates", 1, true))
    assert.truthy(menu:find("for _, k in ipairs(pickedStates()) do GSE_C.ActionBarMenuStates[k] = true end", 1, true))
  end)

  it("changes a button that shows a sequence as its boxes are ticked and unticked", function()
    local s0 = assert(menu:find("select = function()", 1, true))
    local e0 = assert(menu:find("toStates[k] = not toStates[k] or nil", s0, true))
    local pick = menu:sub(s0, e0)
    assert.truthy(pick:find("if existingSequence then", 1, true))
    assert.truthy(pick:find("if InCombatLockdown() then return end", 1, true), "not in combat")
    assert.truthy(pick:find("GSE.ClearOverrideData(buttonName, state)", 1, true), "unticked: off that state")
    assert.truthy(pick:find("if tostring(saved) == tostring(state) then", 1, true), "its own row only, never the Default's")
    assert.truthy(pick:find("GSE.SetOverrideData(buttonName, existingSequence,", 1, true), "ticked: on that state")
    -- Saved at once, put on the buttons when the menu has closed: the menu
    -- stays open for the next tick (Larry, 2026-11-20).
    assert.is_nil(pick:find("GSE.ReloadOverrides()", 1, true), "putting it on at once closes the menu")
    assert.is_nil(pick:find("MenuResponse.CloseAll", 1, true))
    local _, later = pick:gsub("applyWhenMenuCloses%(self%)", "")
    assert.are.equal(2, later, "after a tick and after an untick")
    assert.truthy(menu:find("return choice.select() or MenuResponse.Refresh", 1, true))
  end)

  -- applyWhenMenuCloses / applyStateTicks as Utils.lua has them, with a menu
  -- that can be open or closed and a clock that ticks when told to.
  local function ticks()
    local s = assert(menu:find("    local applyTicker\n", 1, true))
    local e = assert(menu:find("    -- Shared handler:", s, true))
    local code = menu:sub(s, e - 1) .. "\nreturn applyWhenMenuCloses, applyStateTicks"
    local w = { applied = 0, combat = false, open = nil, tickers = 0 }
    local env = {
      GSE = { ReloadOverrides = function() w.applied = w.applied + 1 end },
      InCombatLockdown = function() return w.combat end,
      Menu = { GetManager = function() return { GetOpenMenu = function()
        return w.open and { GetOwnerRegion = function() return w.open end } or nil
      end } end },
      C_Timer = { NewTicker = function(_, fn)
        w.tickers = w.tickers + 1
        w.tick = fn
        return { Cancel = function() w.tick = nil end }
      end },
    }
    local chunk
    if loadstring then
      chunk = assert(loadstring(code))
      setfenv(chunk, env)
    else
      chunk = assert(load(code, "ticks", "t", env))
    end
    w.later, w.now = chunk()
    return w
  end

  it("puts the ticks on the buttons once the button's menu has closed, and once", function()
    local w, button = ticks(), {}
    w.open = button
    w.later(button)
    w.later(button)
    assert.are.equal(1, w.tickers, "one watch for any number of ticks")
    w.tick()
    assert.are.equal(0, w.applied, "the menu is still open")
    w.open = {}
    w.tick()
    assert.are.equal(1, w.applied, "another button's menu is not this one's")
    assert.is_nil(w.tick, "and the watch is over")
  end)

  it("holds the ticks through combat, and puts them on first when a menu is opened again", function()
    local w, button = ticks(), {}
    w.later(button)
    w.combat = true
    w.tick()
    assert.are.equal(0, w.applied)
    w.combat = false
    assert.is_true(w.now())
    assert.are.equal(1, w.applied)
    assert.is_false(w.now(), "nothing waiting")
    local handler = menu:sub(assert(menu:find("local function gseEmptyButtonHandler(self, mousebutton, down)", 1, true)))
    local first = assert(handler:find("if applyStateTicks() then", 1, true))
    local reads = assert(handler:find('local existingSequence = self:GetAttribute("gse-button")', 1, true))
    assert.is_true(first < reads, "before the menu reads what is on the buttons")
  end)

  it("ticks states with boxes, keeps the last tick, and hands every ticked state on", function()
    assert.truthy(menu:find("local create = multi and row.CreateCheckbox or row.CreateRadio", 1, true))
    assert.truthy(menu:find("if toStates[k] and #pickedStates() == 1 then return end", 1, true), "never none ticked")
    assert.truthy(menu:find('GSE.CreateActionBarOverrides(buttonName, entryId,\n'
      .. '                            toLoadout and "loadout" or "spec", pickedStates(), toLoadout and toLoadout.id)', 1, true))
  end)
end)
