-- NinjaWatcher: append owned, single-column rows without touching native rows.
-- FontStrings are pooled by GameTooltip: object identity / an old index is
-- NOT proof of ownership after the native tooltip (or another addon) rebuilds.
local ADDON, NW = ...
local Tooltip = {}
NW.Tooltip = Tooltip
local Stats, Scan, Rate, DB = NW.Stats, NW.Scan, NW.Rate, NW.DB
local shown, drawing, installed = nil, false, false

local function safeText(fs)
    if not fs or type(fs.GetText) ~= "function" then return nil end
    local ok, text = pcall(fs.GetText, fs)
    if not ok or NW.IsSecret(text) or type(text) ~= "string" then return nil end
    return text
end
local function equal(a, b)
    if NW.IsSecret(a) or NW.IsSecret(b) then return false end
    local ok, same = pcall(function() return a == b end)
    return ok and same == true
end
local function lineCount(tooltip)
    if not tooltip or type(tooltip.NumLines) ~= "function" then return nil end
    local ok, count = pcall(tooltip.NumLines, tooltip)
    if not ok or NW.IsSecret(count) or type(count) ~= "number" then return nil end
    return count
end
local function left(index) return _G["GameTooltipTextLeft" .. index] end
local function liveUnit(unit)
    if NW.IsSecret(unit) or type(unit) ~= "string" or unit == "" then return nil end
    local ok, exists = Stats.SafeCall(UnitExists, unit)
    return ok and exists and unit or nil
end
local function tooltipUnit(tooltip)
    if not tooltip or type(tooltip.GetUnit) ~= "function" then return nil end
    local ok, a, b = pcall(tooltip.GetUnit, tooltip)
    if not ok or NW.IsSecret(a) or NW.IsSecret(b) then return nil, true end
    return liveUnit(b) or liveUnit(a)
end
local function currentIdentity(tooltip)
    local unit, blocked = tooltipUnit(tooltip)
    if blocked then return nil end
    return Stats.UnitIdentity(unit or "mouseover")
end
local function ownsRows(record)
    local count = record and lineCount(record.tooltip)
    if not count then return false end
    for _, row in ipairs(record.rows) do
        -- Validate BOTH text and index. Pooled FontStrings can now hold HP,
        -- item level, another player's data or another addon's content.
        if row.index > count or left(row.index) ~= row.fs
            or not equal(safeText(row.fs), row.text) then return false end
    end
    return true
end
local STATUS_KEYS = {
    PENDING="TOOLTIP_PENDING", FAR="TOOLTIP_STATUS_FAR", BUSY="TOOLTIP_STATUS_BUSY",
    COMBAT="TOOLTIP_STATUS_COMBAT", NOAPI="TOOLTIP_STATUS_NOAPI",
    TIMEOUT="TOOLTIP_STATUS_TIMEOUT", NODATA="TOOLTIP_STATUS_NODATA",
}
local function content(row, guid, status)
    local lines, color = {}, NW.COLORS.gray
    if row then
        local result = Rate.Evaluate(row)
        color = Rate.VerdictColor(result)
        lines[1] = NW.L("TOOLTIP_SUMMARY",NW.L("TOOLTIP_LABEL"),Rate.Summary(result,DB.Get("tooltipBand")))
        -- Keep mouseover compact; full context remains in the player catalog.
        lines[2] = NW.L("TOOLTIP_COUNTS",
            Rate.CountText(row, "need"), Rate.CountText(row, "greed"),
            result.rolls and tostring(result.rolls) or NW.L("VALUE_UNKNOWN"))
    else
        lines[1] = NW.L("TOOLTIP_SUMMARY",NW.L("TOOLTIP_LABEL"),NW.L(STATUS_KEYS[status] or "TOOLTIP_UNKNOWN"))
    end
    return lines, color
end
local function relayout(tooltip)
    -- Show recomputes GameTooltip width/height after SetText/AddLine. The
    -- drawing guard prevents processors / OnTooltipSetUnit from reentering.
    if type(tooltip.Show) == "function" then tooltip:Show() end
end
local function paint(tooltip, row, identity, status, refreshOnly)
    if drawing or tooltip ~= GameTooltip or not identity then return end
    local record = shown
    local same = record and record.tooltip == tooltip and equal(record.guid, identity.guid)
    if record and not same then
        -- Do not append data for B to the still-visible tooltip of A. A native
        -- clear/rebuild must remove the previous block first.
        if ownsRows(record) then return end
        shown, record = nil, nil
    end
    if record and not ownsRows(record) then
        -- Never use a stale line number or unreadable text as a write target.
        -- Wait for a native clear/rebuild instead of duplicating our block.
        return
    end
    if refreshOnly and not record then return end
    local lines, color = content(row, identity.guid, status)
    drawing = true
    local ok = pcall(function()
        if not record then
            record = { tooltip=tooltip, guid=identity.guid, identity=identity, rows={} }
        end
        for i=1,math.max(#lines,#record.rows) do
            local text = lines[i] or " "
            local c = i==1 and color or NW.COLORS.gray
            local owned = record.rows[i]
            if owned then
                owned.fs:SetText(text)
                owned.fs:SetTextColor(c[1],c[2],c[3])
                owned.fs:Show()
                owned.text = text
            else
                local count = lineCount(tooltip)
                if not count then error("unreadable tooltip line count") end
                tooltip:AddLine(text,c[1],c[2],c[3],true)
                record.rows[i] = { index=count+1, fs=left(count+1), text=text }
            end
        end
        record.status = row and "READY" or status
        record.row = row
        record.identity = identity
        shown = record
        relayout(tooltip)
    end)
    drawing = false
    if not ok then shown = nil end
end
function Tooltip.Paint(tooltip,row,identity) paint(tooltip,row,identity,"READY") end
function Tooltip.PaintStatus(tooltip,status,identity) paint(tooltip,nil,identity,status) end
function Tooltip.RefreshDisplay()
    if drawing or not shown then return end
    local tooltip = shown.tooltip
    local ok, visible = Stats.SafeCall(tooltip.IsShown,tooltip)
    if not ok or not visible then return end
    local identity = currentIdentity(tooltip)
    if not identity or not equal(identity.guid,shown.guid) then return end
    paint(tooltip,shown.row,identity,shown.status,true)
end
local function refresh(guid,row,status)
    if drawing or not shown or NW.IsSecret(guid) or not equal(shown.guid,guid) then return end
    local tooltip = shown.tooltip
    local ok, visible = Stats.SafeCall(tooltip.IsShown,tooltip)
    if not ok or not visible then return end
    -- The native tooltip may have switched player without hiding. Even when
    -- old addon text remains visible, an A callback must not paint over B.
    local identity = currentIdentity(tooltip)
    if not identity or not equal(identity.guid,guid) then return end
    paint(tooltip,row,identity,status,true)
end
function Tooltip.OnUnit(tooltip)
    if drawing or tooltip ~= GameTooltip or not DB.Get("tooltip") then return end
    local identity = currentIdentity(tooltip)
    if not identity then shown=nil return end
    if identity.isSelf then
        if not DB.Get("selfTooltip") then return end
        local row = Stats.SelfRow()
        if row then
            DB.RecordAttempt(identity.guid,Stats.RowUsable(row) and "READY" or "NODATA",row)
            if Stats.RowUsable(row) then row=DB.Upsert(identity.guid,row) end
            Tooltip.Paint(tooltip,row,identity)
        else Tooltip.PaintStatus(tooltip,"NODATA",identity) end
        return
    end
    local unit, blocked = tooltipUnit(tooltip)
    if blocked then return end
    local row,status = Scan.Request(unit or "mouseover",{front=true})
    if row then Tooltip.Paint(tooltip,row,identity)
    elseif status then Tooltip.PaintStatus(tooltip,status,identity) end
end
function Tooltip.Current()
    if not shown or not ownsRows(shown) then return nil end
    local ok, visible = Stats.SafeCall(shown.tooltip.IsShown,shown.tooltip)
    if not ok or not visible then return nil end
    local identity = currentIdentity(shown.tooltip)
    if not identity or not equal(identity.guid,shown.guid) then return nil end
    return identity,shown.guid
end
function Tooltip.Init()
    if installed then return end
    installed = true
    Scan.OnReady(refresh)
    if GameTooltip and type(GameTooltip.HookScript)=="function" then
        pcall(GameTooltip.HookScript,GameTooltip,"OnHide",function() shown=nil end)
        pcall(GameTooltip.HookScript,GameTooltip,"OnTooltipCleared",function() shown=nil end)
    end
    if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall)=="function"
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        local ok=pcall(TooltipDataProcessor.AddTooltipPostCall,Enum.TooltipDataType.Unit,Tooltip.OnUnit)
        if ok then Tooltip.mode="processor" return end
    end
    if GameTooltip and type(GameTooltip.HookScript)=="function" then
        local ok=pcall(GameTooltip.HookScript,GameTooltip,"OnTooltipSetUnit",Tooltip.OnUnit)
        if ok then Tooltip.mode="script" return end
    end
    local watcher=CreateFrame("Frame")
    watcher:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    watcher:SetScript("OnEvent",function()
        if GameTooltip and GameTooltip:IsShown() then Tooltip.OnUnit(GameTooltip) end
    end)
    Tooltip.mode="event"
end
