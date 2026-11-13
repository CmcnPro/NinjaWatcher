-- NinjaWatcher - 掷骰统计参考
-- Broadcast.lua: one-click 小队 / 团队 announcements, no slash command needed.
--
-- Zero dependencies: no LibDBIcon, no Ace, no external texture files.
--   * A draggable minimap button (or a floating button if Minimap is missing)
--     opens a compact panel with one left click.
--   * Each row is a player with two labelled buttons: 小队 sends to PARTY,
--     团队 sends to RAID. One click sends; nothing is sent automatically.
--   * Hovering a row shows exactly what would be sent, using the same
--     GameTooltip that the fixed Tooltip.lua keeps working on this client.
--   * The portrait's native click behaviour is untouched. Only entries are
--     appended to the unit popup menu (see Settings.lua).
--
-- Every name / guild / verdict text passes through NW.IsSecret before it is
-- displayed, so a protected value can never reach the UI or a chat message.

local ADDON, NW = ...

local Broadcast = {}
NW.Broadcast = Broadcast

local DB, Stats, Share = NW.DB, NW.Stats, NW.Share

local ROW_HEIGHT = 28
local PANEL_WIDTH = 520
local PANEL_HEIGHT = 366

local frame, icon, scroll, scrollChild, emptyText, statusText, iconModeButton
local rows = {}
local entries = {}
local installed = false

local MODES = { minimap = true, float = true, hide = true }
local MODE_ORDER = { "minimap", "float", "hide" }
local MODE_ALIASES = {
    ["小地图"] = "minimap", ["地图"] = "minimap", ["显示"] = "minimap", ["m"] = "minimap",
    ["悬浮"] = "float", ["浮动"] = "float", ["f"] = "float",
    ["隐藏"] = "hide", ["关闭"] = "hide", ["h"] = "hide",
}

local function safeText(value, fallback)
    if NW.IsSecret(value) or type(value) ~= "string" or value == "" then
        return fallback
    end
    return value
end

local function normalizeMode(value)
    if NW.IsSecret(value) or type(value) ~= "string" then return nil end
    local key = value:lower():match("^%s*(.-)%s*$")
    if MODES[key] then return key end
    return MODE_ALIASES[value:match("^%s*(.-)%s*$")] or MODE_ALIASES[key]
end

local function identityOf(unit)
    if NW.IsSecret(unit) or type(unit) ~= "string" then return nil end
    -- Skip NPCs / pets / objects before reading a name, GUID or class.
    if Stats.PlayerGate(unit) ~= "player" then return nil end
    local ok, identity = pcall(Stats.UnitIdentity, unit)
    if not ok or type(identity) ~= "table" then return nil end
    if NW.IsSecret(identity.guid) or type(identity.guid) ~= "string" then return nil end
    return identity
end

-- Current hover / target first, then the whole party or raid. A player is
-- listed once even if he is both the target and a group member.
local function collect()
    local list, seen = {}, {}
    local function add(unit, tagKey)
        local identity = identityOf(unit)
        if not identity or not identity.guid then return end
        if NW.IsSecret(identity.guid) or seen[identity.guid] then return end
        seen[identity.guid] = true
        list[#list + 1] = {
            guid = identity.guid,
            unit = unit,
            name = safeText(identity.name, "?"),
            tag = NW.L(tagKey),
        }
    end
    add("mouseover", "BROADCAST_TAG_MOUSE")
    add("target", "BROADCAST_TAG_TARGET")
    local inRaid = type(IsInRaid) == "function" and IsInRaid() and true or false
    if inRaid and type(GetNumGroupMembers) == "function" then
        local count = tonumber(GetNumGroupMembers()) or 0
        for i = 1, math.min(count, 40) do
            add("raid" .. i, "BROADCAST_TAG_RAID")
        end
    else
        for i = 1, 4 do
            add("party" .. i, "BROADCAST_TAG_PARTY")
        end
    end
    add("player", "BROADCAST_TAG_SELF")
    return list
end

local function groupState()
    local inRaid = type(IsInRaid) == "function" and IsInRaid() and true or false
    local inGroup = false
    if type(IsInGroup) == "function" then
        inGroup = IsInGroup() and true or false
    elseif type(GetNumGroupMembers) == "function" then
        inGroup = (tonumber(GetNumGroupMembers()) or 0) > 0
    end
    if inRaid then return NW.L("BROADCAST_STATE_RAID") end
    if inGroup then return NW.L("BROADCAST_STATE_PARTY") end
    return NW.L("BROADCAST_STATE_SOLO")
end

-- ------------------------------------------------------------------ panel UI
local function showRowTooltip(row, entry)
    if not entry or GameTooltip == nil
        or type(GameTooltip.SetOwner) ~= "function" then
        return
    end
    local ok = pcall(function()
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(entry.name .. " · " .. entry.tag, 1, 1, 1)
        local message = Share.MessageFor(entry.guid)
        if message then
            GameTooltip:AddLine(NW.L("BROADCAST_PREVIEW", message), 0.85, 0.85, 0.85, true)
        else
            GameTooltip:AddLine(NW.L("BROADCAST_NO_ROW"), 0.85, 0.85, 0.85, true)
        end
        GameTooltip:AddLine(NW.L("BROADCAST_HINT"), 0.60, 0.60, 0.60, true)
        GameTooltip:Show()
    end)
    if not ok and type(GameTooltip.Hide) == "function" then
        pcall(GameTooltip.Hide, GameTooltip)
    end
end

local function paintTexture(texture, r, g, b, a)
    if not texture or type(texture.SetColorTexture) ~= "function" then return end
    pcall(texture.SetColorTexture, texture, r, g, b, a)
end

local function makeRow(index)
    local row = CreateFrame("Frame", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:EnableMouse(true)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    paintTexture(bg, 1, 1, 1, index % 2 == 0 and 0.05 or 0.02)

    -- A small colour chip stands in for a portrait and carries the band.
    local chip = row:CreateTexture(nil, "ARTWORK")
    chip:SetSize(10, 10)
    chip:SetPoint("LEFT", row, "LEFT", 6, 0)
    paintTexture(chip, 0.62, 0.62, 0.62, 1)

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("LEFT", row, "LEFT", 22, 0)
    name:SetWidth(104)
    name:SetJustifyH("LEFT")
    name:SetHeight(ROW_HEIGHT)

    local verdict = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verdict:SetPoint("LEFT", row, "LEFT", 128, 0)
    verdict:SetWidth(220)
    verdict:SetJustifyH("LEFT")
    verdict:SetHeight(ROW_HEIGHT)

    local partyButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    partyButton:SetSize(50, 20)
    partyButton:SetPoint("RIGHT", row, "RIGHT", -56, 0)
    partyButton:SetText(NW.L("BROADCAST_PARTY_BTN"))
    local raidButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    raidButton:SetSize(50, 20)
    raidButton:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    raidButton:SetText(NW.L("BROADCAST_RAID_BTN"))

    row.chip = chip
    row.name = name
    row.verdict = verdict
    row.partyButton = partyButton
    row.raidButton = raidButton

    row:SetScript("OnEnter", function(self)
        showRowTooltip(self, self.entry)
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip ~= nil and type(GameTooltip.Hide) == "function" then
            pcall(GameTooltip.Hide, GameTooltip)
        end
    end)
    partyButton:SetScript("OnClick", function()
        if row.entry and Share then
            Share.Broadcast(row.entry.guid, "party", row.entry.unit)
        end
    end)
    raidButton:SetScript("OnClick", function()
        if row.entry and Share then
            Share.Broadcast(row.entry.guid, "raid", row.entry.unit)
        end
    end)
    return row
end

local function getRow(index)
    if not rows[index] then rows[index] = makeRow(index) end
    return rows[index]
end

local function setRow(row, entry)
    row.entry = entry
    row.name:SetText(entry.name)
    local text, color = Share.Verdict(DB.GetPlayer(entry.guid), entry.guid)
    row.verdict:SetText(text)
    row.verdict:SetTextColor(color[1], color[2], color[3])
    paintTexture(row.chip, color[1], color[2], color[3], 1)
    row:Show()
end

local function refreshRows()
    entries = collect()
    for i, entry in ipairs(entries) do
        setRow(getRow(i), entry)
    end
    for i = #entries + 1, #rows do
        rows[i].entry = nil
        rows[i]:Hide()
    end
    scrollChild:SetHeight(math.max(1, #entries * ROW_HEIGHT))
    emptyText:SetShown(#entries == 0)
    statusText:SetText(NW.L("BROADCAST_STATUS", groupState(), DB.Count()))
end

local function updateIconModeButton()
    if not iconModeButton then return end
    local mode = normalizeMode(DB.Get("iconMode")) or "minimap"
    iconModeButton:SetText(NW.L("BROADCAST_ICON_MODE",
        NW.L("BROADCAST_ICON_" .. string.upper(mode))))
end

local function buildPanel()
    local ok, created = pcall(CreateFrame, "Frame", "NinjaWatcherBroadcastFrame",
        UIParent, "BackdropTemplate")
    if not ok or not created then
        created = CreateFrame("Frame", "NinjaWatcherBroadcastFrame", UIParent)
    end
    frame = created
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    paintTexture(bg, 0.06, 0.07, 0.09, 0.95)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
    title:SetText(NW.L("BROADCAST_TITLE"))
    title:SetTextColor(0.96, 0.55, 0.73)

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(54, 22)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    close:SetText(NW.L("BROADCAST_CLOSE"))
    close:SetScript("OnClick", function() frame:Hide() end)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -34)
    hint:SetWidth(PANEL_WIDTH - 20)
    hint:SetJustifyH("LEFT")
    hint:SetText(NW.L("BROADCAST_HINT"))
    hint:SetTextColor(0.72, 0.72, 0.72)

    scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -62)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 62)
    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(PANEL_WIDTH - 44)
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)

    emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("TOPLEFT", scroll, "TOPLEFT", 6, -8)
    emptyText:SetWidth(PANEL_WIDTH - 50)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText(NW.L("BROADCAST_EMPTY"))

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 36)
    statusText:SetWidth(PANEL_WIDTH - 20)
    statusText:SetJustifyH("LEFT")
    statusText:SetTextColor(0.65, 0.65, 0.65)

    iconModeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    iconModeButton:SetSize(170, 22)
    iconModeButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
    iconModeButton:SetScript("OnClick", function()
        local current = normalizeMode(DB.Get("iconMode")) or "minimap"
        local index = 1
        for i, mode in ipairs(MODE_ORDER) do
            if mode == current then index = i break end
        end
        Broadcast.SetIconMode(MODE_ORDER[(index % #MODE_ORDER) + 1])
    end)
    updateIconModeButton()

    return frame
end

-- -------------------------------------------------------------- quick button
local function atan2compat(y, x)
    local fn = math.atan2 or math.atan
    return fn(y, x)
end

local function placeMinimap(button)
    local angle = tonumber(DB.Get("iconAngle")) or 45
    local rad = math.rad(angle)
    local radius = 80
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(rad) * radius, math.sin(rad) * radius)
end

local function dragMinimap(button)
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    local mx, my = Minimap:GetCenter()
    local dx = cx / (scale or 1) - mx
    local dy = cy / (scale or 1) - my
    DB.Set("iconAngle", math.deg(atan2compat(dy, dx)))
    placeMinimap(button)
end

local function placeFloating(button)
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "CENTER", 180, 0)
end

local function applyIconMode(mode)
    if not icon then return end
    local wanted = MODES[mode] and mode or "minimap"
    if wanted == "minimap" and Minimap == nil then wanted = "float" end
    icon.mode = wanted
    if wanted == "hide" then
        icon:Hide()
        return
    end
    if wanted == "float" then
        icon:SetParent(UIParent)
        placeFloating(icon)
    else
        icon:SetParent(Minimap)
        placeMinimap(icon)
    end
    icon:Show()
end

local function buildIcon()
    local parent = Minimap or UIParent
    icon = CreateFrame("Button", "NinjaWatcherQuickButton", parent)
    icon:SetSize(32, 32)
    icon:SetFrameStrata("MEDIUM")
    icon:SetMovable(true)
    icon:EnableMouse(true)
    icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    icon:RegisterForDrag("LeftButton")

    local bg = icon:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(icon)
    paintTexture(bg, 0.10, 0.32, 0.48, 0.95)
    local ring = icon:CreateTexture(nil, "BORDER")
    ring:SetPoint("CENTER", icon, "CENTER", 0, 0)
    ring:SetSize(28, 28)
    paintTexture(ring, 0.96, 0.55, 0.73, 0.9)
    local label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", icon, "CENTER", 0, 0)
    label:SetText("NW")
    label:SetTextColor(0.06, 0.07, 0.09, 1)

    icon:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            Broadcast.SetIconMode("float")
        else
            Broadcast.Toggle()
        end
    end)
    icon:SetScript("OnEnter", function(self)
        if GameTooltip == nil
            or type(GameTooltip.SetOwner) ~= "function" then return end
        pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(NW.L("BROADCAST_ICON_TIP"), 1, 1, 1, true)
            GameTooltip:AddLine(NW.L("RATE_HINT"), 0.78, 0.70, 0.45, true)
            GameTooltip:Show()
        end)
    end)
    icon:SetScript("OnLeave", function()
        if GameTooltip ~= nil and type(GameTooltip.Hide) == "function" then
            pcall(GameTooltip.Hide, GameTooltip)
        end
    end)
    icon:SetScript("OnDragStart", function(self)
        self.dragging = true
        if self.mode == "float" then self:StartMoving() end
    end)
    icon:SetScript("OnDragStop", function(self)
        self.dragging = false
        if self.mode == "float" then self:StopMovingOrSizing() end
    end)
    icon:SetScript("OnUpdate", function(self)
        if self.dragging and self.mode == "minimap" then
            pcall(dragMinimap, self)
        end
    end)
    return icon
end

-- -------------------------------------------------------------------- public
function Broadcast.Init()
    if installed then return end
    installed = true
    buildPanel()
    buildIcon()
    applyIconMode(normalizeMode(DB.Get("iconMode")) or "minimap")
    NW.Scan.OnReady(function()
        if frame and frame:IsShown() then Broadcast.Refresh() end
    end)

    -- Keep an open panel current when the group changes.
    local ok, watcher = pcall(CreateFrame, "Frame")
    if ok and watcher then
        pcall(watcher.RegisterEvent, watcher, "GROUP_ROSTER_UPDATE")
        pcall(watcher.SetScript, watcher, "OnEvent", function()
            if frame and frame:IsShown() then Broadcast.Refresh() end
        end)
    end
end

function Broadcast.Refresh()
    if not frame then return end
    refreshRows()
    updateIconModeButton()
end

function Broadcast.Toggle()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        Broadcast.Refresh()
        frame:Show()
    end
end

function Broadcast.Show()
    if not frame then return end
    Broadcast.Refresh()
    frame:Show()
end

function Broadcast.SetIconMode(value)
    local mode = normalizeMode(value)
    if not mode then
        NW.Print(NW.L("BROADCAST_ICON_SET", NW.L("BROADCAST_ICON_MINIMAP")))
        return
    end
    DB.Set("iconMode", mode)
    applyIconMode(mode)
    if frame then updateIconModeButton() end
    NW.Print(NW.L("BROADCAST_ICON_SET",
        NW.L("BROADCAST_ICON_" .. string.upper(mode))))
end

function Broadcast.IconMode()
    return normalizeMode(DB.Get("iconMode")) or "minimap"
end
