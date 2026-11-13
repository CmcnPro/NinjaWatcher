local ADDON, NW = ...
local initialized=false
local events=CreateFrame("Frame")
function NW.Print(message,color)
    if not DEFAULT_CHAT_FRAME or type(DEFAULT_CHAT_FRAME.AddMessage)~="function" then return end
    local c=color or NW.COLORS.white
    DEFAULT_CHAT_FRAME:AddMessage(NW.L("CHAT_PREFIX").." "..tostring(message or ""),c[1],c[2],c[3])
end
local function safeInit(name,fn)
    local ok,err=pcall(fn)
    if not ok then NW.Print(NW.L("INIT_FAILED",name,tostring(err)),NW.COLORS.red) end
    return ok
end
function NW.ApplyRule(a,b,c)
    local ok,reason=NW.Rate.SetRule(a,b,c)
    if not ok then NW.Print(NW.L("CHAT_RULE_BAD",tostring(reason))) return false end
    NW.DB.Set("tier1",a) NW.DB.Set("tier2",b) NW.DB.Set("tier3",c)
    NW.Print(NW.L("CHAT_RULE_SET",a,b,c))
    if NW.Settings then NW.Settings.RefreshRuleUI() end
    return true
end
local function savedRule()
    if not NW.Rate.SetRule(NW.DB.Get("tier1"),NW.DB.Get("tier2"),NW.DB.Get("tier3")) then
        local d=NW.DEFAULTS
        NW.DB.Set("tier1",d.tier1) NW.DB.Set("tier2",d.tier2) NW.DB.Set("tier3",d.tier3)
        NW.Rate.SetRule(d.tier1,d.tier2,d.tier3)
    end
end
local function initData()
    NW.DB.Init()
    NW.I18n.Init()
end
function NW.SetLanguage(value)
    if not NW.I18n.Set(value) then NW.Print(NW.L("LANGUAGE_BAD")) return false end
    NW.Print(NW.L("LANGUAGE_SAVED",NW.I18n.Name(NW.I18n.Preference())))
    if NW.Settings then NW.Settings.RefreshOptions() end
    return true
end
local function login()
    if initialized then return end
    -- Resolve language before creating any static labels or buttons.
    if not safeInit("DB",initData) then return end
    initialized=true
    safeInit("Rule",savedRule)
    for _,name in ipairs({"Scan","Tooltip","Party","Settings","Broadcast","Badge","ChatTag"}) do
        safeInit(name,function() NW[name].Init() end)
    end
    safeInit("UnitMenu",NW.Settings.InitUnitMenu)
end
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent",function(_,event,addon)
    if event=="ADDON_LOADED" and addon==ADDON then safeInit("DB",initData)
    elseif event=="PLAYER_LOGIN" then login() end
end)
local function help()
    for _,key in ipairs({"HELP_MAIN","HELP_SHARE","HELP_TARGET","HELP_BANDS","HELP_LABELS","HELP_CLEAR","HELP_LANGUAGE"}) do
        NW.Print(NW.L(key))
    end
end
SLASH_NINJAWATCHER1="/nw"
SLASH_NINJAWATCHER2="/ninjawatcher"
SlashCmdList.NINJAWATCHER=function(message)
    local input=tostring(message or ""):match("^%s*(.-)%s*$")
    local verb,args=input:match("^(%S+)%s*(.-)$")
    verb=verb and verb:lower() or "" -- preserve case in player names / arguments
    if verb=="" then NW.Settings.Open()
    elseif verb=="scan" then NW.Party.ScanAll(true)
    elseif verb=="status" then
        local identity=NW.Stats.UnitIdentity("player")
        local row=NW.Stats.SelfRow()
        if not identity or not row then NW.Print(NW.L("TOOLTIP_UNKNOWN")) return end
        NW.DB.RecordAttempt(identity.guid,NW.Stats.RowUsable(row) and "READY" or "NODATA",row)
        if NW.Stats.RowUsable(row) then row=NW.DB.Upsert(identity.guid,row) end
        NW.Print(NW.Rate.Summary(NW.Rate.Evaluate(row)).."\n"..NW.Rate.Detail(row).."\n"..NW.DB.DataNote(identity.guid,row))
    elseif verb=="test" then
        local results=NW.Rate.SelfTest()
        local passed=0
        for _,r in ipairs(results) do
            if r.ok then passed=passed+1 else NW.Print(NW.L("TEST_FAILED",r.label),NW.COLORS.red) end
        end
        NW.Print(NW.L("TEST_RESULTS",passed,#results))
    elseif verb=="clear" then
        if args=="confirm" then NW.Print(NW.L("CLEAR_DONE",NW.DB.Clear())) NW.Settings.RefreshPlayers()
        else NW.Print(NW.L("CLEAR_CONFIRM")) end
    elseif verb=="share" then
        local target,extra=args:match("^(%S+)%s*(.-)$")
        NW.Share.SendCurrent(target,extra~="" and extra or nil,target~=nil)
    elseif verb=="target" then
        if args~="" then NW.Share.SetTarget(args) else NW.Print(NW.Share.TargetLabel()) end
    elseif verb=="broadcast" or verb=="bc" then NW.Broadcast.Show()
    elseif verb=="icon" then
        if args=="" then NW.Broadcast.Show() else NW.Broadcast.SetIconMode(args) end
    elseif verb=="badge" then
        if args=="" then NW.Print(NW.Badge.ModeLabel()) else NW.Badge.SetMode(args) end
    elseif verb=="tag" then
        if args=="" then NW.Print(NW.ChatTag.ModeLabel()) else NW.ChatTag.SetMode(args) end
    elseif verb=="language" or verb=="lang" then
        if args=="" then
            NW.Print(NW.L("LANGUAGE_CURRENT",NW.I18n.Name(NW.I18n.Current()),NW.I18n.Name(NW.I18n.Preference())))
            NW.Print(NW.L("HELP_LANGUAGE"))
        else NW.SetLanguage(args) end
    elseif verb=="bands" then
        if args=="on" or args=="off" then NW.DB.Set("showBands",args=="on") NW.Settings.Refresh()
        else NW.Print(NW.L("BANDS_USAGE")) end
    elseif verb=="tier" then
        local a,b,c=args:match("^(%S+)%s+(%S+)%s+(%S+)$")
        NW.ApplyRule(tonumber(a),tonumber(b),tonumber(c))
    elseif verb=="rule" then
        if args=="reset" then local d=NW.DEFAULTS NW.ApplyRule(d.tier1,d.tier2,d.tier3)
        else NW.Print(NW.L("CHAT_RULE_SET",NW.Rate.RuleValues())) end
    elseif verb=="model" or verb=="pass" or verb=="passid" or verb=="export" or verb=="web" then
        NW.Print(NW.L("LEGACY_COMMAND"))
    elseif verb=="debug" then
        local d=NW.Scan.Debug()
        NW.Print(NW.L("DEBUG_STATUS",d.state,d.queue,NW.DB.Count(),d.timeouts))
    else help() end
end
