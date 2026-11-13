-- NinjaWatcher - 掷骰统计参考
-- ChatTag.lua (0.2.9): put the locally recorded Need rate IN FRONT of the
-- sender's name in chat, e.g. (85%)某某某 whispers: ...
--
-- WHY AddMessage IS WRAPPED
--   ChatFrame_AddMessageEventFilter can rewrite arg2 (the sender), but the
--   chat system builds the clickable |Hplayer:<name>:...|h link FROM arg2.
--   Changing it would make "click the name to reply" whisper "(85%)某某某",
--   which does not exist. There is no official filter hook for the DISPLAY
--   text alone. The long-standing community solution (Prat, nicknames,
--   realm-name strippers) is to wrap each chat frame's own AddMessage and
--   edit only the [shown name] part of an existing player link, leaving the
--   link data byte-for-byte untouched. AddMessage is a plain FrameXML Lua
--   method, not a protected API; the original function is saved and always
--   called, so other chat addons in the chain keep working.
--
-- WHAT THIS DOES NOT DO
--   * No scan on its own (unless /nw tag refresh is enabled), no chat send,
--     no network, no unit frame hook, no SetItemRef hook.
--   * No local row -> no tag by default. Small counts show their share;
--     unknown values never become zero. Stale snapshots carry an explicit tag.
--   * A distant whisperer has NO unit token, so the comparison API cannot be
--     queried for them. Only players already in the local catalog get a
--     number, which is exactly why this feature is useful: it recognises
--     people you scanned earlier regardless of where they are now.
--   * Every string operation is behind NW.IsSecret + pcall. Comparing or
--     concatenating a protected string raises on this client (the original
--     Tooltip.lua:37 bug); on any doubt the message is passed through intact.

local ADDON, NW = ...

local ChatTag = {}
NW.ChatTag = ChatTag

local DB, Rate, Scan = NW.DB, NW.Rate, NW.Scan

local originals = {}        -- [chatFrame] = its original AddMessage
local guidByName = {}       -- normalised name -> { guid, at }
local activeName = nil      -- sender of the incoming whisper being drawn
local activeUntil = 0
local driver = nil
local elapsed = 0

local WINDOW = 2.0          -- seconds a whisper stays "the current message"
local GUID_TTL = 300
local RESCAN = 2.0          -- pick up chat windows created after login

local MODE_ALIASES = {
    ["私聊"] = "whisper", ["密语"] = "whisper", ["仅私聊"] = "whisper",
    ["whisper"] = "whisper", ["w"] = "whisper",
    ["全部"] = "all", ["所有"] = "all", ["全部频道"] = "all", ["all"] = "all",
    ["关"] = "off", ["关闭"] = "off", ["off"] = "off", ["0"] = "off",
}

local MODE_LABEL = {
    whisper = "TAG_MODE_WHISPER",
    all = "TAG_MODE_ALL",
    off = "TAG_MODE_OFF",
}

function ChatTag.Mode()
    local ok, value = pcall(DB.Get, "chatTagMode")
    if ok and not NW.IsSecret(value)
        and (value == "whisper" or value == "all" or value == "off") then
        return value
    end
    return "whisper"
end

function ChatTag.ModeLabel()
    return NW.L(MODE_LABEL[ChatTag.Mode()] or "TAG_MODE_WHISPER")
end

function ChatTag.SetMode(value)
    if NW.IsSecret(value) or type(value) ~= "string" then return false end
    local ok, key = pcall(function()
        return value:lower():match("^%s*(.-)%s*$")
    end)
    if not ok then return false end
    key = MODE_ALIASES[key] or key
    if key ~= "whisper" and key ~= "all" and key ~= "off" then
        NW.Print(NW.L("TAG_BAD"), NW.COLORS.yellow)
        return false
    end
    DB.Set("chatTagMode", key)
    NW.Print(NW.L("TAG_SET", ChatTag.ModeLabel()), NW.COLORS.green)
    if NW.Settings and type(NW.Settings.RefreshLinkUI) == "function" then
        pcall(NW.Settings.RefreshLinkUI)
    end
    return true
end

function ChatTag.NextMode()
    local order = { "whisper", "all", "off" }
    local current = ChatTag.Mode()
    local nextKey = order[1]
    for i, key in ipairs(order) do
        if key == current then nextKey = order[(i % #order) + 1] end
    end
    DB.Set("chatTagMode", nextKey)
    NW.Print(NW.L("TAG_SET", NW.L(MODE_LABEL[nextKey])))
    return nextKey
end

function ChatTag.ShowUnknown()
    local ok, value = pcall(DB.Get, "chatTagUnknown")
    return ok and value == true
end

-- Preserve realm-qualified names. Ambiguous bare-name lookups fail closed.
local function normalise(name)
    if type(name) ~= "string" or NW.IsSecret(name) then return nil end
    local ok, value = pcall(function()
        return (name:gsub("%s+", "")):lower()
    end)
    return ok and value ~= "" and value or nil
end

-- GUID beats a name lookup: two players can share a display name across
-- realms. The GUID comes from the whisper event (arg12), never from the
-- message text, and is only kept in memory for a few minutes.
local function rowFor(name, linkName)
    local key = normalise(linkName) or normalise(name)
    if not key then return nil end
    local cached = guidByName[key]
    if cached and (GetTime() - cached.at) < GUID_TTL then
        local row = DB.GetPlayer(cached.guid)
        -- A known GUID must never fall through to a different same-name player.
        return row
    end
    local row = DB.FindByName(linkName or name)
    return row
end

-- Small counts remain visible; unknown counts never become zero.
local function tagFor(row)
    local result = Rate.Evaluate(row)
    if result.status ~= "ok" then return NW.L("TAG_GRAY"), NW.COLORS.gray end
    local pct = math.floor(result.ratio * 100 + 0.5)
    local suffix = result.sampleLevel == "small" and "·少" or ""
    if not DB.IsFresh(row) then suffix = suffix .. "·旧" end
    return string.format("(%d%%%s)", pct, suffix), Rate.Color(result.band)
end

local function colour(text, rgb)
    local function byte(value)
        return math.max(0, math.min(255, math.floor((value or 1) * 255 + 0.5)))
    end
    return string.format("|cff%02x%02x%02x%s|r",
        byte(rgb[1]), byte(rgb[2]), byte(rgb[3]), text)
end

-- Returns a rewritten message, or nil to pass the original through untouched.
-- The link payload "data" is copied verbatim; only [shown] is prefixed.
local function decorate(message)
    if type(message) ~= "string" or NW.IsSecret(message) then return nil end
    local mode = ChatTag.Mode()
    if mode == "off" then return nil end

    local ok, out = pcall(function()
        local startAt, endAt, data, shown =
            message:find("|Hplayer:([^|]*)|h%[(.-)%]|h")
        if not startAt or NW.IsSecret(data) or NW.IsSecret(shown) then
            return nil
        end
        if #data > 200 or #shown > 80 then return nil end
        local linkName = data:match("^([^:]+)") or data

        if mode == "whisper" then
            if not activeName or GetTime() > activeUntil then return nil end
            if normalise(linkName) ~= normalise(activeName) then return nil end
        end

        local row = rowFor(shown, linkName)
        local tag, rgb
        if row then
            tag, rgb = tagFor(row)
        elseif ChatTag.ShowUnknown() then
            tag, rgb = NW.L("TAG_UNKNOWN"), NW.COLORS.gray
        else
            return nil
        end

        local link = "|Hplayer:" .. data .. "|h["
            .. colour(tag, rgb) .. shown .. "]|h"
        return message:sub(1, startAt - 1) .. link .. message:sub(endAt + 1)
    end)
    if not ok then return nil end
    return out
end

-- Exposed for diagnostics and the behaviour test; the event handler below
-- calls exactly this function, so there is one code path.
function ChatTag.NoteWhisper(sender, guid)
    pcall(function()
        if type(sender) == "string" and not NW.IsSecret(sender) then
            activeName = sender
            activeUntil = GetTime() + WINDOW
        end
        if type(guid) ~= "string" or NW.IsSecret(guid) or guid == ""
            or type(sender) ~= "string" or NW.IsSecret(sender) then
            return
        end
        local key = normalise(sender)
        if key then guidByName[key] = { guid = guid, at = GetTime() } end

        -- Optional and OFF by default. Distant whisperers simply have no unit
        -- token, in which case UnitTokenFromGUID returns nil and nothing at
        -- all is queued. Only a never-before-recorded, nearby player is
        -- eligible, so an ordinary whisper never triggers a scan.
        if DB.Get("chatTagRefresh") == true and not DB.GetPlayer(guid)
            and type(UnitTokenFromGUID) == "function" then
            local tokenOk, unit = pcall(UnitTokenFromGUID, guid)
            if tokenOk and type(unit) == "string" and not NW.IsSecret(unit) then
                pcall(Scan.Request, unit, { manual = true, priority = true })
            end
        end
    end)
    ChatTag.EnsureFrames()
end

local function wrapFrame(f)
    if type(f) ~= "table" or originals[f] then return false end
    local orig = f.AddMessage
    if type(orig) ~= "function" then return false end
    local ok = pcall(function()
        originals[f] = orig
        f.AddMessage = function(self, message, ...)
            local safe, changed = pcall(decorate, message)
            return orig(self, (safe and changed) or message, ...)
        end
    end)
    if not ok then originals[f] = nil end
    return ok
end

-- Covers every standard chat frame plus windows opened later (whisper
-- conversations). No global function is replaced: we only shadow the
-- AddMessage method of frames this addon can see.
function ChatTag.EnsureFrames()
    local count = type(NUM_CHAT_FRAMES) == "number" and NUM_CHAT_FRAMES or 10
    for i = 1, count do
        pcall(wrapFrame, _G["ChatFrame" .. i])
    end
    if type(DEFAULT_CHAT_FRAME) == "table" then
        pcall(wrapFrame, DEFAULT_CHAT_FRAME)
    end
    return true
end

function ChatTag.WrappedCount()
    local count = 0
    for _ in pairs(originals) do count = count + 1 end
    return count
end

function ChatTag.Init()
    if driver then return true end
    local ok = pcall(function()
        driver = CreateFrame("Frame")
        driver:RegisterEvent("CHAT_MSG_WHISPER")
        driver:SetScript("OnEvent", function(_, event, ...)
            if event ~= "CHAT_MSG_WHISPER" then return end
            -- CHAT_MSG_WHISPER: arg1 = text, arg2 = sender, arg12 = GUID.
            local sender, guid = select(2, ...), select(12, ...)
            ChatTag.NoteWhisper(sender, guid)
        end)
        driver:SetScript("OnUpdate", function(_, delta)
            elapsed = elapsed + (type(delta) == "number" and delta or 0)
            if elapsed < RESCAN then return end
            elapsed = 0
            ChatTag.EnsureFrames()
        end)
    end)
    if not ok then driver = nil return false end
    ChatTag.EnsureFrames()
    return true
end
