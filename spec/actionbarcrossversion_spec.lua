-- Stance, form and stealth bars on every WoW version GSE supports and on every
-- action bar addon it puts sequences on.
--
-- The rule (actionbarstances_spec.lua): a sequence's Default row stays off a
-- bar a stance, form or stealth turns to, and a row pinned to one runs there.
-- Two things carry it and must always agree: the button's own secure click
-- (BAR_SWAP_ONCLICK, Events.lua), which decides what a press does, and
-- GSE.ButtonOverrideSequence (Profiles.lua), which decides the icon, the
-- watermark and what the right-click menu offers. This runs both, as the addon
-- has them, against buttons shaped as each bar addon builds them, in every
-- stance each class has on each client.
--
-- Which stances turn the bar is Blizzard's data, SpellShapeshiftForm's
-- BonusActionBar column, read per client from wago.tools on 2026-11-20
-- (Classic Era 1.15.9, TBC Anniversary 2.5.6, MoP Classic 5.5.4, WoW Forever
-- 1.60.1, Retail 12.1.5); Bartender4 4.19.2, Dominos 12.0.4 and ElvUI list the
-- same. The button shapes are read from the addons' own code: Dominos 12.0.4,
-- EllesmereUI 9.9.1, DaylightUI 2.1.3, Bartender4 4.19.2 (LibActionButton).
local function readSource(path)
  local fh = assert(io.open(path, "r"))
  local src = fh:read("*a")
  fh:close()
  return (src:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

local function between(src, startText, endText)
  local s = src:find(startText, 1, true)
  assert(s, "start not found: " .. startText)
  local e = src:find(endText, s, true)
  assert(e, "end not found: " .. endText)
  return src:sub(s, e - 1)
end

local function compile(code, name, env)
  if loadstring then
    local chunk = assert(loadstring(code, name))
    setfenv(chunk, env)
    return chunk
  end
  return assert(load(code, name, "t", env))
end

local events = readSource("GSE/API/Events.lua")
local profiles = readSource("GSE/API/Profiles.lua")

-- The stance code as the addon has it: the page drivers, names and states
-- (Profiles.lua), and the state a button is in (Events.lua).
local STANCE_CODE = between(profiles, "function GSE.LABDefaultState(buttonName)",
    "--- Whether an overridden button runs sequence in any of its states.")
  .. between(events, "local function isBonusPaged(button)", "-- asDefault: the button's Default row")
  .. between(events, "local function getButtonEffectiveSlot(btn)", "function GSE.ActionBarSlotHasForeignAction(button)")
  .. "\nGSE.TestIsBonusPaged = isBonusPaged\n"

local ONCLICK
do
  local resolve = assert(events:match("local BAR_SWAP_RESOLVE = %[%[(.-)%]%]"), "BAR_SWAP_RESOLVE not found")
  local head, tail = events:match("local BAR_SWAP_ONCLICK = %[%[(.-)%]%] %.%. BAR_SWAP_RESOLVE %.%. %[%[(.-)%]%]")
  assert(head and tail, "BAR_SWAP_ONCLICK not built from BAR_SWAP_RESOLVE")
  ONCLICK = head .. resolve .. tail
end

-- Each client: how GSE knows it, the spells it has (a page is named by its
-- spell), and the bonus bar each class's stances bring up.
local SPELLS = {
  [768] = "Cat Form", [5487] = "Bear Form", [24858] = "Moonkin Form", [33891] = "Tree of Life",
  [1784] = "Stealth", [51713] = "Shadow Dance", [2457] = "Battle Stance", [71] = "Defensive Stance",
  [2458] = "Berserker Stance", [15473] = "Shadowform", [103985] = "Stance of the Fierce Tiger",
  [115069] = "Stance of the Sturdy Ox", [115070] = "Stance of the Wise Serpent",
}
local CLIENTS = {
  { name = "Classic Era", gameMode = 1,
    has = { 768, 5487, 24858, 1784, 2457, 71, 2458, 15473 },
    bonus = { WARRIOR = { 1, 2, 3 }, DRUID = { 1, 3 }, ROGUE = { 1 }, PRIEST = {}, MAGE = {} } },
  { name = "TBC Anniversary", gameMode = 2,
    has = { 768, 5487, 24858, 33891, 1784, 2457, 71, 2458, 15473 },
    bonus = { WARRIOR = { 1, 2, 3 }, DRUID = { 1, 2, 3, 4 }, ROGUE = { 1 }, PRIEST = { 1 }, MAGE = {} } },
  { name = "MoP Classic", gameMode = 5,
    has = { 768, 5487, 24858, 33891, 1784, 51713, 2457, 71, 2458, 15473, 103985, 115069, 115070 },
    bonus = { WARRIOR = {}, DRUID = { 1, 3, 4 }, ROGUE = { 1, 2 }, PRIEST = { 1 }, MONK = { 1, 2, 3 }, MAGE = {} } },
  { name = "WoW Forever", gameMode = 12, forever = true,
    has = { 768, 5487, 24858, 1784, 2457, 71, 2458, 15473 },
    bonus = { WARRIOR = { 1, 2, 3 }, DRUID = { 1, 3 }, ROGUE = { 1 }, PRIEST = {}, MAGE = {} } },
  { name = "Retail", gameMode = 12,
    has = { 768, 5487, 24858, 33891, 1784 },
    bonus = { WARRIOR = {}, DRUID = { 1, 3, 4 }, ROGUE = { 1 }, PRIEST = {}, MONK = {}, MAGE = {} } },
}

-- A client with one character logged in: the stance code loaded into it.
local function login(client, classfile)
  local has = {}
  for _, id in ipairs(client.has) do has[id] = true end
  local env
  env = setmetatable({
    GSE = {
      GameMode = client.gameMode, IsForever = client.forever or nil,
      L = setmetatable({}, { __index = function(_, k) return k end }),
      GetSpellInfo = function(id) return has[id] and { name = SPELLS[id] } or nil end,
      GetCurrentClassID = function() return 1 end,
      ButtonOverrides = {}, ButtonOverrideDefaults = {}, ButtonOverrideStates = {},
    },
    GetClassInfo = function() return classfile, classfile end,
    UnitClass = function() return classfile, classfile end,
    RegisterStateDriver = function() end,
  }, { __index = { string = string, table = table, math = math, pairs = pairs, ipairs = ipairs, type = type,
    tostring = tostring, tonumber = tonumber, select = select, setmetatable = setmetatable, pcall = pcall,
    rawget = rawget, next = next } })
  env._G = env
  -- hooksecurefunc as WoW has it: the global is replaced, so a caller holding
  -- the function from before (EllesmereUI) is not seen.
  env.hooksecurefunc = function(name, hook)
    local original = env[name]
    env[name] = function(...) original(...) hook(...) end
  end
  compile(STANCE_CODE, "stance code", env)()
  return env
end

-- A button as its bar addon builds it. bonus: the bonus bar the player's
-- stance has up now (0: none).
local function newButton(env, name, shape)
  local b = { attrs = shape.attrs or {} }
  function b:GetName() return name end
  function b:GetID() return shape.id or 0 end
  function b:GetAttribute(k) return self.attrs[k] end
  function b:GetParent() return shape.parent end
  if shape.dominos then b.SetShowGridInsecure = function() end end
  if shape.lab then b.SetState = function() end b.state_types = shape.lab end
  b.shape = shape
  env[name] = b
  return b
end
local function slotOnBonus(bonus) return 1 + (6 + bonus - 1) * 12 end

-- Blizzard's main bar: paged in C, the slot it shows in the .action field,
-- its page from the bar (actionpage, 1).
local function blizzardMainBar(env)
  return newButton(env, "ActionButton1", { id = 1, attrs = { actionpage = 1 },
    turn = function(b, bonus) b.action = bonus > 0 and slotOnBonus(bonus) or 1 end })
end
-- Blizzard's Action Bar 2: slots 61-72, whatever the stance.
local function blizzardBar2(env)
  return newButton(env, "MultiBarBottomLeftButton1", { id = 1, attrs = { actionpage = 6 },
    turn = function(b) b.action = 61 end })
end
-- Dominos' first bar (button.lua, bar.lua): id 0, the slot in the "action"
-- attribute, the bar paging by a driver of states Dominos names itself.
local function dominosMainBar(env)
  local bar = {}
  env.RegisterStateDriver(bar, "page", "[bonusbar:1,stealth]prowl;[bonusbar:1]cat;[bonusbar:3]bear;base")
  return newButton(env, "DominosActionButton1", { dominos = true, parent = bar, attrs = { ["action-base"] = 1 },
    turn = function(b, bonus) b.attrs.action = bonus > 0 and slotOnBonus(bonus) or 1 end })
end
-- A Dominos bar set on the bonus-bar slots (addressMap.lua: addresses 109-156
-- are slots 73-120): an ordinary bar that never turns.
local function dominosBarOnBonusSlots(env)
  return newButton(env, "DominosActionButton109", { dominos = true, parent = {}, attrs = { ["action-base"] = 73 },
    turn = function(b) b.attrs.action = 73 end })
end
-- EllesmereUI's main bar (EUI_ActionBars_Secure.lua): id 0, the slot in the
-- "action" attribute. It registers its paging through a RegisterStateDriver
-- it took before GSE loaded (EUI_ActionBars_Bars.lua:15), so GSE sees none.
local function ellesmereMainBar(env)
  return newButton(env, "EABButton1", { parent = {}, attrs = {},
    turn = function(b, bonus) b.attrs.action = bonus > 0 and slotOnBonus(bonus) or 1 end })
end
-- DaylightUI's first bar (Buttons.lua): id 0, the slot in the "action"
-- attribute. Its driver is set up before GSE loads; unseen, its stances are
-- on Blizzard's pages (GSE.ButtonPagesWithForms).
local function daylightMainBar(env)
  return newButton(env, "DaylightUIBar1Button1", { parent = {}, attrs = {},
    turn = function(b, bonus) b.attrs.action = bonus > 0 and slotOnBonus(bonus) or 1 end })
end
-- A bar whose page driver GSE does see, pages 7-10 for the bonus bars.
local function driverPagedBar(env)
  local bar = {}
  env.RegisterStateDriver(bar, "page", "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; 1")
  return newButton(env, "EABButton1", { parent = bar, attrs = {},
    turn = function(b, bonus) b.attrs.action = bonus > 0 and slotOnBonus(bonus) or 1 end })
end

-- Put rows on a button as GSE does, and press it: what GSE says runs on it
-- now, and what the press does. rows: { default = true, pinned = { page } }.
local function press(env, button, bonus, rows)
  local GSE, name = env.GSE, button:GetName()
  button.shape.turn(button, bonus)
  GSE.ButtonOverrides[name] = rows.default and "DEFAULT" or "PINNED"
  GSE.ButtonOverrideDefaults[name] = rows.default or nil
  GSE.ButtonOverrideStates[name] = nil
  local attrs = button.attrs
  for k in pairs(attrs) do if k:find("^gse%-") or k == "type" then attrs[k] = nil end end
  attrs["gse-secure"] = true
  if GSE.TestIsBonusPaged(button) then attrs["gse-bonus-paged"] = true end
  for _, page in ipairs(rows.pinned or {}) do
    GSE.ButtonOverrideStates[name] = GSE.ButtonOverrideStates[name] or {}
    GSE.ButtonOverrideStates[name][tostring(page)] = "PINNED" .. page
    attrs["gse-page-" .. page] = true
  end
  if rows.default then
    -- armRow: the Default row, and the marks GSE.ButtonStancePages gives it.
    attrs["gse-default"] = true
    for page in pairs(GSE.ButtonStancePages(name)) do attrs["gse-stance-" .. page] = true end
  end
  local shown = GSE.ButtonOverrideSequence(name)
  local renamed = compile(ONCLICK, "BAR_SWAP_ONCLICK", {
    floor = math.floor, tonumber = tonumber,
    GetBonusBarOffset = function() return bonus end,
    GetActionInfo = function() return nil end,
    self = {
      GetID = function() return button:GetID() end,
      GetEffectiveAttribute = function(_, k) return attrs[k] end,
      GetAttribute = function(_, k) return attrs[k] end,
      SetAttribute = function(_, k, v) attrs[k] = v end,
    },
  })()
  local pressed
  if attrs.type == "click" then pressed = renamed and ("PINNED" .. renamed:match("^gse(%d+)$")) or "DEFAULT" end
  return shown, pressed
end

describe("Stance bars on every client and bar addon", function()
  it("arms the Default row with GSE.ButtonStancePages, the pages what GSE shows reads too", function()
    local arm = between(events, "local function armRow(button, buttonName, sequenceName, state)", "\nend\n")
    assert.truthy(arm:find("GSE.ButtonStancePages(buttonName)", 1, true))
    assert.truthy(arm:find("secureArmGSEButton(button, sequenceName, true, stancePages)", 1, true))
    local armed = between(events, "local function secureArmGSEButton(button, sequenceName, asDefault, stancePages)", "\nend\n")
    assert.truthy(armed:find('for page = 1, 10 do b:SetAttribute("gse-stance-" .. page, nil) end', 1, true),
      "marks from before go when the row is armed again")
    local now = between(profiles, "function GSE.ButtonOverrideSequence(buttonName)", "\nend\n")
    assert.truthy(now:find("GSE.ButtonStancePages(buttonName)[tonumber(st)]", 1, true))
  end)

  for _, client in ipairs(CLIENTS) do
    describe(client.name, function()
      for classfile, bonuses in pairs(client.bonus) do
        it(classfile .. ": every stance bar it has is a State to choose, on Blizzard's bar and Dominos'", function()
          for _, build in ipairs({ blizzardMainBar, dominosMainBar }) do
            local env = login(client, classfile)
            local states = env.GSE.OverrideStatesFor(build(env):GetName())
            for _, bonus in ipairs(bonuses) do
              local page = tostring(6 + bonus)
              assert.truthy(states and states[page] and states[page] ~= page,
                classfile .. " bonus bar " .. bonus .. " has no name on " .. client.name)
            end
          end
        end)

        it(classfile .. ": a press and what GSE shows agree, on every bar, in every stance", function()
          -- What turns to a stance bar: the Default row stays off it there.
          local turning = { blizzardMainBar, dominosMainBar, daylightMainBar, driverPagedBar }
          -- What does not: the Default row runs whatever the stance.
          local still = { blizzardBar2, dominosBarOnBonusSlots, ellesmereMainBar }
          local stances = { 0 }
          for _, bonus in ipairs(bonuses) do stances[#stances + 1] = bonus end
          for _, bonus in ipairs(stances) do
            local page = 6 + bonus
            for _, build in ipairs(turning) do
              local env = login(client, classfile)
              local b = build(env)
              local where = b:GetName() .. " bonus " .. bonus
              local shown, pressed = press(env, b, bonus, { default = true })
              assert.are.equal(tostring(shown), tostring(pressed), "Default only, " .. where)
              if bonus == 0 then
                assert.are.equal("DEFAULT", shown, "the bar itself, " .. where)
              else
                assert.is_nil(shown, "the stance bar is its own, " .. where)
                shown, pressed = press(env, b, bonus, { default = true, pinned = { page } })
                assert.are.equal("PINNED" .. page, shown, "its own row, " .. where)
                assert.are.equal(shown, pressed, "its own row, " .. where)
                shown, pressed = press(env, b, 0, { default = true, pinned = { page } })
                assert.are.equal("DEFAULT", shown, "out of it again, " .. where)
                assert.are.equal(shown, pressed, "out of it again, " .. where)
                shown, pressed = press(env, b, 0, { pinned = { page } })
                assert.is_nil(shown, "a stance's row is not the bar's, " .. where)
                assert.is_nil(pressed, "a stance's row is not the bar's, " .. where)
              end
            end
            for _, build in ipairs(still) do
              local env = login(client, classfile)
              local b = build(env)
              local where = b:GetName() .. " bonus " .. bonus
              local shown, pressed = press(env, b, bonus, { default = true })
              assert.are.equal("DEFAULT", shown, "a bar that turns to no other, " .. where)
              assert.are.equal(shown, pressed, "a bar that turns to no other, " .. where)
            end
          end
        end)
      end

      it("keeps the Default row in every state of a LibActionButton bar (Bartender4, ElvUI, NDui, ConsolePort)", function()
        local env = login(client, "DRUID")
        local b = newButton(env, "BT4Button1", { lab = { ["0"] = "action", ["7"] = "action", ["9"] = "action" },
          attrs = { state = "7" }, turn = function() end })
        env.GSE.ButtonOverrides.BT4Button1, env.GSE.ButtonOverrideDefaults.BT4Button1 = "DEFAULT", true
        assert.are.same({}, env.GSE.ButtonStancePages("BT4Button1"))
        assert.are.equal("DEFAULT", env.GSE.ButtonOverrideSequence("BT4Button1"))
        env.GSE.ButtonOverrideStates.BT4Button1 = { ["7"] = "CAT" }
        assert.are.equal("CAT", env.GSE.ButtonOverrideSequence("BT4Button1"))
        b.attrs.state = "9"
        assert.are.equal("DEFAULT", env.GSE.ButtonOverrideSequence("BT4Button1"))
      end)
    end)
  end

  it("a Dominos bar set on the bonus-bar slots keeps its Default row, and a row pinned there", function()
    local env = login(CLIENTS[5], "ROGUE")
    local b = dominosBarOnBonusSlots(env)
    assert.are.same({ [8] = true, [9] = true, [10] = true }, env.GSE.ButtonStancePages(b:GetName()),
      "its own page (7) is no stance page of its")
    local shown, pressed = press(env, b, 1, { default = true, pinned = { 7 } })
    assert.are.equal("PINNED7", shown)
    assert.are.equal(shown, pressed)
  end)
end)
