local ADDON, ns = ...

local UI = { icons = {} }
ns.UI = UI

local Rotation = ns.Rotation

local ICON_SIZE_PRIMARY   = 60
local ICON_SIZE_SECONDARY = 38
local ICON_GAP            = 8
local PRIMARY_GLOW_PAD    = 6
local UPDATE_FREQ         = 0.2

local CLASS_COLORS = RAID_CLASS_COLORS

local function GetSpellIconPath(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    return _G.GetSpellTexture and _G.GetSpellTexture(spellID) or nil
end

local function iconSizeAt(index)
    return (index == 1) and ICON_SIZE_PRIMARY or ICON_SIZE_SECONDARY
end

local function applyPos(frame, pos)
    frame:ClearAllPoints()
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 0)
end

local function createAnchor()
    local f = CreateFrame("Frame", "AutoCCAnchor", UIParent)
    f:SetSize(ICON_SIZE_PRIMARY, ICON_SIZE_PRIMARY)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    f.bg = bg

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("BOTTOM", f, "TOP", 0, 4)
    label:SetText("autocc — drag to move")
    f.label = label

    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        ns.db.position = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)

    return f
end

local function createIcon(parent, index, isPrimary)
    local size = isPrimary and ICON_SIZE_PRIMARY or ICON_SIZE_SECONDARY
    local btn = CreateFrame("Frame", "AutoCCIcon" .. index, parent)
    btn:SetSize(size, size)
    btn.isPrimary = isPrimary

    -- Outer glow for the primary slot.
    if isPrimary then
        local glow = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
        glow:SetPoint("TOPLEFT", -PRIMARY_GLOW_PAD, PRIMARY_GLOW_PAD)
        glow:SetPoint("BOTTOMRIGHT", PRIMARY_GLOW_PAD, -PRIMARY_GLOW_PAD)
        glow:SetColorTexture(1, 0.8, 0.25, 0.55)
        glow:SetBlendMode("ADD")
        btn.glow = glow
    end

    local borderWidth = isPrimary and 2 or 1
    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -borderWidth, borderWidth)
    border:SetPoint("BOTTOMRIGHT", borderWidth, -borderWidth)
    border:SetColorTexture(1, 1, 1, 1)
    btn.border = border

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = tex

    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetHideCountdownNumbers(false)
    btn.cd = cd

    -- Player name below the icon.
    local nameText = btn:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(STANDARD_TEXT_FONT, isPrimary and 13 or 10, "OUTLINE")
    nameText:SetPoint("TOP", btn, "BOTTOM", 0, -3)
    nameText:SetWidth(size + 40)
    nameText:SetWordWrap(false)
    btn.nameText = nameText

    -- Effective duration text on top of the icon.
    local durText = btn:CreateFontString(nil, "OVERLAY")
    durText:SetFont(STANDARD_TEXT_FONT, isPrimary and 20 or 13, "OUTLINE")
    durText:SetPoint("CENTER", btn, "CENTER", 0, 0)
    durText:SetShadowColor(0, 0, 0, 1)
    durText:SetShadowOffset(1, -1)
    btn.durText = durText

    -- "NEXT" label above the primary icon.
    if isPrimary then
        local nextLabel = btn:CreateFontString(nil, "OVERLAY")
        nextLabel:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        nextLabel:SetPoint("BOTTOM", btn, "TOP", 0, 4)
        nextLabel:SetText("NEXT")
        nextLabel:SetTextColor(1, 0.85, 0.3)
        btn.nextLabel = nextLabel
    end

    return btn
end

function UI:Build()
    if self.anchor then return end
    self.anchor = createAnchor()
    applyPos(self.anchor, ns.db.position)
    self.anchor:SetScale(ns.db.scale or 1)
end

function UI:LayoutIcons(count)
    count = math.max(0, count)
    local horizontal = (ns.db and ns.db.layout) ~= "vertical"

    -- Allocate / reuse icons.
    for i = 1, count do
        local wantPrimary = (i == 1)
        local icon = self.icons[i]
        if not icon or icon.isPrimary ~= wantPrimary then
            if icon then icon:Hide(); icon:SetParent(nil) end
            icon = createIcon(self.anchor, i, wantPrimary)
            self.icons[i] = icon
        end
        icon:ClearAllPoints()
    end
    for i = count + 1, #self.icons do
        self.icons[i]:Hide()
    end

    -- Position along the layout axis. Secondary icons are centered on the
    -- orthogonal axis so they read as a smaller "queue" hanging off the primary.
    local offset = 0
    for i = 1, count do
        local icon = self.icons[i]
        local size = iconSizeAt(i)

        if horizontal then
            icon:SetPoint("LEFT", self.anchor, "LEFT", offset, 0)
        else
            icon:SetPoint("TOP", self.anchor, "TOP", 0, -offset)
        end
        icon:Show()

        offset = offset + size + ICON_GAP
    end

    -- Anchor extent along the main axis equals the sum of icon sizes + gaps,
    -- minus the trailing gap.
    local mainExtent = math.max(1, offset - ICON_GAP)
    if horizontal then
        self.anchor:SetSize(mainExtent, ICON_SIZE_PRIMARY)
    else
        self.anchor:SetSize(ICON_SIZE_PRIMARY, mainExtent)
    end
end

local function paintIcon(icon, suggestion)
    if not icon or not suggestion then return end
    local entry  = suggestion.entry
    local member = suggestion.member
    if not entry or not member then return end

    icon.icon:SetTexture(GetSpellIconPath(entry.id) or entry.icon or 134400)

    local color = CLASS_COLORS[member.class] or { r = 1, g = 1, b = 1 }
    icon.border:SetColorTexture(color.r, color.g, color.b, 1)

    local shortName = (member.name or "?"):match("^[^-]+") or member.name or "?"
    icon.nameText:SetText(shortName)
    icon.nameText:SetTextColor(color.r, color.g, color.b)

    if suggestion.effective and suggestion.effective > 0 then
        icon.durText:SetText(("%.0fs"):format(suggestion.effective))
        icon.durText:SetTextColor(1, 0.95, 0.5)
    else
        icon.durText:SetText("")
    end

    if suggestion.readyIn and suggestion.readyIn > 0 then
        icon.cd:SetCooldown(GetTime() - (entry.cooldown - suggestion.readyIn), entry.cooldown)
        icon.icon:SetDesaturated(true)
        icon.icon:SetVertexColor(0.55, 0.55, 0.55)
        -- Dim the glow if primary is waiting on CD.
        if icon.glow then icon.glow:SetAlpha(0.25) end
    else
        icon.cd:Clear()
        icon.icon:SetDesaturated(false)
        icon.icon:SetVertexColor(1, 1, 1)
        if icon.glow then icon.glow:SetAlpha(1) end
    end
end

function UI:Refresh()
    if not self.anchor then return end
    if not ns.db.enabled then self.anchor:Hide(); return end

    local inCombat = InCombatLockdown()
    if not inCombat and not ns.db.showOutOfCombat and ns.db.locked then
        self.anchor:Hide()
        return
    end
    self.anchor:Show()

    self.anchor.bg:SetShown(not ns.db.locked)
    self.anchor.label:SetShown(not ns.db.locked)
    self.anchor:EnableMouse(not ns.db.locked)

    local suggestions = Rotation:Suggest(ns.db.queueLength)
    self:LayoutIcons(#suggestions)
    for i, s in ipairs(suggestions) do
        paintIcon(self.icons[i], s)
    end
end

local elapsed = 0
local function onUpdate(_, dt)
    elapsed = elapsed + dt
    if elapsed >= UPDATE_FREQ then
        elapsed = 0
        UI:Refresh()
    end
end

ns:On("DB_READY", function()
    UI:Build()
    UI.anchor:SetScript("OnUpdate", onUpdate)
end)

ns:On("LOCK_CHANGED",   function() UI:Refresh() end)
ns:On("POSITION_RESET", function() applyPos(UI.anchor, ns.db.position); UI:Refresh() end)
ns:On("LAYOUT_CHANGED", function() UI:Refresh() end)

ns:On("TEST", function()
    UI:LayoutIcons(3)
    local pname  = UnitName("player")
    local pclass = select(2, UnitClass("player"))
    local fake = {
        { entry = ns.Database:GetByCastID(119381), member = { name = pname, class = pclass, unit = "player" }, effective = 3,  readyIn = 0 },
        { entry = ns.Database:GetByCastID(207684), member = { name = pname, class = pclass, unit = "player" }, effective = 10, readyIn = 0 },
        { entry = ns.Database:GetByCastID(179057), member = { name = pname, class = pclass, unit = "player" }, effective = 1,  readyIn = 12 },
    }
    for i, s in ipairs(fake) do
        if s.entry then paintIcon(UI.icons[i], s) end
    end
    UI.anchor:Show()
end)
