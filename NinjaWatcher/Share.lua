-- Manual, neutral sharing. Default local; public sends require explicit consent.
local ADDON, NW = ...
local Share = {}
NW.Share = Share
local DB, Stats, Rate = NW.DB, NW.Stats, NW.Rate
local TARGETS = {
    self={label="SHARE_TARGET_SELF"}, edit={label="SHARE_TARGET_EDIT"},
    say={label="SHARE_TARGET_SAY",channel="SAY"}, party={label="SHARE_TARGET_PARTY",channel="PARTY"},
    raid={label="SHARE_TARGET_RAID",channel="RAID"}, guild={label="SHARE_TARGET_GUILD",channel="GUILD"},
    whisper={label="SHARE_TARGET_WHISPER",channel="WHISPER"},
}
local ORDER={"self","edit","say","party","raid","guild","whisper"}
local ALIASES={ ["本地"]="self",["输入框"]="edit",["说"]="say",["小队"]="party",["队伍"]="party",
    ["团队"]="raid",["公会"]="guild",["密语"]="whisper",["私聊"]="whisper" }
local pending, lastSend=nil,{}
local function shorten(s,n)
    if #s<=n then return s end
    local cut=n+1
    while cut>1 and s:byte(cut)>=128 and s:byte(cut)<192 do cut=cut-1 end
    return s:sub(1,cut-1)
end
local function clean(s,n)
    if NW.IsSecret(s) or type(s)~="string" then return nil end
    s=s:gsub("[%c|]"," "):match("^%s*(.-)%s*$")
    if s=="" then return nil end
    return shorten(s,n or 64)
end
local function normalize(s)
    if NW.IsSecret(s) or type(s)~="string" then return "self" end
    s=s:lower():match("^%s*(.-)%s*$")
    return TARGETS[s] and s or ALIASES[s] or "self"
end
local function build(guid,row)
    if not row then return nil end
    local name=clean(row.name,48) or "?"
    local realm=clean(row.realm,48)
    if realm then name=name.."-"..realm end
    -- Never truncate away the caveat. Drop optional details first.
    local prefix="NinjaWatcher："..name.." "..Rate.Summary(Rate.Evaluate(row))
    local note=DB.IsFresh(row) and NW.L("DATA_RECENT") or NW.L("DATA_STALE")
    local suffix="（"..note.." "..DB.TimeText(row).."；统计不代表恶意需求）"
    local message=prefix.."；需求"..Rate.CountText(row,"need").."/贪婪"..Rate.CountText(row,"greed")..suffix
    if #message>255 then message=prefix..suffix end
    if #message>255 then message="NinjaWatcher："..shorten(name,36).." "..Rate.Summary(Rate.Evaluate(row))..suffix end
    if #message>255 then return nil end
    return message
end
function Share.Target() return normalize(DB.Get("shareTarget")) end
function Share.TargetLabel() return NW.L(TARGETS[Share.Target()].label) end
function Share.SetTarget(v)
    local key=normalize(v)
    DB.Set("shareTarget",key)
    pending=nil
    NW.Print(NW.L("SHARE_TARGET_SET",Share.TargetLabel()))
    return key
end
function Share.NextTarget()
    local key=Share.Target()
    for i,v in ipairs(ORDER) do if v==key then return Share.SetTarget(ORDER[i % #ORDER+1]) end end
end
function Share.CanBroadcast(key)
    local ok,raid=Stats.SafeCall(IsInRaid)
    if key=="raid" then return ok and raid==true end
    local groupOK,group=Stats.SafeCall(IsInGroup)
    if not groupOK then
        local sizeOK,size=Stats.SafeCall(GetNumGroupMembers)
        group=sizeOK and type(size)=="number" and size>0
    end
    return key=="party" and group==true
end
function Share.MessageFor(guid)
    return build(guid,DB.GetPlayer(guid))
end
function Share.Send(guid,unit,target,whisperTo,explicit)
    if NW.IsSecret(guid) or type(guid)~="string" then return false end
    local row=DB.GetPlayer(guid)
    if not row then
        NW.Print(NW.L("SHARE_NO_DATA"))
        if unit then pcall(NW.Scan.Request,unit,{manual=true}) end
        return false
    end
    local key=target~=nil and normalize(target) or Share.Target()
    local channel=TARGETS[key].channel
    if channel and not explicit then
        local id=guid.."|"..key
        if not pending or pending.id~=id or time()-pending.at>=30 then
            pending={id=id,at=time()}
            NW.Print(NW.L("SHARE_CONFIRM",NW.L(TARGETS[key].label)))
            return false
        end
        pending=nil
    end
    if (key=="party" or key=="raid") and not Share.CanBroadcast(key) then
        NW.Print(NW.L(key=="raid" and "SHARE_NOT_IN_RAID" or "SHARE_NOT_IN_PARTY"))
        return false
    end
    -- Local output includes full snapshot date and latest scan failure.
    if key=="self" then
        NW.Print((build(guid,row) or Rate.Summary(Rate.Evaluate(row))).."\n"..Rate.Detail(row).."\n"..DB.DataNote(guid,row))
        return true
    end
    local message=build(guid,row)
    if not message then NW.Print(NW.L("SHARE_BAD_DATA")) return false end
    if key=="edit" then
        if type(ChatFrame_OpenChat)=="function" then return pcall(ChatFrame_OpenChat,message) end
        return false
    end
    local recipient=key=="whisper" and clean(whisperTo,100) or nil
    if key=="whisper" and not recipient then NW.Print(NW.L("SHARE_NO_WHISPER")) return false end
    if type(SendChatMessage)~="function" then return false end
    local id=guid.."|"..key
    if lastSend[id] and time()-lastSend[id]<5 then NW.Print(NW.L("SHARE_COOLDOWN")) return false end
    local ok=pcall(SendChatMessage,message,channel,nil,recipient)
    if ok then lastSend[id]=time() NW.Print(NW.L("SHARE_SENT",NW.L(TARGETS[key].label))) end
    return ok
end
function Share.SendCurrent(target,whisperTo,explicit)
    local guid,unit
    if NW.Tooltip then
        local identity,cached=NW.Tooltip.Current()
        guid=cached or (identity and identity.guid)
    end
    if not guid then
        for _,token in ipairs({"mouseover","target"}) do
            local identity=Stats.UnitIdentity(token)
            if identity then guid,unit=identity.guid,token break end
        end
    end
    return Share.Send(guid,unit,target,whisperTo,explicit)
end
function Share.Broadcast(guid,key,unit)
    if key~="party" and key~="raid" then return false end
    return Share.Send(guid,unit,key,nil,true)
end
function Share.Verdict(row,guid)
    local result=Rate.Evaluate(row or {})
    local note=row and not DB.IsFresh(row) and " · "..NW.L("DATA_STALE_SHORT") or ""
    return Rate.Summary(result)..note,Rate.VerdictColor(result)
end
