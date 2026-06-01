local ADDON, ns = ...

-- ns is the addon-private namespace shared across files (Database, PartyTracker, ...).
ns.ADDON = ADDON
ns.modules = {}
ns.callbacks = CreateFrame("Frame")
ns.callbacks.listeners = {}

function ns:Register(name, mod)
    self.modules[name] = mod
    return mod
end

function ns:Get(name)
    return self.modules[name]
end

-- Tiny pub/sub so modules can talk without hard-coupling.
function ns:On(event, fn)
    local list = self.callbacks.listeners[event]
    if not list then
        list = {}
        self.callbacks.listeners[event] = list
    end
    list[#list + 1] = fn
end

function ns:Fire(event, ...)
    local list = self.callbacks.listeners[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

function ns:Print(...)
    print("|cff7fd5ff[autocc]|r", ...)
end

local AutoCC = CreateFrame("Frame", "AutoCCFrame")
ns.frame = AutoCC

local AUTOCC_DEFAULTS = {
    enabled = true,
    queueLength = 3,
    scale = 1.0,
    locked = true,
    position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -150 },
    showOutOfCombat = true,
    layout = "horizontal",        -- "horizontal" | "vertical"
    priorityOverrides = {},
    blacklist = {},               -- blacklist[spellID] = true -> hide from rotation
    debug = false,
}

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

AutoCC:RegisterEvent("ADDON_LOADED")
AutoCC:RegisterEvent("PLAYER_LOGIN")
AutoCC:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        AutoCCDB = CopyDefaults(AUTOCC_DEFAULTS, AutoCCDB or {})
        ns.db = AutoCCDB
        ns:Fire("DB_READY")
    elseif event == "PLAYER_LOGIN" then
        ns:Fire("LOGIN")
        ns:Print("loaded. /autocc for commands.")
    end
end)

SLASH_AUTOCC1 = "/autocc"
SlashCmdList["AUTOCC"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "lock" then
        ns.db.locked = true
        ns:Fire("LOCK_CHANGED", true)
        ns:Print("locked.")
    elseif msg == "unlock" then
        ns.db.locked = false
        ns:Fire("LOCK_CHANGED", false)
        ns:Print("unlocked — drag the anchor; /autocc lock when done.")
    elseif msg == "test" then
        ns:Fire("TEST")
    elseif msg == "reset" then
        ns.db.position = CopyDefaults(AUTOCC_DEFAULTS.position, {})
        ns:Fire("POSITION_RESET")
        ns:Print("position reset.")
    elseif msg == "config" or msg == "options" or msg == "" then
        if ns.ConfigUI and ns.ConfigUI.Toggle then
            ns.ConfigUI:Toggle()
        else
            ns:Print("config panel not ready yet.")
        end
    elseif msg == "debug" then
        ns.db.debug = not ns.db.debug
        ns:Print("debug:", ns.db.debug and "on" or "off")
    else
        ns:Print("commands: (no arg) | lock | unlock | test | reset | config | debug")
    end
end
