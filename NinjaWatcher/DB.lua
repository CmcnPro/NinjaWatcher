-- Schema 2: latest observations, last scan attempts and independent personal notes.
local ADDON, NW = ...
local DB = {}
NW.DB = DB
local SCHEMA = 2
local function count(v) return NW.Rate.IsCount(v) end
local function text(v, limit)
    if NW.IsSecret(v) or type(v) ~= "string" then return nil end
    local s = v:gsub("[%c|]", " ")
    if s == "" then return nil end
    local n = limit or 160
    if #s > n then
        local cut = n + 1
        while cut > 1 and s:byte(cut) >= 128 and s:byte(cut) < 192 do cut = cut - 1 end
        s = s:sub(1, cut-1)
    end
    return s
end
local function guidOK(guid)
    return not NW.IsSecret(guid) and type(guid)=="string" and guid~=""
end
local function copy(v)
    if type(v)~="table" then return v end
    local out={}
    for k,x in pairs(v) do out[k]=copy(x) end
    return out
end
local function cleanRow(row)
    row = type(row)=="table" and row or {}
    local out={ quality={} }
    for _,k in ipairs({"name","realm","class","classKey","source"}) do out[k]=text(row[k]) end
    for _,k in ipairs({"level","at","firstAt","scanCount"}) do out[k]=count(row[k]) and row[k] or nil end
    for _,k in ipairs({"need","greed","entries"}) do
        local q=type(row.quality)=="table" and row.quality[k] or nil
        if count(row[k]) and (q==nil or q=="readable") then
            out[k],out.quality[k]=row[k],"readable"
        else
            out.quality[k]=q=="zero" and "unreported" or text(q,24) or "unknown"
        end
    end
    return out
end
local function normalise()
    if type(NinjaWatcherDB)~="table" then NinjaWatcherDB={} end
    local db=NinjaWatcherDB
    if type(db.version)=="number" and db.version>SCHEMA then
        error(NW.L("DB_NEWER_SCHEMA"))
    end
    if db.version~=SCHEMA then
        -- Keep a one-time pre-migration copy, including old classifier options
        -- and notes. Legacy dash-derived quality='zero' cannot be trusted.
        if next(db) and not db.legacyBackup then db.legacyBackup=copy(db) end
        local players={}
        if type(db.players)=="table" then
            for guid,row in pairs(db.players) do
                if guidOK(guid) and type(row)=="table" then players[guid]=cleanRow(row) end
            end
        end
        db.players=players
        db.options=type(db.options)=="table" and db.options or {}
        db.options.partyAlert,db.options.localAlert=false,false
        db.options.showBands=false
        db.options.chatTagMode="off"
        db.options.qLo,db.options.passStatId,db.options.webUrl=nil,nil,nil
        db.version=SCHEMA
    end
    for _,k in ipairs({"options","players","reports","attempts"}) do
        if type(db[k])~="table" then db[k]={} end
    end
    for k,v in pairs(NW.DEFAULTS) do if db.options[k]==nil then db.options[k]=v end end
    return db
end
function DB.Init() return normalise() end
function DB.Get(k)
    local v=normalise().options[k]
    if v==nil then return NW.DEFAULTS[k] end
    return v
end
function DB.Set(k,v) normalise().options[k]=v end
function DB.ResetOptions()
    normalise().options={}
    normalise()
end
function DB.Players() return normalise().players end
function DB.GetPlayer(guid)
    if not guidOK(guid) then return nil end
    local row=normalise().players[guid]
    return type(row)=="table" and row or nil
end
local index=nil
function DB.Upsert(guid,row)
    if not guidOK(guid) or type(row)~="table" then return nil end
    local db=normalise()
    local previous=DB.GetPlayer(guid)
    local out=cleanRow(row)
    out.at=out.at or time()
    out.firstAt=previous and previous.firstAt or out.at
    out.scanCount=previous and (tonumber(previous.scanCount) or 0)+1 or 1
    db.players[guid]=out
    index=nil
    return out
end
function DB.RecordAttempt(guid,status,row)
    if not guidOK(guid) then return end
    normalise().attempts[guid]={ at=time(), status=text(status,24) or "UNKNOWN",
        observation=type(row)=="table" and cleanRow(row) or nil }
end
function DB.LastAttempt(guid)
    return guidOK(guid) and normalise().attempts[guid] or nil
end
function DB.IsFresh(row)
    if type(row)~="table" or not count(row.at) or not NW.Stats.RowUsable(row) then return false end
    local ttl=tonumber(DB.Get("cacheMinutes")) or 10
    local age=time()-row.at
    return age>=0 and age<math.max(1,ttl)*60
end
function DB.TimeText(row)
    if not row or not count(row.at) then return NW.L("VALUE_UNKNOWN") end
    if type(date)=="function" then
        local ok,s=pcall(date,"%m-%d %H:%M",row.at)
        if ok then return s end
    end
    return tostring(row.at)
end
function DB.DataNote(guid,row)
    local note=DB.IsFresh(row) and NW.L("DATA_RECENT") or NW.L("DATA_STALE")
    note=note .. " · " .. NW.L("DATA_COLLECTED",DB.TimeText(row))
    local attempt=DB.LastAttempt(guid)
    if attempt and attempt.status~="READY" and (not row or attempt.at >= (row.at or 0)) then
        note=note .. " · " .. NW.L("DATA_LAST_FAILED",NW.L("SCAN_"..attempt.status))
    end
    return note
end
function DB.Remove(guid)
    if not guidOK(guid) then return false end
    local db=normalise()
    local existed=db.players[guid]~=nil
    db.players[guid],db.attempts[guid],db.reports[guid]=nil,nil,nil
    index=nil
    return existed
end
function DB.Clear()
    local db=normalise()
    local n=DB.Count()
    db.players,db.reports,db.attempts,db.legacyBackup={},{},{},nil
    index=nil
    return n
end
function DB.Count()
    local n=0
    for _ in pairs(normalise().players) do n=n+1 end
    return n
end
function DB.List()
    local out={}
    for guid,row in pairs(normalise().players) do
        if guidOK(guid) and type(row)=="table" then out[#out+1]={guid=guid,row=row} end
    end
    table.sort(out,function(a,b)
        if (a.row.at or 0)==(b.row.at or 0) then return a.guid<b.guid end
        return (a.row.at or 0)>(b.row.at or 0)
    end)
    return out
end
local function nameKey(name)
    local s=text(name)
    return s and s:gsub("%s+",""):lower() or nil
end
function DB.FindByName(name)
    local key=nameKey(name)
    if not key then return nil end
    if not index then
        index={}
        local function put(k,guid)
            if k then index[k]=index[k]==nil and guid or false end
        end
        for guid,row in pairs(DB.Players()) do
            local base=nameKey(row.name)
            put(base,guid)
            if base and row.realm then put(base.."-"..nameKey(row.realm),guid) end
        end
    end
    local guid=index[key]
    if guid then return DB.GetPlayer(guid),guid end
end
function DB.Reported(guid)
    return guidOK(guid) and normalise().reports[guid] or nil
end
function DB.SetReport(guid,snapshot)
    if not guidOK(guid) then return nil end
    local r=copy(type(snapshot)=="table" and snapshot or {})
    r.at=r.at or time()
    r.ruleVersion=NW.RULE_VERSION
    normalise().reports[guid]=r
    return r
end
function DB.FillReport(guid,snapshot)
    local r=DB.Reported(guid)
    if not r or r.collectedAt or r.rolls or type(snapshot)~="table" then return r end
    local markedAt=r.at
    for k,v in pairs(snapshot) do r[k]=v end
    r.at=markedAt
    return r
end
function DB.ClearReport(guid)
    if not guidOK(guid) then return false end
    local db=normalise()
    local exists=db.reports[guid]~=nil
    db.reports[guid]=nil
    return exists
end
