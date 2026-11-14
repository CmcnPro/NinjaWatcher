local ADDON, RL = ...
local initialized=false
local events=CreateFrame("Frame")
function RL.Print(message,color)
    if not DEFAULT_CHAT_FRAME or type(DEFAULT_CHAT_FRAME.AddMessage)~="function" then return end
    local c=color or RL.COLORS.white
    DEFAULT_CHAT_FRAME:AddMessage(RL.L("CHAT_PREFIX").." "..tostring(message or ""),c[1],c[2],c[3])
end
local function safeInit(name,fn)
    local ok,err=pcall(fn)
    if not ok then RL.Print(RL.L("INIT_FAILED",name,tostring(err)),RL.COLORS.red) end
    return ok
end
function RL.ApplyRule(a,b,c)
    local ok,reason=RL.Rate.SetRule(a,b,c)
    if not ok then RL.Print(RL.L("CHAT_RULE_BAD",tostring(reason))) return false end
    RL.DB.Set("tier1",a) RL.DB.Set("tier2",b) RL.DB.Set("tier3",c)
    RL.Print(RL.L("CHAT_RULE_SET",a,b,c))
    if RL.Settings then RL.Settings.RefreshRuleUI() end
    return true
end
local function savedRule()
    if not RL.Rate.SetRule(RL.DB.Get("tier1"),RL.DB.Get("tier2"),RL.DB.Get("tier3")) then
        local d=RL.DEFAULTS
        RL.DB.Set("tier1",d.tier1) RL.DB.Set("tier2",d.tier2) RL.DB.Set("tier3",d.tier3)
        RL.Rate.SetRule(d.tier1,d.tier2,d.tier3)
    end
end
local function initData()
    RL.DB.Init()
    RL.I18n.Init()
end
function RL.SetLanguage(value)
    if not RL.I18n.Set(value) then RL.Print(RL.L("LANGUAGE_BAD")) return false end
    RL.Print(RL.L("LANGUAGE_SAVED",RL.I18n.Name(RL.I18n.Preference())))
    if RL.Settings then RL.Settings.RefreshOptions() end
    return true
end
local function login()
    if initialized then return end
    -- Resolve language before creating any static labels or buttons.
    if not safeInit("DB",initData) then return end
    initialized=true
    safeInit("Rule",savedRule)
    for _,name in ipairs({"Scan","Tooltip","Party","Settings","Broadcast","Badge","ChatTag"}) do
        safeInit(name,function() RL[name].Init() end)
    end
    safeInit("UnitMenu",RL.Settings.InitUnitMenu)
end
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent",function(_,event,addon)
    if event=="ADDON_LOADED" and addon==ADDON then safeInit("DB",initData)
    elseif event=="PLAYER_LOGIN" then login() end
end)
local function help()
    for _,key in ipairs({"HELP_MAIN","HELP_SHARE","HELP_TARGET","HELP_BANDS","HELP_LABELS","HELP_CLEAR","HELP_LANGUAGE"}) do
        RL.Print(RL.L(key))
    end
end
SLASH_ROLLLEDGER1="/rledger"
SLASH_ROLLLEDGER2="/rollledger"
SlashCmdList.ROLLLEDGER=function(message)
    local input=tostring(message or ""):match("^%s*(.-)%s*$")
    local verb,args=input:match("^(%S+)%s*(.-)$")
    verb=verb and verb:lower() or "" -- preserve case in player names / arguments
    if verb=="" then RL.Settings.Open()
    elseif verb=="scan" then RL.Party.ScanAll(true)
    elseif verb=="status" then
        local identity=RL.Stats.UnitIdentity("player")
        local row=RL.Stats.SelfRow()
        if not identity or not row then RL.Print(RL.L("TOOLTIP_UNKNOWN")) return end
        RL.DB.RecordAttempt(identity.guid,RL.Stats.RowUsable(row) and "READY" or "NODATA",row)
        if RL.Stats.RowUsable(row) then row=RL.DB.Upsert(identity.guid,row) end
        RL.Print(RL.Rate.Summary(RL.Rate.Evaluate(row)).."\n"..RL.Rate.Detail(row).."\n"..RL.DB.DataNote(identity.guid,row))
    elseif verb=="test" then
        local results=RL.Rate.SelfTest()
        local passed=0
        for _,r in ipairs(results) do
            if r.ok then passed=passed+1 else RL.Print(RL.L("TEST_FAILED",r.label),RL.COLORS.red) end
        end
        RL.Print(RL.L("TEST_RESULTS",passed,#results))
    elseif verb=="clear" then
        if args=="confirm" then RL.Print(RL.L("CLEAR_DONE",RL.DB.Clear())) RL.Settings.RefreshPlayers()
        else RL.Print(RL.L("CLEAR_CONFIRM")) end
    elseif verb=="share" then
        local target,extra=args:match("^(%S+)%s*(.-)$")
        RL.Share.SendCurrent(target,extra~="" and extra or nil,target~=nil)
    elseif verb=="target" then
        if args~="" then RL.Share.SetTarget(args) else RL.Print(RL.Share.TargetLabel()) end
    elseif verb=="broadcast" or verb=="bc" then RL.Broadcast.Show()
    elseif verb=="icon" then
        if args=="" then RL.Broadcast.Show() else RL.Broadcast.SetIconMode(args) end
    elseif verb=="badge" then
        if args=="" then RL.Print(RL.Badge.ModeLabel()) else RL.Badge.SetMode(args) end
    elseif verb=="tag" then
        if args=="" then RL.Print(RL.ChatTag.ModeLabel()) else RL.ChatTag.SetMode(args) end
    elseif verb=="language" or verb=="lang" then
        if args=="" then
            RL.Print(RL.L("LANGUAGE_CURRENT",RL.I18n.Name(RL.I18n.Current()),RL.I18n.Name(RL.I18n.Preference())))
            RL.Print(RL.L("HELP_LANGUAGE"))
        else RL.SetLanguage(args) end
    elseif verb=="bands" then
        if args=="on" or args=="off" then RL.DB.Set("showBands",args=="on") RL.Settings.Refresh()
        else RL.Print(RL.L("BANDS_USAGE")) end
    elseif verb=="tier" then
        local a,b,c=args:match("^(%S+)%s+(%S+)%s+(%S+)$")
        RL.ApplyRule(tonumber(a),tonumber(b),tonumber(c))
    elseif verb=="rule" then
        if args=="reset" then local d=RL.DEFAULTS RL.ApplyRule(d.tier1,d.tier2,d.tier3)
        else RL.Print(RL.L("CHAT_RULE_SET",RL.Rate.RuleValues())) end
    elseif verb=="model" or verb=="pass" or verb=="passid" or verb=="export" or verb=="web" then
        RL.Print(RL.L("LEGACY_COMMAND"))
    elseif verb=="debug" then
        local d=RL.Scan.Debug()
        RL.Print(RL.L("DEBUG_STATUS",d.state,d.queue,RL.DB.Count(),d.timeouts))
    else help() end
end
