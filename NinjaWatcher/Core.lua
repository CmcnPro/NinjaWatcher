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
    if not ok then NW.Print("初始化失败（"..name.."）："..tostring(err),NW.COLORS.red) end
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
local function login()
    if initialized then return end
    -- A failed DB migration must stop initialization, not silently continue.
    if not safeInit("DB",NW.DB.Init) then return end
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
    if event=="ADDON_LOADED" and addon==ADDON then safeInit("DB",NW.DB.Init)
    elseif event=="PLAYER_LOGIN" then login() end
end)
local function help()
    NW.Print("/nw 打开设置；/nw scan 扫描小队；/nw status 自身统计；/nw test 自测")
    NW.Print("/nw share [self|edit|party|raid|say|guild|whisper 玩家名] 手动分享")
    NW.Print("/nw target <目标> 分享目标；/nw broadcast 通报面板；/nw icon <minimap|float|hide>")
    NW.Print("/nw bands <on|off> 可选占比颜色；/nw tier <15 35 55> 界值；/nw rule [reset]")
    NW.Print("/nw badge <auto|on|off> 框体标签；/nw tag <off|whisper|all> 聊天标签")
    NW.Print("/nw clear，再输入 /nw clear confirm 清除记录（含迁移备份）；/nw debug 扫描状态")
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
            if r.ok then passed=passed+1 else NW.Print("FAIL "..r.label,NW.COLORS.red) end
        end
        NW.Print(string.format("通过 %d / %d",passed,#results))
    elseif verb=="clear" then
        if args=="confirm" then NW.Print("已清除 "..NW.DB.Clear().." 条记录。") NW.Settings.RefreshPlayers()
        else NW.Print("输入 /nw clear confirm 确认清除全部记录、个人标记及迁移备份。") end
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
    elseif verb=="bands" then
        if args=="on" or args=="off" then NW.DB.Set("showBands",args=="on") NW.Settings.Refresh()
        else NW.Print("/nw bands on 或 /nw bands off；仅为占比分档，不是风险等级。") end
    elseif verb=="tier" then
        local a,b,c=args:match("^(%S+)%s+(%S+)%s+(%S+)$")
        NW.ApplyRule(tonumber(a),tonumber(b),tonumber(c))
    elseif verb=="rule" then
        if args=="reset" then local d=NW.DEFAULTS NW.ApplyRule(d.tier1,d.tier2,d.tier3)
        else NW.Print(NW.L("CHAT_RULE_SET",NW.Rate.RuleValues())) end
    elseif verb=="model" or verb=="pass" or verb=="passid" or verb=="export" or verb=="web" then
        NW.Print("维护版已移除进本免责、放弃推算与第三方网站对接；这些旧命令不再生效。")
    elseif verb=="debug" then
        local d=NW.Scan.Debug()
        NW.Print(string.format("状态 %s；队列 %d；记录 %d；超时 %d",d.state,d.queue,NW.DB.Count(),d.timeouts))
    else help() end
end
