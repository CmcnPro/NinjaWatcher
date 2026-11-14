-- RollLedger - 掷骰统计参考
-- Scan.lua: the only file that talks to the achievement comparison API.
--
-- Sequence for another player:
--   SetAchievementComparisonUnit(unit)
--   INSPECT_ACHIEVEMENT_READY (guid)
--   GetComparisonStatistic(1044 / 1043 / 932)
--   ClearAchievementComparisonUnit()
--
-- One request is in flight at a time. Hover requests are debounced; a party
-- scan is a small queue. The addon never calls NotifyInspect or
-- InspectAchievements and never registers a restricted event.

local ADDON, RL = ...

local Scan = {}
RL.Scan = Scan

local Stats, DB = RL.Stats, RL.DB

local state = "IDLE"
local pending = nil
local inflight = nil
local queue = {}
local lastSet = nil
local farUntil = {}
local listeners = {}
local ownsComparison = false
local inCall = false
local externalUntil = 0
local hooks = {}

local frame = CreateFrame("Frame")
Scan.frame = frame
Scan.last = nil
Scan.timeouts = 0

local function now()
    return GetTime()
end

local function secret(value)
    return RL.IsSecret(value)
end

function Scan.State()
    return state
end

function Scan.QueueSize()
    return #queue
end

function Scan.HasAPI()
    return type(SetAchievementComparisonUnit) == "function"
        and type(ClearAchievementComparisonUnit) == "function"
        and type(GetComparisonStatistic) == "function"
end

-- fn(guid, row|nil, status)
function Scan.OnReady(fn)
    if type(fn) == "function" then
        listeners[#listeners + 1] = fn
    end
end

local function notify(guid, row, status)
    for _, fn in ipairs(listeners) do
        pcall(fn, guid, row, status)
    end
end

local function cacheFresh(row)
    return DB.IsFresh(row)
end

function Scan.Peek(guid)
    return guid and DB.GetPlayer(guid) or nil
end

function Scan.Get(guid)
    local row = Scan.Peek(guid)
    return cacheFresh(row) and row or nil
end

function Scan.Status(guid)
    if secret(guid) or type(guid) ~= "string" then return nil end
    if inflight and inflight.guid == guid then return "PENDING" end
    if pending and pending.guid == guid then return "PENDING" end
    for _, item in ipairs(queue) do
        if item.guid == guid then return "PENDING" end
    end
    if farUntil[guid] and farUntil[guid] > now() then return "FAR" end
    return nil
end

local function busy()
    local af = AchievementFrame
    return af and af.IsShown and af:IsShown() and true or false
end

-- Fail safe: if the combat check itself is unavailable or secret, treat it as
-- combat and do not touch the protected comparison APIs.
local function inCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, locked = RL.Stats.SafeCall(InCombatLockdown)
    return (not ok) or (locked and true) or false
end

local function settle()
    if pending or inflight or #queue > 0 then
        frame:SetScript("OnUpdate", Scan.Tick)
    else
        frame:SetScript("OnUpdate", nil)
    end
end

-- Blizzard's comparison frame listens for the same event. Silence its own
-- subscription for the duration of one request, then put it back.
local function quietNative(entry)
    local cmp = AchievementFrameComparison
    if not cmp or type(cmp.IsEventRegistered) ~= "function"
        or type(cmp.UnregisterEvent) ~= "function" then
        return
    end
    local ok, registered = pcall(cmp.IsEventRegistered, cmp, "INSPECT_ACHIEVEMENT_READY")
    if ok and registered then
        if pcall(cmp.UnregisterEvent, cmp, "INSPECT_ACHIEVEMENT_READY") then
            entry.mutedNative = true
        end
    end
end

local function restoreNative(entry)
    if not entry or not entry.mutedNative then return end
    entry.mutedNative = nil
    local cmp = AchievementFrameComparison
    if cmp and type(cmp.RegisterEvent) == "function" then
        pcall(cmp.RegisterEvent, cmp, "INSPECT_ACHIEVEMENT_READY")
    end
end

local function comparisonCall(fn, ...)
    inCall = true
    local ok, result = pcall(fn, ...)
    inCall = false
    return ok, result
end

local function releaseComparison()
    if ownsComparison then
        ownsComparison = false
        if type(ClearAchievementComparisonUnit) == "function" then
            comparisonCall(ClearAchievementComparisonUnit)
        end
    end
end

-- If another addon or the native window changes the comparison unit, drop
-- our request instead of reading someone else's answer.
function Scan.WatchComparison()
    if type(hooksecurefunc) ~= "function" then return false end
    local function changed()
        if inCall then return end
        ownsComparison = false
        externalUntil = now() + 5
        Scan.Cancel("BUSY")
    end
    for _, name in ipairs({ "SetAchievementComparisonUnit", "ClearAchievementComparisonUnit" }) do
        if not hooks[name] and type(_G[name]) == "function" then
            hooks[name] = pcall(hooksecurefunc, name, changed)
        end
        if not hooks[name] then return false end
    end
    return true
end

local function queued(guid)
    for _, item in ipairs(queue) do
        if item.guid == guid then return true end
    end
    return false
end

local function enqueue(unit, identity, opts)
    if #queue >= 20 then return false end
    local item = {
        unit = unit,
        guid = identity.guid,
        name = identity.name,
        realm = identity.realm,
        level = identity.level,
        class = identity.class,
        classKey = identity.classKey,
        at = now(),
        priority = opts.priority and true or false,
        manual = opts.manual and true or false,
    }
    if opts.front then
        table.insert(queue, 1, item)
    else
        queue[#queue + 1] = item
    end
    settle()
    return true
end

-- Request a scan. Returns a fresh cached row and "READY", or nil plus a
-- status: PENDING, FAR, HIDDEN, SELF, NPC, NOAPI, COMBAT, BUSY.
function Scan.Request(unit, opts)
    opts = opts or {}
    -- UnitIdentity starts with Stats.PlayerGate, so an NPC / pet / object or
    -- a protected token is rejected before any API read and never queued.
    local identity, why = Stats.UnitIdentity(unit)
    if not identity then
        if why == "npc" then return nil, "NPC" end
        return nil, why == "hidden" and "HIDDEN" or "NONE"
    end
    if not identity.isPlayer or secret(identity.guid) then
        return nil, "NPC"
    end
    if identity.isSelf then
        return nil, "SELF"
    end
    local row = DB.GetPlayer(identity.guid)
    if row and cacheFresh(row) and not opts.force then
        return row, "READY"
    end
    local function unavailable(status)
        DB.RecordAttempt(identity.guid, status)
        return nil, status
    end
    if not Scan.HasAPI() or not Scan.WatchComparison() then
        return unavailable("NOAPI")
    end
    if inCombat() then
        return unavailable("COMBAT")
    end
    if busy() or now() < externalUntil then
        return unavailable("BUSY")
    end
    local status = Scan.Status(identity.guid)
    if status then
        return nil, status
    end
    if opts.queue == false then
        return nil, "BUSY"
    end
    if not enqueue(unit, identity, opts) then return unavailable("BUSY") end
    return nil, "PENDING"
end

function Scan.Cancel(status)
    local entry, waiting = inflight, pending
    frame:UnregisterEvent("INSPECT_ACHIEVEMENT_READY")
    releaseComparison()
    restoreNative(entry)
    inflight, pending, state = nil, nil, "IDLE"
    local queuedItems = queue
    queue = {}
    settle()
    local function cancelled(item)
        if not item then return end
        DB.RecordAttempt(item.guid, status or "CANCELLED")
        notify(item.guid, nil, status or "CANCELLED")
    end
    cancelled(entry)
    cancelled(waiting)
    for _, item in ipairs(queuedItems) do cancelled(item) end
end

local function finish(row, status)
    local entry = inflight
    frame:UnregisterEvent("INSPECT_ACHIEVEMENT_READY")
    releaseComparison()
    restoreNative(entry)
    state = "IDLE"
    inflight = nil

    if entry and not entry.frameWasShown and AchievementFrame
        and AchievementFrame.IsShown and AchievementFrame:IsShown() then
        -- Our request made the native comparison window pop. Hide it and do
        -- not leave it on screen for the player.
        pcall(HideUIPanel, AchievementFrame)
    end

    if entry and status == "READY" and not Stats.RowUsable(row) then status = "NODATA" end
    -- Failed/partial reads do not renew the previous successful snapshot.
    if entry then DB.RecordAttempt(entry.guid, status, row) end

    if entry and status == "READY" and row then
        row.name = entry.name
        row.realm = entry.realm
        row.level = entry.level
        row.class = entry.class
        row.classKey = entry.classKey
        row.at = time()
        row.source = "scan"
        row = DB.Upsert(entry.guid, row)
        Scan.last = entry.guid
        notify(entry.guid, row, "READY")
    elseif entry then
        if status == "TIMEOUT" then Scan.timeouts = Scan.timeouts + 1 end
        notify(entry.guid, nil, status)
    end
    settle()
end

local function fire(entry)
    lastSet = now()
    entry.frameWasShown = busy()
    quietNative(entry)
    state, inflight, ownsComparison = "INFLIGHT", entry, true
    entry.started = now()
    frame:RegisterEvent("INSPECT_ACHIEVEMENT_READY")
    local ok, result = comparisonCall(SetAchievementComparisonUnit, entry.unit)
    if not ok or secret(result) or result == false then
        farUntil[entry.guid] = now() + RL.SCAN.farTTL
        if inflight == entry then finish(nil, "FAR") end
        return
    end
    settle()
end

function Scan.Tick()
    local current = now()
    if (pending or inflight) and inCombat() then
        Scan.Cancel("COMBAT")
        return
    end

    if state == "INFLIGHT" then
        if inflight and current - inflight.started > (inflight.manual and RL.SCAN.manualTimeout or RL.SCAN.hoverTimeout) then
            finish(nil, "TIMEOUT")
        else
            return
        end
    end

    if not pending then
        if #queue == 0 then
            settle()
            return
        end
        pending = table.remove(queue, 1)
        pending.at = current
    end

    if current - pending.at < RL.SCAN.debounce then
        return
    end
    if lastSet and current - lastSet < RL.SCAN.floor then
        return
    end

    -- Re-check the gate right before firing: the mouse may now be over an NPC
    -- even though the queued entry was created for a player.
    if Stats.PlayerGate(pending.unit) ~= "player" then
        local entry = pending
        pending = nil
        DB.RecordAttempt(entry.guid, "CANCELLED")
        notify(entry.guid, nil, "CANCELLED")
        settle()
        return
    end
    local identity = Stats.UnitIdentity(pending.unit)
    if not identity or secret(identity.guid) or identity.guid ~= pending.guid
        or not identity.isPlayer or identity.isSelf then
        local entry = pending
        pending = nil
        DB.RecordAttempt(entry.guid, "CANCELLED")
        notify(entry.guid, nil, "CANCELLED")
        settle()
        return
    end
    if busy() or current < externalUntil then
        local entry = pending
        pending = nil
        DB.RecordAttempt(entry.guid, "BUSY")
        notify(entry.guid, nil, "BUSY")
        settle()
        return
    end
    pending.name = identity.name or pending.name
    pending.realm = identity.realm or pending.realm
    pending.level = identity.level or pending.level
    local entry = pending
    pending = nil
    fire(entry)
end

frame:SetScript("OnEvent", function(_, event, guid)
    if event ~= "INSPECT_ACHIEVEMENT_READY" or state ~= "INFLIGHT" or not inflight then
        return
    end
    if secret(guid) or type(guid) ~= "string" or guid ~= inflight.guid or not ownsComparison then
        return
    end
    if now() - inflight.started > (inflight.manual and RL.SCAN.manualTimeout or RL.SCAN.hoverTimeout) then
        finish(nil, "TIMEOUT")
        return
    end
    if inCombat() then
        Scan.Cancel("COMBAT")
        return
    end
    local identity = Stats.UnitIdentity(inflight.unit)
    if not identity or identity.guid ~= guid then
        Scan.Cancel("CANCELLED")
        return
    end
    local row = Stats.ComparisonRow()
    finish(row, "READY")
end)

function Scan.Init()
    Scan.WatchComparison()
end

-- Queue every non-self party member. Returns how many were requested and how
-- many were already cached.
function Scan.ScanParty(force)
    if type(GetNumGroupMembers) ~= "function" or (GetNumGroupMembers() or 0) <= 0 then
        return 0, 0
    end
    if type(IsInRaid) == "function" and IsInRaid() then
        return 0, 0
    end
    local requested, ready = 0, 0
    for i = 1, 4 do
        local unit = "party" .. i
        local existsOk, exists = Stats.SafeCall(UnitExists, unit)
        if existsOk and exists then
            local row, status = Scan.Request(unit, { force = force, priority = true, manual = true })
            if row and status == "READY" then
                ready = ready + 1
            elseif status == "PENDING" then
                requested = requested + 1
            end
        end
    end
    return requested, ready
end

function Scan.Debug()
    return {
        state = state,
        queue = #queue,
        pending = pending and pending.guid or nil,
        inflight = inflight and inflight.guid or nil,
        api = Scan.HasAPI(),
        timeouts = Scan.timeouts,
    }
end
