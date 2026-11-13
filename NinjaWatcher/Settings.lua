-- Maintained UI: paged snapshots, independent data quality and optional bands.
local ADDON, NW = ...
local Settings = {}
NW.Settings = Settings
local DB, Rate, Scan, Stats = NW.DB, NW.Rate, NW.Scan, NW.Stats
local frame, listPage, optionsPage, counter, detailText
local rows, checks, edits = {}, {}, {}
local pageNumber, pageSize, sortMode = 1, 20, "recent"
local highlightGUID, clearUntil = nil, 0
local function label(parent,text,x,y,width)
    local fs=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
    fs:SetWidth(width or 590)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end
local function button(parent,text,x,y,width,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(width or 110,24)
    b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
    b:SetText(text)
    b:SetScript("OnClick",fn)
    return b
end
local function sorted()
    local items=DB.List()
    if sortMode=="rate" then
        table.sort(items,function(a,b)
            local ar,br=Rate.Evaluate(a.row).ratio,Rate.Evaluate(b.row).ratio
            if ar==br then return a.guid<b.guid end
            if ar==nil then return false end
            if br==nil then return true end
            return ar>br
        end)
    end
    return items
end
local function makeRow(i)
    local row=CreateFrame("Button",nil,listPage)
    row:SetSize(600,22)
    row:SetPoint("TOPLEFT",listPage,"TOPLEFT",4,-92-(i-1)*22)
    row.text=label(row,"",0,-3,598)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnEnter",function(self)
        local e=self.entry
        if not e then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:AddLine((e.row.name or "?").."-"..(e.row.realm or "?"),1,1,1)
        GameTooltip:AddLine(Rate.Summary(Rate.Evaluate(e.row)),1,1,1)
        GameTooltip:AddLine(Rate.Detail(e.row),0.8,0.8,0.8,true)
        GameTooltip:AddLine(DB.DataNote(e.guid,e.row),0.7,0.7,0.7,true)
        local report=DB.Reported(e.guid)
        if report then
            GameTooltip:AddLine(NW.L("PERSONAL_NOTE_WARNING"),1,0.82,0,true)
        end
        GameTooltip:AddLine(NW.L("RATE_HINT"),0.65,0.65,0.65,true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave",function() GameTooltip:Hide() end)
    row:SetScript("OnClick",function(self)
        local ok,shift=Stats.SafeCall(IsShiftKeyDown)
        if ok and shift and self.entry then NW.Share.Send(self.entry.guid) end
    end)
    return row
end
function Settings.RefreshPlayers()
    if not listPage then return end
    local items=sorted()
    if highlightGUID then
        for i,e in ipairs(items) do if e.guid==highlightGUID then pageNumber=math.floor((i-1)/pageSize)+1 break end end
    end
    local pages=math.max(1,math.ceil(#items/pageSize))
    pageNumber=math.max(1,math.min(pages,pageNumber))
    for i=1,pageSize do
        local e=items[(pageNumber-1)*pageSize+i]
        if not rows[i] then rows[i]=makeRow(i) end
        local row=rows[i]
        row.entry=e
        if e then
            local result=Rate.Evaluate(e.row)
            local name=e.row.name or "?"
            if e.row.realm then name=name.."-"..e.row.realm end
            local prefix=e.guid==highlightGUID and "> " or ""
            if DB.Reported(e.guid) then prefix=prefix.."★ " end
            local stale=DB.IsFresh(e.row) and "" or " · "..NW.L("DATA_STALE_SHORT")
            row.text:SetText(prefix..name.." · "..Rate.Summary(result)..stale)
            local c=Rate.VerdictColor(result)
            row.text:SetTextColor(c[1],c[2],c[3])
            row:Show()
        else row:Hide() end
    end
    counter:SetText(string.format("共 %d 条 · 第 %d / %d 页（每页 %d 条）",#items,pageNumber,pages,pageSize))
end
function Settings.RefreshOptions()
    for k,cb in pairs(checks) do cb:SetChecked(DB.Get(k)==true) end
    local values={Rate.RuleValues()}
    for i,box in ipairs(edits) do box:SetText(tostring(values[i])) end
    if detailText then detailText:SetText("当前手动分享目标："..NW.Share.TargetLabel().."\n"..NW.Badge.ModeLabel().."；聊天标签："..NW.ChatTag.ModeLabel()) end
end
function Settings.RefreshRuleUI() Settings.RefreshOptions() Settings.RefreshPlayers() end
function Settings.RefreshLinkUI() Settings.RefreshOptions() end
function Settings.RefreshShareTarget() Settings.RefreshOptions() end
function Settings.Refresh()
    if not frame then return end
    Settings.RefreshOptions()
    Settings.RefreshPlayers()
end
function Settings.Open()
    local api=_G.Settings
    if Settings.category and api and type(api.OpenToCategory)=="function" then
        local ok=pcall(function() api.OpenToCategory(Settings.category:GetID()) end)
        if not ok then pcall(api.OpenToCategory,Settings.category.ID) end
    else NW.Print(NW.L("CHAT_NO_SETTINGS")) end
end
function Settings.ShowPlayers(guid)
    highlightGUID=not NW.IsSecret(guid) and type(guid)=="string" and guid or nil
    Settings.Open()
    if listPage then listPage:Show() optionsPage:Hide() Settings.RefreshPlayers() end
end
local function snapshot(row)
    local r=Rate.Evaluate(row or {})
    local a,b,c=Rate.RuleValues()
    return { at=time(), collectedAt=row and row.at, need=row and row.need, greed=row and row.greed,
        entries=row and row.entries, rolls=r.rolls, ratio=r.ratio, band=r.band,
        ruleVersion=NW.RULE_VERSION, tier1=a,tier2=b,tier3=c, kind="personal" }
end
function Settings.ToggleReport(guid,unit)
    if NW.IsSecret(guid) or type(guid)~="string" then return end
    if DB.Reported(guid) then DB.ClearReport(guid)
    else
        if unit then
            local identity=Stats.UnitIdentity(unit)
            if not identity or identity.isSelf or identity.guid~=guid then return end
        end
        DB.SetReport(guid,snapshot(DB.GetPlayer(guid)))
        if not DB.GetPlayer(guid) and unit then Scan.Request(unit,{manual=true}) end
    end
    NW.Print(NW.L("PERSONAL_NOTE_WARNING"))
    Settings.RefreshPlayers()
end
local function checkbox(parent,key,text,y)
    local cb=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate")
    cb:SetSize(26,26)
    cb:SetPoint("TOPLEFT",parent,"TOPLEFT",4,y)
    label(parent,text,34,y-5,555)
    cb:SetScript("OnClick",function(self)
        DB.Set(key,self:GetChecked()==true)
        Settings.RefreshPlayers()
        if NW.Badge then pcall(NW.Badge.Refresh) end
    end)
    checks[key]=cb
end
function Settings.Init()
    if frame then return end
    local api=_G.Settings
    if type(api)~="table" or type(api.RegisterCanvasLayoutCategory)~="function" then return end
    frame=CreateFrame("Frame","NinjaWatcherSettingsFrame",UIParent)
    frame:SetSize(640,700)
    frame:Hide()
    label(frame,"NinjaWatcher · 统计参考  "..NW.VERSION,8,-8,600)
    label(frame,NW.L("RATE_HINT"),8,-32,600)
    listPage=CreateFrame("Frame",nil,frame)
    listPage:SetPoint("TOPLEFT",frame,"TOPLEFT",8,-100)
    listPage:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-8,8)
    optionsPage=CreateFrame("Frame",nil,frame)
    optionsPage:SetAllPoints(listPage)
    button(frame,"玩家记录",8,-68,110,function() listPage:Show() optionsPage:Hide() Settings.RefreshPlayers() end)
    button(frame,"显示与提醒",126,-68,130,function() listPage:Hide() optionsPage:Show() Settings.RefreshOptions() end)
    label(listPage,"悬停查看计数、采集时间与最近失败；Shift+点击手动分享。★仅为个人标记。",4,-4,600)
    button(listPage,"扫描小队",4,-30,110,function() NW.Party.ScanAll(true) end)
    button(listPage,"最近 / 占比排序",122,-30,140,function()
        sortMode=sortMode=="recent" and "rate" or "recent"
        highlightGUID=nil pageNumber=1 Settings.RefreshPlayers()
    end)
    local clearButton
    clearButton=button(listPage,"清除全部记录",270,-30,140,function()
        if time()>clearUntil then
            clearUntil=time()+5 clearButton:SetText("5秒内再点确认") return
        end
        DB.Clear() clearUntil=0 clearButton:SetText("清除全部记录") Settings.RefreshPlayers()
    end)
    button(listPage,"上一页",4,-560,90,function() highlightGUID=nil pageNumber=pageNumber-1 Settings.RefreshPlayers() end)
    button(listPage,"下一页",102,-560,90,function() highlightGUID=nil pageNumber=pageNumber+1 Settings.RefreshPlayers() end)
    counter=label(listPage,"",4,-70,600)
    local opts={
        {"tooltip","悬停显示统计"},{"selfTooltip","悬停自己时显示统计"},
        {"showBands","启用占比颜色及描述（非风险等级，默认关闭）"},
        {"localAlert","启用小队本地数值提醒（默认关闭，累计掷骰至少30次）"},
        {"partyAlert","启用5人小队自动公开数值提醒（默认关闭）"},
        {"badgeShowUnknown","框体标签显示未记录玩家"},
    }
    for i,o in ipairs(opts) do checkbox(optionsPage,o[1],o[2],-(i-1)*32) end
    label(optionsPage,"可选占比分档界值（百分比，非经验证的行为界线）",8,-204,590)
    local values={Rate.RuleValues()}
    for i=1,3 do
        local box=CreateFrame("EditBox",nil,optionsPage,"InputBoxTemplate")
        box:SetSize(56,24) box:SetPoint("TOPLEFT",optionsPage,"TOPLEFT",12+(i-1)*70,-232)
        box:SetAutoFocus(false) box:SetMaxLetters(2) box:SetText(tostring(values[i]))
        box:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        edits[i]=box
    end
    button(optionsPage,"应用界值",230,-232,110,function()
        NW.ApplyRule(tonumber(edits[1]:GetText()),tonumber(edits[2]:GetText()),tonumber(edits[3]:GetText()))
    end)
    button(optionsPage,"切换分享目标",8,-276,160,function() NW.Share.NextTarget() Settings.RefreshOptions() end)
    button(optionsPage,"切换框体标签",176,-276,160,function() NW.Badge.NextMode() Settings.RefreshOptions() end)
    button(optionsPage,"切换聊天标签",344,-276,160,function() NW.ChatTag.NextMode() Settings.RefreshOptions() end)
    detailText=label(optionsPage,"",8,-314,590)
    label(optionsPage,"需求占比始终为 N/(N+G)，不受进本次数影响。少于20次仅提示计数较少，不隐藏占比。\n进本次数可独立缺失；没有放弃估算，不根据累计计数认定恶意。\n所有记录和设置为账号级本地数据；公开分享和自动小队提醒会让其他玩家看到。\n数据读取失败不刷新旧快照；过期记录会明确标记。",8,-370,590)
    button(optionsPage,"恢复默认设置",8,-486,160,function()
        DB.ResetOptions()
        local d=NW.DEFAULTS NW.ApplyRule(d.tier1,d.tier2,d.tier3)
        NW.Broadcast.SetIconMode(d.iconMode)
        Settings.Refresh()
    end)
    frame:SetScript("OnShow",Settings.Refresh)
    frame.OnRefresh=Settings.Refresh
    frame.OnCommit=function() end
    frame.OnDefault=function() DB.ResetOptions() local d=NW.DEFAULTS NW.ApplyRule(d.tier1,d.tier2,d.tier3) Settings.Refresh() end
    local category=api.RegisterCanvasLayoutCategory(frame,"NinjaWatcher 统计参考")
    api.RegisterAddOnCategory(category)
    Settings.category=category
    listPage:Show() optionsPage:Hide()
    Scan.OnReady(function(guid,row,status)
        if status=="READY" and row then DB.FillReport(guid,snapshot(row)) end
        if frame:IsShown() then Settings.RefreshPlayers() end
    end)
end
function Settings.InitUnitMenu()
    if type(Menu)~="table" or type(Menu.ModifyMenu)~="function" then return end
    local added=setmetatable({},{__mode="k"})
    for _,tag in ipairs({"MENU_UNIT_PLAYER","MENU_UNIT_PARTY","MENU_UNIT_RAID_PLAYER","MENU_UNIT_TARGET","MENU_UNIT_FOCUS"}) do
        pcall(Menu.ModifyMenu,tag,function(_,description,context)
            if type(description)~="table" or added[description] then return end
            local unit=type(context)=="table" and context.unit or nil
            if NW.IsSecret(unit) or type(unit)~="string" then return end
            local identity=Stats.UnitIdentity(unit)
            if not identity or identity.isSelf then return end
            added[description]=true
            local guid=identity.guid
            if description.CreateDivider then description:CreateDivider() end
            description:CreateButton("查看掷骰统计",function()
                Settings.ShowPlayers(guid) Scan.Request(unit,{manual=true,force=true})
            end)
            description:CreateButton("手动分享统计",function() NW.Share.Send(guid,unit) end)
            description:CreateButton(DB.Reported(guid) and "取消个人标记" or "个人标记（非举报）",function() Settings.ToggleReport(guid,unit) end)
        end)
    end
end
