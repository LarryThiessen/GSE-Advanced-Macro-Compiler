
-- Seven entries in Statics.SpecIDList are disambiguated as "Frost - Mage",
-- because Frost is both a Mage and a Death Knight spec. Either half comes from
-- the client's CONTENT, and a client can have the specialisation API while
-- having no such spec or class to report.
--
-- That is WoW Forever: Retail's API surface on vanilla content, so GameMode is
-- honestly 12, the retail branch is entered, GetSpecializationInfoByID(64) has
-- no Frost Mage to return, and concatenating the nil threw
-- "attempt to concatenate a nil value" as soon as a sequence was created.
--
-- Lifted from the shipped file, so changing it there fails this.
-- .gitattributes marks *.lua eol=crlf; normalise on read (see CLAUDE.md).
local function liftSpecWithClass(specName, className)
    local fh = assert(io.open("GSE/API/Statics.lua", "r"), "cannot open GSE/API/Statics.lua")
    local src = fh:read("*a")
    fh:close()
    src = (src:gsub("\r\n", "\n"):gsub("\r", "\n"))
    local block = src:match("(local function specWithClass.-return className and %(specName %.%. \" %- \" %.%. className%) or specName)")
    assert(block, "specWithClass not found in Statics.lua -- did it get rewritten?")
    local compile = loadstring or load
    -- Inject the two lookups the helper closes over.
    local chunk = assert(compile(
        "local determineSpecializationName, determineClassName = ...\n"
        .. block .. "\nend\nreturn specWithClass"))
    return chunk(function() return specName end, function() return className end)
end

-- Mists of Pandaria is on the class-only list, as the clients before it are
-- (#2236). The list after it names a spec through
-- determineSpecializationName, which gives a class id -- a number -- below
-- Legion; the editor's Specialization dropdown sorts by name and stopped on
-- it, so a sequence's Configuration page ended after Author.
describe("the class and spec list", function()
    local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Death Knight", "Shaman", "Mage",
        "Warlock", "Monk", "Druid" }

    -- buildSpecList as the shipped file has it, on a client of this GameMode.
    local function build(gameMode)
        local fh = assert(io.open("GSE/API/Statics.lua", "r"), "cannot open GSE/API/Statics.lua")
        local src = fh:read("*a")
        fh:close()
        src = (src:gsub("\r\n", "\n"):gsub("\r", "\n"))
        local body = assert(src:match("\nlocal function buildSpecList%(%)\n(.-)\nend\n"), "buildSpecList not found")
        local compile = loadstring or load
        local chunk = assert(compile("local Statics, GSE, L, determineClassName, determineSpecializationName, "
            .. "specWithClass, deriveClassTreeSpecs, specListBuilt = ...\n" .. body))
        local Statics = { SpecIDList = {}, SpecIDHashList = {}, SpecIDIconList = {} }
        local classIDs = { [62] = 8, [63] = 8, [64] = 8, [259] = 4, [268] = 10 }
        local function specName(id)
            -- As the shipped determineSpecializationName answers below Legion.
            if gameMode < 7 then return classIDs[id] end
            return "Spec " .. id
        end
        chunk(Statics, { GameMode = gameMode, SpecIDClassList = {} }, { Global = "Global" },
            function(id) return CLASSES[id] end, specName,
            function(id) return specName(id) end, function() return nil end, false)
        return Statics.SpecIDList
    end

    it("is classes only on Mists of Pandaria, the monk among them", function()
        local list = build(5)
        for id = 1, 11 do assert.equals(CLASSES[id], list[id]) end
        for id in pairs(list) do assert.is_true(id <= 13, "a spec is listed: " .. id) end
    end)

    it("names nothing with a number, on any client", function()
        for _, gameMode in ipairs({ 1, 2, 3, 4, 5, 11, 12 }) do
            for id, name in pairs(build(gameMode)) do
                assert.equals("string", type(name), "GameMode " .. gameMode .. ", id " .. id)
            end
        end
    end)

    it("leaves the earlier clients' classes as they were", function()
        assert.is_nil(build(1)[6], "no death knight in Classic Era")
        assert.is_nil(build(2)[10], "no monk in The Burning Crusade")
        assert.equals("Death Knight", build(3)[6])
        assert.is_nil(build(4)[10], "no monk in Cataclysm")
    end)

    it("still lists specs from Legion on", function()
        local list = build(12)
        assert.equals("Spec 62", list[62])
        assert.equals("Monk", list[10])
    end)
end)

describe("specWithClass", function()
    it("joins spec and class when the client has both", function()
        local f = liftSpecWithClass("Frost", "Mage")
        assert.equals("Frost - Mage", f(64, 8))
    end)

    -- Forever: the API exists, the content does not.
    it("returns nil when the client has no such spec", function()
        local f = liftSpecWithClass(nil, "Mage")
        assert.is_nil(f(64, 8), "no spec means no entry, not a concatenation error")
    end)

    -- Death Knight on vanilla content: C_CreatureInfo has no class 6.
    it("falls back to the bare spec name when the class is absent", function()
        local f = liftSpecWithClass("Frost", nil)
        assert.equals("Frost", f(251, 6))
    end)

    it("returns nil when the client has neither", function()
        local f = liftSpecWithClass(nil, nil)
        assert.is_nil(f(64, 8))
    end)

    -- The point of returning nil rather than a placeholder: the key is never
    -- set, so a client without specialisations ends up with the class-only
    -- list it should have, instead of rows reading "- Mage" or "Unknown".
    it("never yields a half-built label", function()
        local f = liftSpecWithClass(nil, "Mage")
        local out = f(64, 8)
        assert.is_nil(out)
        f = liftSpecWithClass("Frost", nil)
        assert.equals("Frost", f(64, 8))
    end)
end)
