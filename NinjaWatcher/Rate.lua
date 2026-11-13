-- Pure Lua descriptive statistics. E never affects the share or its band.
local ADDON, NW = ...
local Rate = {}
NW.Rate = Rate
function Rate.IsCount(v)
    return type(v) == "number" and v == v and v >= 0 and v < math.huge and v == math.floor(v)
end
function Rate.FieldUsable(row, field)
    if type(row) ~= "table" or not Rate.IsCount(row[field]) then return false end
    local q = type(row.quality) == "table" and row.quality[field] or nil
    return q == nil or q == "readable"
end
function Rate.SetRule(a, b, c)
    for _, v in ipairs({ a, b, c }) do
        if type(v) ~= "number" or v ~= math.floor(v) then return false, "integer" end
    end
    if type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number"
        or not (a > 0 and a < b and b < c and c < 100) then return false, "order" end
    NW.RULE.darkGreenBelow, NW.RULE.greenBelow, NW.RULE.yellowBelow = a/100, b/100, c/100
    return true
end
function Rate.RuleValues()
    local r = NW.RULE
    return math.floor(r.darkGreenBelow*100+0.5), math.floor(r.greenBelow*100+0.5), math.floor(r.yellowBelow*100+0.5)
end
function Rate.Evaluate(need, greed, entries, quality)
    local row = type(need) == "table" and need or { need=need, greed=greed, entries=entries, quality=quality }
    local out = { status="unknown", ruleVersion=NW.RULE_VERSION, need=row.need, greed=row.greed }
    for _, field in ipairs({ "need", "greed" }) do
        if not Rate.FieldUsable(row, field) then
            local q = type(row.quality) == "table" and row.quality[field] or "missing"
            out.reason = field .. ":" .. tostring(q or "missing")
            return out
        end
    end
    out.entries = Rate.FieldUsable(row, "entries") and row.entries or nil
    out.rolls = row.need + row.greed
    if out.rolls == 0 then out.status="empty" return out end
    out.status, out.branch = "ok", "greed" -- legacy branch name for UI subscribers
    out.ratio = row.need / out.rolls
    out.sampleLevel = out.rolls < NW.RULE.sampleBelowRolls and "small" or "recorded"
    local p, r = out.ratio, NW.RULE
    out.band = p < r.darkGreenBelow and "darkgreen" or p < r.greenBelow and "green"
        or p < r.yellowBelow and "yellow" or "red"
    return out
end
function Rate.Tier(result)
    if not result or result.status ~= "ok" then return nil end
    return ({ darkgreen=1, green=2, yellow=3, red=4 })[result.band]
end
function Rate.TierKey(result, prefix)
    local tier = Rate.Tier(result)
    return tier and (prefix or "TIER_") .. tier or nil
end
function Rate.BandLabelKey(band)
    return ({ darkgreen="BAND_DARKGREEN", green="BAND_GREEN", yellow="BAND_YELLOW", red="BAND_RED", gray="BAND_GRAY" })[band] or "BAND_UNKNOWN"
end
function Rate.Color(band)
    if not NW.DB or NW.DB.Get("showBands") ~= true then return NW.COLORS.white end
    return NW.COLORS[band] or NW.COLORS.gray
end
function Rate.VerdictColor(result)
    if not result or result.status ~= "ok" then return NW.COLORS.gray end
    return Rate.Color(result.band)
end
function Rate.Summary(result, showBand)
    if not result or result.status == "unknown" then return NW.L("TOOLTIP_UNKNOWN") end
    if result.status == "empty" then return NW.L("EMPTY_ROLLS") end
    local text = NW.L("SHARE_RATE", result.ratio*100)
    if result.sampleLevel == "small" then text = text .. " · " .. NW.L("SMALL_SAMPLE") end
    if showBand ~= false and NW.DB and NW.DB.Get("showBands") == true then
        text = text .. " · " .. NW.L(Rate.BandLabelKey(result.band))
    end
    return text
end
function Rate.CountText(row, field)
    return Rate.FieldUsable(row, field) and tostring(row[field]) or NW.L("VALUE_UNKNOWN")
end
function Rate.Detail(row)
    local r = Rate.Evaluate(row)
    local total = r.rolls and tostring(r.rolls) or NW.L("VALUE_UNKNOWN")
    return NW.L("COUNTS_DETAIL", Rate.CountText(row,"need"), Rate.CountText(row,"greed"), total, Rate.CountText(row,"entries"))
end
local FIELD_KEYS = { need="FIELD_NEED", greed="FIELD_GREED", entries="FIELD_ENTRIES", rolls="FIELD_ROLLS" }
local QUALITY_KEYS = { readable="STATUS_READABLE", unreported="STATUS_UNREPORTED", zero="STATUS_UNREPORTED",
    unknown="STATUS_UNKNOWN", restricted="STATUS_RESTRICTED", format="STATUS_FORMAT", skipped="STATUS_SKIPPED",
    api="STATUS_API", error="STATUS_ERROR", missing="STATUS_UNREPORTED" }
function Rate.FieldLabel(field) return NW.L(FIELD_KEYS[field] or tostring(field)) end
function Rate.QualityLabel(q) return NW.L(QUALITY_KEYS[q] or tostring(q)) end
function Rate.SelfTest()
    local live = NW.RULE
    NW.RULE = NW.BASE_RULE
    local cases = {
        {45,5,10,"ok","red"}, {40,6,11,"ok","red"}, {100,0,500,"ok","red"},
        {1,0,0,"ok","red"}, {0,1,0,"ok","darkgreen"}, {0,0,10,"empty"},
        {14,86,10,"ok","darkgreen"}, {15,85,10,"ok","green"},
        {35,65,10,"ok","yellow"}, {55,45,10,"ok","red"},
        {10,10,10,"ok","yellow"}, {nil,10,10,"unknown"},
        {10,10,nil,"ok","yellow"}, {-1,10,10,"unknown"},
    }
    local results = {}
    local ok, err = pcall(function()
        for i, c in ipairs(cases) do
            local got = Rate.Evaluate(c[1],c[2],c[3])
            results[#results+1] = { index=i, label="share-v1 #"..i,
                ok=got.status==c[4] and got.band==c[5],
                expected={status=c[4],band=c[5]}, got=got }
        end
    end)
    NW.RULE = live
    if not ok then
        results[#results+1] = { index=#results+1, label=tostring(err), ok=false, expected={}, got={} }
    end
    return results
end
