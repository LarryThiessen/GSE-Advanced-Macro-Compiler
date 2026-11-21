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
    assert.truthy(pick:find("GSE.CreateActionBarOverride(buttonName, existingSequence,", 1, true), "ticked: on that state")
    assert.truthy(pick:find("if k == nowState or #pickedStates() == 0 then return MenuResponse.CloseAll end", 1, true))
    assert.truthy(menu:find("return choice.select() or MenuResponse.Refresh", 1, true))
  end)

  it("ticks states with boxes, keeps the last tick, and hands every ticked state on", function()
    assert.truthy(menu:find("local create = multi and row.CreateCheckbox or row.CreateRadio", 1, true))
    assert.truthy(menu:find("if toStates[k] and #pickedStates() == 1 then return end", 1, true), "never none ticked")
    assert.truthy(menu:find('GSE.CreateActionBarOverrides(buttonName, entryId,\n'
      .. '                            toLoadout and "loadout" or "spec", pickedStates(), toLoadout and toLoadout.id)', 1, true))
  end)
end)
