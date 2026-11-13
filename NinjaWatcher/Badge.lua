-- NinjaWatcher - 掷骰统计参考
-- Badge.lua (0.2.8): a small need-rate tag next to unit health bars.
--
-- Design constraints, all deliberate:
--   * READ ONLY. It never queues a scan, never calls an achievement API and
--     never sends a chat message. It paints whatever is already in the local
--     catalog. No record -> no number (optionally a grey 未记录 tag).
--   * NO TAINT. Every tag is a frame this addon creates itself, parented to
--     UIParent. Nothing is parented to a Blizzard frame, no unit-frame script
--     is hooked or replaced, no protected attribute is touched. Left-clicking
--     a portrait still selects the unit exactly as before.
--   * Placement: look up the well-known unit-frame globals, read their screen
--     position behind pcall, then anchor our own tag beside the health bar.
--     If the client names its frames differently the tags fall back to a neat
--     column on the right edge of the screen rather than floating randomly.
--   * Every unit token, GUID and geometry read is guarded against secret
--     values. A protected value simply hides that tag for one refresh.
--
-- Modes (account-wide SavedVariables):
--   auto (default) - ON inside instances and outdoors, OFF in cities where
--                    hundreds of nameplates would make the tags unreadable
--   on             - always
--   off            - never

local ADDON, NW = ...

local Badge = {}
NW.Badge = Badge

local DB, Stats, Rate = NW.DB, NW.Stats, NW.Rate

local INTERVAL = 0.35
local accumulated = 0
local driver = nil
local labels = {}

-- target / focus plus the four party health bars. The raid frames are only
-- used as ALTERNATIVE ANCHORS for party members, so we never try to paint 40
-- tags in a raid.
local UNITS = {
    { unit = "target", anchors = { "TargetFrame" } },
    { unit = "focus",  anchors = { "FocusFrame" } },
    { unit = "party1", anchors = { "PartyMemberFrame1", "CompactPartyFrameMember1", "CompactRaidFrame1" } },
    { unit = "party2", anchors = { "PartyMemberFrame2", "CompactPartyFrameMember2", "CompactRaidFrame2" } },
    { unit = "party3", anchors = { "PartyMemberFrame3", "CompactPartyFrameMember3", "CompactRaidFrame3" } },
    { unit = "party4", anchors = { "PartyMemberFrame4", "CompactPartyFrameMember4", "CompactRaidFrame4" } },
}

-- Both languages: the client's zone text may be localised differently from
-- the addon's own strings.
local CITY_WORDS = {
    "暴风城", "铁炉堡", "达纳苏斯", "埃索达", "奥格瑞玛", "雷霆崖",
    "幽暗城", "银月城", "沙塔斯", "达拉然", "锦绣谷", "七星殿", "双月殿",
    "Stormwind", "Ironforge", "Darnassus", "Exodar", "Orgrimmar",
    "Thunder Bluff", "Undercity", "Silvermoon", "Shattrath", "Dalaran",
}

local EVENTS = {
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
    "ZONE_CHANGED_INDOORS", "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
}

local MODE_ALIASES = {
    ["自动"] = "auto", ["野外"] = "auto", ["智能"] = "auto",
    ["开"] = "on", ["开启"] = "on", ["总是"] = "on", ["打开"] = "on",
    ["关"] = "off", ["关闭"] = "off", ["隐藏"] = "off",
}

function Badge.Mode()
    local ok, value = pcall(DB.Get, "badgeMode")
    if ok and not NW.IsSecret(value)
        and (value == "auto" or value == "on" or value == "off") then
        return value
    end
    return "auto"
end

function Badge.ModeLabel()
    return NW.L("BADGE_MODE_" .. string.upper(Badge.Mode()))
end

function Badge.SetMode(value)
    local key = value
    if NW.IsSecret(key) or type(key) ~= "string" then return false end
    key = key:lower():match("^%s*(.-)%s*$")
    key = MODE_ALIASES[key] or key
    if key ~= "auto" and key ~= "on" and key ~= "off" then
        NW.Print(NW.L("BADGE_BAD"), NW.COLORS.yellow)
        return false
    end
    DB.Set("badgeMode", key)
    NW.Print(NW.L("BADGE_SET", Badge.ModeLabel()), NW.COLORS.green)
    pcall(Badge.Refresh)
    return true
end

function Badge.NextMode()
    local order = { "auto", "on", "off" }
    local current = Badge.Mode()
    local nextKey = order[1]
    for i, key in ipairs(order) do
        if key == current then nextKey = order[(i % #order) + 1] end
    end
    DB.Set("badgeMode", nextKey)
    pcall(Badge.Refresh)
    NW.Print(NW.L("BADGE_SET", NW.L("BADGE_MODE_" .. string.upper(nextKey))))
    return nextKey
end

local function inInstance()
    local ok, inside = Stats.SafeCall(IsInInstance)
    return ok and inside == true
end

-- IsResting() is the most reliable "you are in a sanctuary" signal across
-- client generations. The zone-name list is a fallback for clients that do
-- not expose it. Both reads are filtered for secret values.
local function inCity()
    local okRest, resting = Stats.SafeCall(IsResting)
    if okRest and resting == true then return true end
    local okZone, zone = Stats.SafeCall(GetZoneText)
    if not okZone or type(zone) ~= "string" then return false end
    local okFind, found = pcall(function()
        for _, word in ipairs(CITY_WORDS) do
            if zone:find(word, 1, true) then return true end
        end
        return false
    end)
    return okFind and found == true
end

function Badge.ShouldShow()
    local mode = Badge.Mode()
    if mode == "off" then return false end
    if mode == "on" then return true end
    if inInstance() then return true end
    if inCity() then return false end
    return true
end

-- Return left, bottom, width (screen coordinates) and whether we had to fall
-- back. Geometry reads are wrapped: a frame may be forbidden or its numbers
-- protected, and a mock/absent frame must never produce an error.
local function anchorOf(def)
    for _, name in ipairs(def.anchors) do
        local candidate = _G[name]
        if type(candidate) == "table" and type(candidate.GetLeft) == "function" then
            local ok, left, bottom, width = pcall(function()
                return candidate:GetLeft(), candidate:GetBottom(), candidate:GetWidth()
            end)
            if ok and type(left) == "number" and type(bottom) == "number"
                and not NW.IsSecret(left) and not NW.IsSecret(bottom)
                and not NW.IsSecret(width) then
                return left, bottom, type(width) == "number" and width or 0, false
            end
        end
    end
    return nil, nil, nil, true
end

local function guidFor(unit)
    if NW.IsSecret(unit) or type(unit) ~= "string" then return nil end
    if Stats.PlayerGate(unit) ~= "player" then return nil end
    local ok, identity = pcall(Stats.UnitIdentity, unit)
    if not ok or type(identity) ~= "table" then return nil end
    local guid = identity.guid
    if NW.IsSecret(guid) or type(guid) ~= "string" then return nil end
    return guid
end

-- Always show readable N/R, including small counts, with an age indicator.
local function verdictOf(row)
    local result = Rate.Evaluate(row)
    local suffix = DB.IsFresh(row) and "" or " · " .. NW.L("DATA_STALE_SHORT")
    return Rate.Summary(result) .. suffix, Rate.VerdictColor(result)
end

local function makeLabel(index)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(240, 18)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    if type(bg.SetColorTexture) == "function" then
        pcall(bg.SetColorTexture, bg, 0.04, 0.04, 0.03, 0.72)
    end

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetAllPoints(frame)
    text:SetJustifyH("LEFT")
    return { frame = frame, text = text, index = index }
end

local function hide(label)
    if label and label.frame then pcall(label.frame.Hide, label.frame) end
end

local function paint(label, def, text, color, fallbackName)
    local left, bottom, width, fallback = anchorOf(def)
    local frame = label.frame
    pcall(function()
        frame:ClearAllPoints()
        if fallback then
            -- No standard unit frame found: a tidy right-edge column. Prefix
            -- the player's name so the column is unambiguous.
            frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -18,
                -150 - (label.index - 1) * 22)
            if fallbackName then
                text = fallbackName .. " · " .. text
            end
        else
            frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
                left + width + 4, bottom + 6)
        end
        label.text:SetText(text)
        label.text:SetTextColor(color[1], color[2], color[3])
        frame:Show()
    end)
end

local function shortName(row)
    local name = row and row.name
    if NW.IsSecret(name) or type(name) ~= "string" then return nil end
    return name:sub(1, 12)
end

function Badge.Refresh()
    if not labels[1] then return false end
    if not Badge.ShouldShow() then
        for i = 1, #labels do hide(labels[i]) end
        return false
    end
    local showUnknown = DB.Get("badgeShowUnknown") == true
    for i, def in ipairs(UNITS) do
        local label = labels[i]
        local guid = guidFor(def.unit)
        local row = guid and DB.GetPlayer(guid) or nil
        if row then
            local text, color = verdictOf(row)
            paint(label, def, text, color, shortName(row))
        elseif guid and showUnknown then
            paint(label, def, NW.L("BADGE_NO_ROW"), NW.COLORS.gray, nil)
        else
            hide(label)
        end
    end
    return true
end

-- Current label texts, for diagnostics and the Lua-VM behaviour test.
function Badge.Texts()
    local out = {}
    for i, label in ipairs(labels) do
        local value = ""
        if label.text and type(label.text.GetText) == "function" then
            local ok, text = pcall(label.text.GetText, label.text)
            if ok and type(text) == "string" then value = text end
        end
        out[i] = value
    end
    return out
end

-- Number of tags currently visible. Used by the self-test / diagnostics.
function Badge.VisibleCount()
    local count = 0
    for _, label in ipairs(labels) do
        if label.frame and type(label.frame.IsShown) == "function" then
            local ok, shown = pcall(label.frame.IsShown, label.frame)
            if ok and shown == true then count = count + 1 end
        end
    end
    return count
end

function Badge.Init()
    if driver then return true end
    local ok = pcall(function()
        for i = 1, #UNITS do labels[i] = makeLabel(i) end
        driver = CreateFrame("Frame")
        for _, event in ipairs(EVENTS) do driver:RegisterEvent(event) end
        driver:SetScript("OnEvent", function() pcall(Badge.Refresh) end)
        driver:SetScript("OnUpdate", function(_, elapsed)
            accumulated = accumulated + (type(elapsed) == "number" and elapsed or 0)
            if accumulated < INTERVAL then return end
            accumulated = 0
            pcall(Badge.Refresh)
        end)
    end)
    if not ok then driver = nil return false end
    pcall(Badge.Refresh)
    return true
end
