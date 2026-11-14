-- RollLedger - 掷骰统计参考
-- Stats.lua: read the three public counters and resolve unit identity.
--
-- Only N/G/E are read. Empty/dash values are unreported, never zero.
-- String separators are intentionally conservative until verified in-client.

local ADDON, RL = ...

local Stats = {}
RL.Stats = Stats

local DASH = "\226\128\148" -- em dash

-- A secret value must not be compared, concatenated, hashed or formatted.
local function isSecret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return not ok or (secret and true or false)
end
RL.IsSecret = isSecret

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Calls a game API. Returns ok, first, second, third. A secret return makes
-- the whole call unavailable; the addon treats that as unknown.
function Stats.SafeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, a, b, c = pcall(fn, ...)
    if not ok or isSecret(a) or isSecret(b) or isSecret(c) then
        return false
    end
    return true, a, b, c
end

-- Returns count, quality: readable, unreported, unknown, restricted, format.
function Stats.ParseCount(value)
    if isSecret(value) then return nil, "restricted" end
    if type(value) == "number" then
        if value ~= value or value < 0 or value == math.huge or value ~= math.floor(value) then
            return nil, "format"
        end
        return value, "readable"
    end
    if type(value) ~= "string" then
        return nil, "unknown"
    end
    local text = trim(value)
    if text == "" or text == "-" or text == "--" or text == DASH then
        return nil, "unreported"
    end
    -- Accept plain digits and strict comma thousands groups only. Dot and
    -- mixed/space formats are ambiguous (1.000 may mean 1 or 1000).
    if text:find(",", 1, true) then
        local first, rest = text:match("^(%d%d?%d?)(,.*)$")
        if not first then return nil, "format" end
        while #rest > 0 do
            local group, tail = rest:match("^,(%d%d%d)(.*)$")
            if not group then return nil, "format" end
            first, rest = first .. group, tail
        end
        text = first
    end
    if text:match("^%d+$") then
        local count = tonumber(text)
        if count and count >= 0 and count < math.huge and count == math.floor(count) then
            return count, "readable"
        end
    end
    return nil, "format"
end

-- Reads one statistic through a getter such as GetStatistic or
-- GetComparisonStatistic. The second return of those APIs is a skip flag.
function Stats.ReadOne(getter, id)
    if type(getter) ~= "function" then
        return nil, "api"
    end
    local ok, value, skip = pcall(getter, id)
    if not ok then return nil, "error" end
    if isSecret(value) or isSecret(skip) then return nil, "restricted" end
    if skip then return nil, "skipped" end
    return Stats.ParseCount(value)
end

local function readField(getter, id)
    local value, quality = Stats.ReadOne(getter, id)
    return value, quality
end

-- Reads each field independently, preserving unknown quality flags.
function Stats.ReadRow(getter)
    local row = {
        at = time(),
        quality = {},
        source = "scan",
    }
    row.need, row.quality.need = readField(getter, RL.STAT.need)
    row.greed, row.quality.greed = readField(getter, RL.STAT.greed)
    row.entries, row.quality.entries = readField(getter, RL.STAT.dungeons)
    return row
end

local function usableQuality(quality, value)
    return RL.Rate.IsCount(value) and (quality == nil or quality == "readable")
end

-- N/G suffice for a share. E is independently optional.
function Stats.RowUsable(row)
    if type(row) ~= "table" then return false end
    return usableQuality(row.quality and row.quality.need, row.need)
        and usableQuality(row.quality and row.quality.greed, row.greed)
end

function Stats.UnknownField(row)
    if type(row) ~= "table" then return "row" end
    if not usableQuality(row.quality and row.quality.need, row.need) then return "need" end
    if not usableQuality(row.quality and row.quality.greed, row.greed) then return "greed" end
    if not usableQuality(row.quality and row.quality.entries, row.entries) then return "entries" end
    return nil
end

-- The player's own row uses GetStatistic. Other players use the comparison
-- getter only after SetAchievementComparisonUnit has fired its ready event.
function Stats.SelfRow()
    local identity = Stats.UnitIdentity("player")
    if not identity or not identity.isSelf then return nil end
    local row = Stats.ReadRow(GetStatistic)
    row.name = identity.name
    row.realm = identity.realm
    row.level = identity.level
    row.class = identity.class
    row.classKey = identity.classKey
    row.source = "self"
    row.self = true
    return row
end

function Stats.ComparisonRow()
    return Stats.ReadRow(GetComparisonStatistic)
end

-- Cheap gate that runs BEFORE any statistic or identity read. NPC, pet and
-- object tooltips must not make the addon touch the achievement comparison
-- API (or even ask for a name/class). A protected ("secret") token or return
-- value is reported as "unknown" so callers stop instead of guessing.
-- Returns "player" | "npc" | "unknown".
function Stats.PlayerGate(unit)
    if isSecret(unit) or type(unit) ~= "string" or unit == "" then
        return "unknown"
    end
    local existsOk, exists = Stats.SafeCall(UnitExists, unit)
    if not existsOk or isSecret(exists) then return "unknown" end
    if not exists then return "unknown" end
    local playerOk, isPlayer = Stats.SafeCall(UnitIsPlayer, unit)
    if not playerOk or isSecret(isPlayer) or isPlayer == nil then
        return "unknown"
    end
    return isPlayer and "player" or "npc"
end

-- Resolves a unit token without assuming that a missing value is zero.
-- Returns identity, nil or nil, reason ("npc", "none" or "hidden").
function Stats.UnitIdentity(unit)
    -- Non-player units and unreadable tokens are rejected here, before the
    -- GUID / name / level / class reads below.
    local gate = Stats.PlayerGate(unit)
    if gate ~= "player" then
        return nil, gate == "npc" and "npc" or "hidden"
    end

    local guidOk, guid = Stats.SafeCall(UnitGUID, unit)
    if not guidOk or isSecret(guid) or type(guid) ~= "string" or guid == "" then
        return nil, "hidden"
    end

    local nameOk, name, realm = Stats.SafeCall(UnitName, unit)
    if not nameOk or type(name) ~= "string" or name == "" then
        return nil, "hidden"
    end
    if type(realm) ~= "string" or realm == "" then
        local realmOk, current = Stats.SafeCall(GetRealmName)
        realm = realmOk and type(current) == "string" and current or nil
    end

    local levelOk, level = Stats.SafeCall(UnitLevel, unit)
    if not levelOk or type(level) ~= "number" or level < 0 or level ~= math.floor(level) then
        level = nil
    end

    local selfOk, isSelf = Stats.SafeCall(UnitIsUnit, unit, "player")
    if not selfOk or isSelf == nil then return nil, "hidden" end

    local classOk, class, classKey = Stats.SafeCall(UnitClass, unit)
    if not classOk then class, classKey = nil, nil end

    return {
        guid = guid,
        name = name,
        realm = type(realm) == "string" and realm or nil,
        level = level,
        isPlayer = true,
        isSelf = isSelf and true or false,
        class = type(class) == "string" and class or nil,
        classKey = type(classKey) == "string" and classKey or nil,
    }
end
