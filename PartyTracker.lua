local ADDON, ns = ...

-- PartyTracker maintains, for every party member (incl. player), the set of CC spells
-- they own (based on class) and the next-ready time for each spell.
--
-- Note: In WoW Midnight (12.0+) CLEU is restricted in boss/M+ encounters, so we use
-- UNIT_SPELLCAST_SUCCEEDED (unit-based event) which is the official replacement.

local Tracker = { members = {} }
ns.PartyTracker = Tracker

local Database = ns.Database

local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local PARTY_UNIT_SET = {}
for _, u in ipairs(PARTY_UNITS) do PARTY_UNIT_SET[u] = true end

local function buildSpellsFor(class)
    local out = {}
    for _, entry in ipairs(Database:GetForClass(class)) do
        if (entry.priority or 0) > 0 then
            out[entry.id] = { entry = entry, readyAt = 0 }
        end
    end
    return out
end

local function unitInfo(unit)
    if not UnitExists(unit) then return nil end
    local name = GetUnitName(unit, true) or UnitName(unit)
    local _, class = UnitClass(unit)
    if not class then return nil end
    return {
        unit  = unit,
        name  = name,
        class = class,
        spells = buildSpellsFor(class),
    }
end

function Tracker:Refresh()
    self.members = {}
    for _, unit in ipairs(PARTY_UNITS) do
        local info = unitInfo(unit)
        if info then
            self.members[unit] = info
        end
    end
    ns:Fire("ROSTER_CHANGED")
end

function Tracker:GetMemberByUnit(unit)
    return self.members[unit]
end

function Tracker:GetAvailable(lookahead)
    lookahead = lookahead or 0
    local now = GetTime()
    local blacklist = (ns.db and ns.db.blacklist) or {}
    local out = {}
    for _, member in pairs(self.members) do
        for spellID, slot in pairs(member.spells) do
            if not blacklist[spellID] then
                local readyIn = math.max(0, slot.readyAt - now)
                if readyIn <= lookahead then
                    out[#out + 1] = {
                        member  = member,
                        entry   = slot.entry,
                        readyAt = slot.readyAt,
                        readyIn = readyIn,
                    }
                end
            end
        end
    end
    return out
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

frame:SetScript("OnEvent", function(_, event, arg1, _, spellID)
    if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        Tracker:Refresh()
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = arg1
        if not PARTY_UNIT_SET[unit] then return end

        local member = Tracker:GetMemberByUnit(unit)
        if not member then return end

        local slot = member.spells[spellID]
        if not slot then return end

        local entry = slot.entry
        slot.readyAt = GetTime() + (entry.cooldown or 0)

        ns:Fire("CD_STARTED", member, entry, slot.readyAt)
    end
end)

ns:On("LOGIN", function() Tracker:Refresh() end)
