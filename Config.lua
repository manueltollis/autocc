local ADDON, ns = ...

-- Custom config window. Dark backdrop, subtle accent line, section for display
-- settings and a scrollable spell list (grouped by DR category) with per-spell
-- blacklist checkboxes.

local Panel = {}
ns.ConfigUI = Panel

local UI_W, UI_H = 500, 620
local PAD        = 16
local ROW_H      = 30

local CAT_ORDER = { "STUN", "DISORIENT", "INCAP", "SILENCE", "KNOCKBACK" }
local CAT_LABELS = {
    STUN      = "Stuns",
    DISORIENT = "Disorients",
    INCAP     = "Incapacitates",
    SILENCE   = "Silences",
    KNOCKBACK = "Knockbacks",
}
local CLASS_LABELS = {
    DEATHKNIGHT = "Death Knight",
    DEMONHUNTER = "Demon Hunter",
    DRUID       = "Druid",
    EVOKER      = "Evoker",
    HUNTER      = "Hunter",
    MAGE        = "Mage",
    MONK        = "Monk",
    PALADIN     = "Paladin",
    PRIEST      = "Priest",
    ROGUE       = "Rogue",
    SHAMAN      = "Shaman",
    WARLOCK     = "Warlock",
    WARRIOR     = "Warrior",
}

local function spellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(id) or 134400
    end
    return 134400
end

local function solidBG(frame, r, g, b, a, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a)
    return t
end

local function thinEdge(frame, edge, r, g, b, a, thickness)
    thickness = thickness or 1
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetColorTexture(r, g, b, a)
    if edge == "TOP" then
        t:SetHeight(thickness); t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT")
    elseif edge == "BOTTOM" then
        t:SetHeight(thickness); t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT")
    elseif edge == "LEFT" then
        t:SetWidth(thickness); t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT")
    elseif edge == "RIGHT" then
        t:SetWidth(thickness); t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT")
    end
    return t
end

local function frameBorder(frame, r, g, b, a)
    thinEdge(frame, "TOP",    r, g, b, a)
    thinEdge(frame, "BOTTOM", r, g, b, a)
    thinEdge(frame, "LEFT",   r, g, b, a)
    thinEdge(frame, "RIGHT",  r, g, b, a)
end

local function makeCheckbox(parent, label, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb.text:SetText(label)
    cb.text:SetTextColor(0.92, 0.92, 0.95)
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
    return cb
end

local function makeSlider(parent, label, lo, hi, step, getter, setter, fmt)
    fmt = fmt or "%d"
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(34)

    local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 0, 0)
    lbl:SetText(label)
    lbl:SetTextColor(0.92, 0.92, 0.95)

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetSize(220, 16)
    slider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 4, -4)
    slider:SetMinMaxValues(lo, hi)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    if slider.Low then slider.Low:SetText("") end
    if slider.High then slider.High:SetText("") end
    if slider.Text then slider.Text:SetText("") end

    local val = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    val:SetPoint("LEFT", slider, "RIGHT", 12, 0)

    local snap = (step >= 1) and function(v) return math.floor(v + 0.5) end or function(v) return v end

    slider:SetValue(getter())
    val:SetText(fmt:format(snap(getter())))

    slider:SetScript("OnValueChanged", function(self, v)
        v = snap(v)
        setter(v)
        val:SetText(fmt:format(v))
    end)

    return container
end

local function createSpellRow(parent, entry)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)

    local hover = row:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0)

    row:SetScript("OnEnter", function() hover:SetColorTexture(1, 1, 1, 0.04) end)
    row:SetScript("OnLeave", function() hover:SetColorTexture(0, 0, 0, 0) end)

    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("LEFT", 4, 0)
    cb:SetChecked(not (ns.db.blacklist and ns.db.blacklist[entry.id]))
    cb:SetScript("OnClick", function(self)
        ns.db.blacklist = ns.db.blacklist or {}
        if self:GetChecked() then
            ns.db.blacklist[entry.id] = nil
        else
            ns.db.blacklist[entry.id] = true
        end
    end)
    row.cb = cb

    local classColor = RAID_CLASS_COLORS[entry.class] or { r = 1, g = 1, b = 1 }

    local borderTex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    borderTex:SetSize(24, 24)
    borderTex:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    borderTex:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER", borderTex, "CENTER", 0, 0)
    icon:SetTexture(spellIcon(entry.id))
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", borderTex, "RIGHT", 10, 0)
    name:SetText(entry.name)
    name:SetTextColor(0.95, 0.95, 0.98)

    local classLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    classLabel:SetPoint("LEFT", name, "RIGHT", 12, 0)
    classLabel:SetText(CLASS_LABELS[entry.class] or entry.class)
    classLabel:SetTextColor(classColor.r * 0.85, classColor.g * 0.85, classColor.b * 0.85)

    local stats = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    stats:SetPoint("RIGHT", -8, 0)
    if (entry.duration or 0) > 0 then
        stats:SetText(("%ds · %ds cd"):format(entry.duration, entry.cooldown))
    else
        stats:SetText(("knockback · %ds cd"):format(entry.cooldown))
    end

    return row
end

local function createCategoryHeader(parent, label)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(24)

    local text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 6, 0)
    text:SetText(label:upper())
    text:SetTextColor(0.6, 0.5, 0.85)

    local line = h:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", text, "RIGHT", 10, -1)
    line:SetPoint("RIGHT", -8, -1)
    line:SetColorTexture(0.3, 0.25, 0.4, 0.45)

    return h
end

function Panel:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "AutoCCConfigFrame", UIParent)
    f:SetSize(UI_W, UI_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()

    solidBG(f, 0.06, 0.06, 0.08, 0.96)
    frameBorder(f, 0.22, 0.22, 0.28, 1)

    -- Header (also acts as the drag handle for the whole window)
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(48)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
    solidBG(header, 0.55, 0.4, 0.95, 0.07)
    thinEdge(header, "BOTTOM", 0.6, 0.45, 0.95, 0.6, 2)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", PAD, 1)
    title:SetText("autocc")
    title:SetTextColor(1, 1, 1)

    local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("LEFT", title, "RIGHT", 8, -1)
    subtitle:SetText("· Mythic+ CC Rotation")
    subtitle:SetTextColor(0.6, 0.6, 0.7)

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetSize(28, 28)
    close:SetPoint("RIGHT", -4, 0)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Display section
    local displayLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    displayLabel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", PAD, -PAD)
    displayLabel:SetText("DISPLAY")
    displayLabel:SetTextColor(0.6, 0.5, 0.85)

    local enableCB = makeCheckbox(f, "Show CC queue",
        function() return ns.db.enabled end,
        function(v) ns.db.enabled = v end)
    enableCB:SetPoint("TOPLEFT", displayLabel, "BOTTOMLEFT", -4, -6)

    local oocCB = makeCheckbox(f, "Show out of combat",
        function() return ns.db.showOutOfCombat end,
        function(v) ns.db.showOutOfCombat = v end)
    oocCB:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 0, -2)

    local queueSlider = makeSlider(f, "Queue length", 1, 6, 1,
        function() return ns.db.queueLength end,
        function(v) ns.db.queueLength = v end,
        "%d")
    queueSlider:SetPoint("TOPLEFT", oocCB, "BOTTOMLEFT", 4, -8)
    queueSlider:SetWidth(UI_W - 2 * PAD)

    local scaleSlider = makeSlider(f, "Scale", 0.5, 2.0, 0.05,
        function() return ns.db.scale end,
        function(v)
            ns.db.scale = v
            if ns.UI and ns.UI.anchor then ns.UI.anchor:SetScale(v) end
        end,
        "%.2fx")
    scaleSlider:SetPoint("TOPLEFT", queueSlider, "BOTTOMLEFT", 0, -10)
    scaleSlider:SetWidth(UI_W - 2 * PAD)

    -- Layout direction
    local layoutLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    layoutLabel:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", -4, -10)
    layoutLabel:SetText("Layout")
    layoutLabel:SetTextColor(0.92, 0.92, 0.95)

    local horizBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    horizBtn:SetSize(110, 22)
    horizBtn:SetPoint("TOPLEFT", layoutLabel, "BOTTOMLEFT", 4, -4)
    horizBtn:SetText("Horizontal")

    local vertBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    vertBtn:SetSize(110, 22)
    vertBtn:SetPoint("LEFT", horizBtn, "RIGHT", 8, 0)
    vertBtn:SetText("Vertical")

    local function refreshLayoutBtns()
        if ns.db.layout == "vertical" then
            vertBtn:LockHighlight(); horizBtn:UnlockHighlight()
        else
            horizBtn:LockHighlight(); vertBtn:UnlockHighlight()
        end
    end
    horizBtn:SetScript("OnClick", function()
        ns.db.layout = "horizontal"
        refreshLayoutBtns()
        ns:Fire("LAYOUT_CHANGED")
    end)
    vertBtn:SetScript("OnClick", function()
        ns.db.layout = "vertical"
        refreshLayoutBtns()
        ns:Fire("LAYOUT_CHANGED")
    end)
    refreshLayoutBtns()

    -- Spell list section
    local spellsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spellsLabel:SetPoint("TOPLEFT", horizBtn, "BOTTOMLEFT", -4, -18)
    spellsLabel:SetText("TRACKED SPELLS")
    spellsLabel:SetTextColor(0.6, 0.5, 0.85)

    local spellsHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spellsHint:SetPoint("LEFT", spellsLabel, "RIGHT", 8, 0)
    spellsHint:SetText("uncheck to hide from the queue")
    spellsHint:SetTextColor(0.5, 0.5, 0.55)

    -- ScrollFrame
    local scrollContainer = CreateFrame("Frame", nil, f)
    scrollContainer:SetPoint("TOPLEFT", spellsLabel, "BOTTOMLEFT", 4, -8)
    scrollContainer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 56)
    solidBG(scrollContainer, 0, 0, 0, 0.35)
    frameBorder(scrollContainer, 0.18, 0.18, 0.22, 1)

    local scroll = CreateFrame("ScrollFrame", "AutoCCConfigScroll", scrollContainer, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    f.scroll = scroll
    f.content = content

    -- Footer
    local footer = CreateFrame("Frame", nil, f)
    footer:SetHeight(46)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    thinEdge(footer, "TOP", 0.18, 0.18, 0.22, 1)

    local resetPos = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    resetPos:SetSize(130, 22)
    resetPos:SetPoint("LEFT", PAD, 0)
    resetPos:SetText("Reset position")
    resetPos:SetScript("OnClick", function()
        ns.db.position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -150 }
        ns:Fire("POSITION_RESET")
    end)

    local lockToggle = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    lockToggle:SetSize(120, 22)
    lockToggle:SetPoint("LEFT", resetPos, "RIGHT", 8, 0)
    local function refreshLockLabel()
        lockToggle:SetText(ns.db.locked and "Unlock anchor" or "Lock anchor")
    end
    refreshLockLabel()
    lockToggle:SetScript("OnClick", function()
        ns.db.locked = not ns.db.locked
        ns:Fire("LOCK_CHANGED", ns.db.locked)
        refreshLockLabel()
    end)

    local enableAll = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    enableAll:SetSize(100, 22)
    enableAll:SetPoint("RIGHT", -PAD, 0)
    enableAll:SetText("Enable all")
    enableAll:SetScript("OnClick", function()
        ns.db.blacklist = {}
        Panel:RefreshSpells()
    end)

    self.frame = f
    return f
end

function Panel:RefreshSpells()
    local f = self.frame
    if not f then return end

    -- Tear down existing rows
    if f.rowFrames then
        for _, r in ipairs(f.rowFrames) do r:Hide(); r:SetParent(nil) end
    end
    f.rowFrames = {}

    -- Group spells by category
    local byCat = {}
    for _, entry in ipairs(ns.Database.spells) do
        byCat[entry.cat] = byCat[entry.cat] or {}
        table.insert(byCat[entry.cat], entry)
    end

    local content = f.content
    local contentWidth = f.scroll:GetWidth() - 8
    content:SetWidth(contentWidth)

    local y = -4
    for _, cat in ipairs(CAT_ORDER) do
        local spells = byCat[cat]
        if spells and #spells > 0 then
            local h = createCategoryHeader(content, CAT_LABELS[cat])
            h:SetPoint("TOPLEFT", 0, y)
            h:SetWidth(contentWidth)
            f.rowFrames[#f.rowFrames + 1] = h
            y = y - 24

            table.sort(spells, function(a, b) return a.name < b.name end)
            for _, entry in ipairs(spells) do
                local row = createSpellRow(content, entry)
                row:SetPoint("TOPLEFT", 0, y)
                row:SetWidth(contentWidth)
                f.rowFrames[#f.rowFrames + 1] = row
                y = y - ROW_H
            end
            y = y - 10
        end
    end

    content:SetHeight(math.max(1, -y + 8))
end

function Panel:Show()
    local f = self:Build()
    self:RefreshSpells()
    f:Show()
end

function Panel:Hide()
    if self.frame then self.frame:Hide() end
end

function Panel:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Optional keybinding: nothing to do at DB_READY; the panel is built lazily on first open.
ns:On("DB_READY", function() end)
