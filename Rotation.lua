local ADDON, ns = ...

-- Rotation.Compute(targetGUID, queueLength) -> array of suggestion entries
--
-- Each entry: {
--     member   = <party member table>,
--     entry    = <spell db entry>,
--     effective = <DR-adjusted CC duration in seconds>,
--     readyIn  = <seconds until off-CD; 0 if ready now>,
--     score    = <numeric score>,
-- }
--
-- Algorithm:
--   * Snapshot DR state for the target into a local mutable copy (we don't touch real DR).
--   * For each queue slot 1..N:
--       - Consider every (member, spell) pair across the party.
--       - Skip pairs already chosen in this rotation.
--       - readyIn = how long until the ability is castable.
--       - cat = DR category. effDur = baseDur * drMultiplier(localCount[cat])
--       - score = effDur * priorityWeight - readyIn * cooldownPenalty
--           + bonus for using a category not yet DR'd in this chain
--       - Knockback (effDur 0) only used as filler if nothing better.
--   * Commit best, increment local DR count for its category, advance "now".

local R = {}
ns.Rotation = R

local Database    = ns.Database
local CAT         = ns.CAT
local DRTracker   = ns.DRTracker
local PartyTracker= ns.PartyTracker

-- Scoring philosophy: every "real CC" (duration > 0) is roughly equivalent —
-- the goal is preventing one cast or one melee swing, not locking down for as long
-- as possible. So we don't reward longer durations beyond a small cap.
-- Knockbacks are weaker (no actual disable) and get a lower base score.
local CC_BASE_SCORE       = 10.0   -- base score for a usable real CC
local KNOCKBACK_BASE_SCORE= 2.0    -- knockback / displacement
local DURATION_CAP        = 4.0    -- effective duration beyond this gives diminishing returns
local DURATION_WEIGHT     = 0.2    -- small bonus per second up to cap
local PRIORITY_WEIGHT     = 0.05   -- entry priority -> score
local COOLDOWN_PENALTY    = 0.4    -- per second the ability is still on CD
local CATEGORY_DIVERSITY  = 5.0    -- big bonus for using a category not yet used in this chain
local DR_IMMUNE_SCORE     = -1000  -- never pick fully DR'd CCs

local function snapshotDR(unitToken)
    -- Build a shallow per-category count map from the live DR state.
    -- Keyed by unit token because Midnight makes UnitGUID a "secret value"
    -- that cannot be used as a Lua table key.
    local snap = {}
    if unitToken and DRTracker.state[unitToken] then
        local now = GetTime()
        for cat, slot in pairs(DRTracker.state[unitToken]) do
            if slot.expiry > now then
                snap[cat] = slot.count
            end
        end
    end
    return snap
end

local function scoreCandidate(member, entry, readyIn, drSnap, usedCats)
    local cat       = entry.cat
    local localCnt  = drSnap[cat] or 0
    local mult      = Database:DRMultiplier(localCnt)
    local baseDur   = entry.duration or 0
    local effDur    = baseDur * mult

    local score
    if baseDur == 0 then
        -- pure knockback / displacement
        score = KNOCKBACK_BASE_SCORE
    elseif effDur <= 0 then
        -- a CC that would land as immune in current DR state
        return DR_IMMUNE_SCORE, 0, mult
    else
        -- bounded duration bonus: a 3s stun ~ a 6s disorient; a 30s root would
        -- not get a 10x boost.
        local cappedDur = math.min(effDur, DURATION_CAP)
        score = CC_BASE_SCORE + cappedDur * DURATION_WEIGHT
        if not usedCats[cat] then
            score = score + CATEGORY_DIVERSITY
        end
    end

    score = score
          + (entry.priority or 0) * PRIORITY_WEIGHT
          - readyIn * COOLDOWN_PENALTY

    return score, effDur, mult
end

function R:Compute(targetUnit, queueLength, options)
    queueLength = queueLength or (ns.db and ns.db.queueLength) or 3
    options = options or {}
    local lookahead = options.lookahead or 60

    local available = PartyTracker:GetAvailable(lookahead)
    if #available == 0 then return {} end

    local drSnap   = snapshotDR(targetUnit)
    local usedCats = {}
    local result   = {}
    local taken    = {}   -- key = member.unit .. "|" .. spellID (unit tokens are plain strings; GUIDs may be secret)

    -- We simulate a moving "now" anchored to GetTime(); since we don't deduct the
    -- effective duration from time (chained CC overlap is the whole point), we only
    -- advance time by the *next* slot's expected wait — keeping greedy simple.
    for _ = 1, queueLength do
        local best, bestScore, bestEff, bestKey
        for _, cand in ipairs(available) do
            local key = cand.member.unit .. "|" .. cand.entry.id
            if not taken[key] then
                local s, eff = scoreCandidate(cand.member, cand.entry, cand.readyIn, drSnap, usedCats)
                if not best or s > bestScore then
                    best, bestScore, bestEff, bestKey = cand, s, eff, key
                end
            end
        end

        if not best then break end
        taken[bestKey] = true

        result[#result + 1] = {
            member    = best.member,
            entry     = best.entry,
            effective = bestEff,
            readyIn   = best.readyIn,
            score     = bestScore,
        }

        -- Commit the simulation effect: bump local DR count for this category and
        -- mark category as used in this chain.
        local cat = best.entry.cat
        if bestEff > 0 then
            drSnap[cat] = (drSnap[cat] or 0) + 1
            usedCats[cat] = true
        end
    end

    return result
end

-- Convenience: query DR state for the player's current target (unit token "target").
-- If the player has no target the snapshot is empty -> all CCs land fresh.
function R:Suggest(queueLength)
    return self:Compute(UnitExists("target") and "target" or nil, queueLength)
end
