-- NinjaWatcher maintained baseline. No dungeon-based exemption or pass estimate.
local ADDON, NW = ...
NW.NAME = ADDON
NW.VERSION = "0.3.1"
NW.RULE_VERSION = "share-v1"
NW.BETA = false
NW.STAT = { need = 1044, greed = 1043, dungeons = 932 }
-- Optional descriptive bands, NOT validated behavioural/risk thresholds.
NW.BASE_RULE = {
    darkGreenBelow = 0.15, greenBelow = 0.35, yellowBelow = 0.55,
    sampleBelowRolls = 20, alertMinRolls = 30,
}
NW.RULE = {}
for k, v in pairs(NW.BASE_RULE) do NW.RULE[k] = v end
NW.SCAN = { debounce = 0.30, floor = 1.5, hoverTimeout = 2.5, manualTimeout = 15, farTTL = 3 }
NW.COLORS = {
    darkgreen = { 0.10, 0.72, 0.24 }, green = { 0.25, 0.95, 0.35 },
    yellow = { 1, 0.82, 0 }, red = { 1, 0.25, 0.25 },
    gray = { 0.62, 0.62, 0.62 }, white = { 1, 1, 1 }, pink = { 245/255, 140/255, 186/255 },
}
NW.DEFAULTS = {
    tooltip = true, selfTooltip = true,
    showBands = false, localAlert = false, partyAlert = false,
    cacheMinutes = 10, redCooldown = 300,
    shareTarget = "self", iconMode = "minimap", iconAngle = 45,
    tier1 = 15, tier2 = 35, tier3 = 55,
    badgeMode = "auto", badgeShowUnknown = false,
    chatTagMode = "off", chatTagUnknown = false, chatTagRefresh = false,
}
function NW.L(key, ...)
    local text = (NW.strings and NW.strings[key]) or key
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, text, ...)
        if ok then return formatted end
    end
    return text
end
