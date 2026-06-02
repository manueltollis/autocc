local ADDON, ns = ...

-- DR categories. 18s window shared per (target, category).
local CAT = {
    STUN        = "STUN",
    DISORIENT   = "DISORIENT",
    INCAP       = "INCAP",
    SILENCE     = "SILENCE",
    KNOCKBACK   = "KNOCKBACK",   -- not DR'd but tracked for rotation ordering
}
ns.CAT = CAT

-- Canonical AoE-CC list (matches the original WA scope).
--
-- Fields:
--   id        - cast spell id (matches UNIT_SPELLCAST_SUCCEEDED's spellID)
--   auraIDs   - extra aura ids that may appear on the enemy if different from cast id
--   name      - display name fallback
--   class     - WoW class token
--   cat       - DR category
--   duration  - base CC duration in seconds (0 for pure knockback/displacement)
--   cooldown  - base cooldown in seconds
--   priority  - tiebreaker weight; higher = preferred when score is close
local SPELLS = {
    -- Stuns
    { id = 192058, name = "Capacitor Totem",   class = "SHAMAN",       cat = CAT.STUN,      duration = 3, cooldown = 60, priority = 95, auraIDs = { 118905 } },
    { id = 179057, name = "Chaos Nova",        class = "DEMONHUNTER",  cat = CAT.STUN,      duration = 2, cooldown = 45, priority = 90 },
    { id = 119381, name = "Leg Sweep",         class = "MONK",         cat = CAT.STUN,      duration = 3, cooldown = 60, priority = 95 },
    { id = 46968,  name = "Shockwave",         class = "WARRIOR",      cat = CAT.STUN,      duration = 2, cooldown = 40, priority = 90 },
    { id = 30283,  name = "Shadowfury",        class = "WARLOCK",      cat = CAT.STUN,      duration = 3, cooldown = 60, priority = 95 },

    -- Disorients
    { id = 8122,   name = "Psychic Scream",    class = "PRIEST",       cat = CAT.DISORIENT, duration = 8, cooldown = 60, priority = 90 },
    { id = 115750, name = "Blinding Light",    class = "PALADIN",      cat = CAT.DISORIENT, duration = 6, cooldown = 90, priority = 85 },
    { id = 2094,   name = "Blind",             class = "ROGUE",        cat = CAT.DISORIENT, duration = 6, cooldown = 120, priority = 70 }, -- AoE only with Airborne Irritant talent
    { id = 31661,  name = "Dragon's Breath",   class = "MAGE",         cat = CAT.DISORIENT, duration = 4, cooldown = 45, priority = 80 },
    { id = 5246,   name = "Intimidating Shout",class = "WARRIOR",      cat = CAT.DISORIENT, duration = 8, cooldown = 90, priority = 85 },
    { id = 207167, name = "Blinding Sleet",    class = "DEATHKNIGHT",  cat = CAT.DISORIENT, duration = 5, cooldown = 60, priority = 80 },
    { id = 207684, name = "Sigil of Misery",   class = "DEMONHUNTER",  cat = CAT.DISORIENT, duration = 20, cooldown = 90, priority = 90, auraIDs = { 207685 } },

    -- Incapacitates
    { id = 99,     name = "Incapacitating Roar", class = "DRUID",      cat = CAT.INCAP,     duration = 3, cooldown = 30, priority = 80 },

    -- Silences
    { id = 202137, name = "Sigil of Silence",  class = "DEMONHUNTER",  cat = CAT.SILENCE,   duration = 6, cooldown = 60, priority = 75, auraIDs = { 204490 } },

    -- Knockbacks / displacements (no CC duration, used for positioning / pushing out of casts)
    { id = 368970, name = "Tail Swipe",        class = "EVOKER",       cat = CAT.KNOCKBACK, duration = 0, cooldown = 180, priority = 70 },
    { id = 357214, name = "Wing Buffet",       class = "EVOKER",       cat = CAT.KNOCKBACK, duration = 0, cooldown = 180, priority = 70 },
    { id = 385952, name = "Sundering",         class = "WARRIOR",      cat = CAT.KNOCKBACK, duration = 0, cooldown = 40, priority = 55 },
    { id = 157981, name = "Blast Wave",        class = "MAGE",         cat = CAT.KNOCKBACK, duration = 0, cooldown = 30, priority = 50 },
    { id = 51490,  name = "Thunderstorm",      class = "SHAMAN",       cat = CAT.KNOCKBACK, duration = 0, cooldown = 45, priority = 50 },
    { id = 132469, name = "Typhoon",           class = "DRUID",        cat = CAT.KNOCKBACK, duration = 0, cooldown = 30, priority = 55 },
    { id = 116844, name = "Ring of Peace",     class = "MONK",         cat = CAT.KNOCKBACK, duration = 0, cooldown = 45, priority = 55 },
    { id = 202138, name = "Sigil of Chains",   class = "DEMONHUNTER",  cat = CAT.KNOCKBACK, duration = 0, cooldown = 90, priority = 55 },
}

local byID, byAuraID, byClass = {}, {}, {}
for i = 1, #SPELLS do
    local s = SPELLS[i]
    byID[s.id] = s
    if s.auraIDs then
        for _, aid in ipairs(s.auraIDs) do byAuraID[aid] = s end
    end
    byAuraID[s.id] = byAuraID[s.id] or s
    byClass[s.class] = byClass[s.class] or {}
    table.insert(byClass[s.class], s)
end

ns.Database = {
    spells   = SPELLS,
    byID     = byID,
    byAuraID = byAuraID,
    byClass  = byClass,
    drMultipliers = { [0] = 1.0, [1] = 0.5, [2] = 0.25, [3] = 0.0 },
    drWindow      = 18.0,
}

local function isSecret(v)
    return v ~= nil and _G.issecretvalue and _G.issecretvalue(v)
end

function ns.Database:GetByCastID(id)
    if id == nil or isSecret(id) then return nil end
    return self.byID[id]
end

function ns.Database:GetByAuraID(id)
    -- Midnight obfuscates aura spellIDs on hostile units into "secret values"
    -- that crash table indexing. Guard against that here.
    if id == nil or isSecret(id) then return nil end
    return self.byAuraID[id]
end

-- Localized-name fallback. Built lazily because C_Spell.GetSpellInfo isn't
-- guaranteed to be ready at addon load. Names from the client locale match
-- both sides (our DB lookup and the aura `name` field), so this works in any
-- language without us hardcoding translations.
local nameLookup
function ns.Database:GetByAuraName(name)
    if not name or name == "" then return nil end
    if not nameLookup then
        nameLookup = {}
        if C_Spell and C_Spell.GetSpellInfo then
            for id, entry in pairs(self.byAuraID) do
                local info = C_Spell.GetSpellInfo(id)
                local resolvedName = info and info.name
                if resolvedName then nameLookup[resolvedName] = entry end
            end
        end
    end
    return nameLookup[name]
end

function ns.Database:GetForClass(class)  return self.byClass[class] or {} end
function ns.Database:DRMultiplier(applicationCount)
    return self.drMultipliers[applicationCount] or 0.0
end
