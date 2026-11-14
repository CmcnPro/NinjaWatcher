-- RollLedger maintained baseline. No dungeon-based exemption or pass estimate.
local ADDON, RL = ...
RL.NAME = ADDON
RL.VERSION = "0.4.1"
RL.RULE_VERSION = "share-v1"
RL.BETA = false
RL.STAT = { need = 1044, greed = 1043, dungeons = 932 }
-- Optional descriptive bands, NOT validated behavioural/risk thresholds.
RL.BASE_RULE = {
    darkGreenBelow = 0.15, greenBelow = 0.35, yellowBelow = 0.55,
    sampleBelowRolls = 20, alertMinRolls = 30,
}
RL.RULE = {}
for k, v in pairs(RL.BASE_RULE) do RL.RULE[k] = v end
RL.SCAN = { debounce = 0.30, floor = 1.5, hoverTimeout = 2.5, manualTimeout = 15, farTTL = 3 }
RL.COLORS = {
    darkgreen = { 0.10, 0.72, 0.24 }, green = { 0.25, 0.95, 0.35 },
    yellow = { 1, 0.82, 0 }, red = { 1, 0.25, 0.25 },
    gray = { 0.62, 0.62, 0.62 }, white = { 1, 1, 1 }, pink = { 245/255, 140/255, 186/255 },
}
RL.DEFAULTS = {
    language = "auto",
    tooltip = true, selfTooltip = true, tooltipBand = true,
    showBands = false, localAlert = false, partyAlert = false,
    cacheMinutes = 10, redCooldown = 300,
    shareTarget = "self", iconMode = "minimap", iconAngle = 45,
    tier1 = 15, tier2 = 35, tier3 = 55,
    badgeMode = "auto", badgeShowUnknown = false,
    chatTagMode = "off", chatTagUnknown = false, chatTagRefresh = false,
}
