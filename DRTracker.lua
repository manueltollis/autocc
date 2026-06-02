local ADDON, ns = ...

-- DRTracker tracks per-target per-DR-category diminishing returns state.
--
-- Midnight 12.0 obfuscates UnitGUID into "secret values" that cannot be used as
-- Lua table keys. So we key state by *unit token* (`target`, `nameplate1`, ...)
-- which is a plain string. The trade-off: if the same mob appears under multiple
-- tokens (e.g. nameplate3 + target) we may track it twice. For an M+ CC rotation
-- this is acceptable — the rotation queries DR for "target".
--
-- Replacement for CLEU: we observe CC applications by snapshotting harmful auras
-- on each unit (UNIT_AURA) and diffing against the previous snapshot. Anything
-- newly present in the snapshot counts as a fresh application of that CC.

local DR = {
    state = {},          -- state[unitToken][cat] = { count, expiry }
    seenAuras = {},      -- seenAuras[unitToken][auraSpellID] = entry
}
ns.DRTracker = DR

local Database = ns.Database
local CAT      = ns.CAT

local AURA_UNITS = {
    "target", "focus", "mouseover",
    "boss1", "boss2", "boss3", "boss4", "boss5",
}
do
    for i = 1, 40 do AURA_UNITS[#AURA_UNITS + 1] = "nameplate" .. i end
end

local function clean(now, slot)
    if slot and now > slot.expiry then
        slot.count = 0
        slot.expiry = 0
    end
end

function DR:Get(unitToken, cat)
    local g = self.state[unitToken]; if not g then return 0, 0 end
    local s = g[cat]; if not s then return 0, 0 end
    clean(GetTime(), s)
    return s.count, s.expiry
end

function DR:NextMultiplier(unitToken, cat)
    local count = self:Get(unitToken, cat)
    return Database:DRMultiplier(count)
end

function DR:Apply(unitToken, cat, effectiveDuration)
    if not unitToken or not cat then return end
    local now = GetTime()
    local g = self.state[unitToken]; if not g then g = {}; self.state[unitToken] = g end
    local s = g[cat]; if not s then s = { count = 0, expiry = 0 }; g[cat] = s end
    clean(now, s)
    s.count  = s.count + 1
    s.expiry = now + (effectiveDuration or 0) + Database.drWindow
end

function DR:Forget(unitToken)
    self.state[unitToken]     = nil
    self.seenAuras[unitToken] = nil
end

local function snapshotAuras(unit)
    -- Result is keyed by entry.id (our own static spellID, always a plain
    -- number) so we never put a Midnight secret value into a table key.
    local out = {}
    if not UnitExists(unit) then return out end
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return out end

    for i = 1, 40 do
        local data = C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
        if not data then break end
        -- spellId is a secret value for hostile auras in Midnight; lookup by
        -- name is the reliable path. Try spellId first for cheaper hits.
        local entry = Database:GetByAuraID(data.spellId)
                  or Database:GetByAuraName(data.name)
        if entry and (entry.duration or 0) > 0 and entry.cat ~= CAT.KNOCKBACK then
            out[entry.id] = entry
        end
    end
    return out
end

local function processUnit(unit)
    if not unit then return end
    if not UnitExists(unit) then return end
    if not UnitCanAttack("player", unit) then return end

    local current = snapshotAuras(unit)
    local prev = DR.seenAuras[unit] or {}

    for entryID, entry in pairs(current) do
        if not prev[entryID] then
            local count = DR:Get(unit, entry.cat)
            local mult  = Database:DRMultiplier(count)
            local effective = (entry.duration or 0) * mult
            DR:Apply(unit, entry.cat, effective)
            ns:Fire("DR_CHANGED", unit, entry.cat)
            if ns.db and ns.db.debug then
                ns:Print(("DR %s on %s -> count=%d, eff=%.1fs"):format(
                    entry.cat, unit, count + 1, effective))
            end
        end
    end

    DR.seenAuras[unit] = current
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        DR.state     = {}
        DR.seenAuras = {}
        return
    end

    if event == "NAME_PLATE_UNIT_REMOVED" then
        DR:Forget(unit)
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        -- The "target" token now points at a (potentially) different mob: wipe its slot.
        DR:Forget("target")
        processUnit("target")
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        DR:Forget("focus")
        processUnit("focus")
        return
    end

    if event == "NAME_PLATE_UNIT_ADDED" then
        processUnit(unit)
        return
    end

    if event == "UNIT_AURA" and unit then
        processUnit(unit)
    end
end)
