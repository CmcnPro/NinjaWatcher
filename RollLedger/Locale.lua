-- Shared i18n service. Locale files only register dictionaries; no UI writes.
-- Selection is resolved after SavedVariables load, before constructing frames.
local ADDON, RL = ...
local I18n = { dictionaries={}, active="enUS" }
RL.I18n = I18n
local function safeString(value)
    if type(value) ~= "string" then return nil end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue,value)
        if not ok or secret then return nil end
    end
    return value
end
local function preference(value)
    value = safeString(value)
    if not value then return nil end
    local key = value:lower():match("^%s*(.-)%s*$")
    return ({ auto="auto", zhcn="zhCN", enus="enUS" })[key]
end
function I18n.Register(locale,strings)
    I18n.dictionaries[locale] = strings
end
local function clientLanguage()
    if type(GetLocale) == "function" then
        local ok, locale = pcall(GetLocale)
        if ok and safeString(locale) == "zhCN" then return "zhCN" end
    end
    -- enGB and all unsupported client languages use the English dictionary.
    return "enUS"
end
function I18n.Init()
    local selected = preference(RL.DB.Get("language")) or "auto"
    RL.DB.Set("language",selected)
    I18n.active = selected == "auto" and clientLanguage() or selected
    RL.strings = I18n.dictionaries[I18n.active] or I18n.dictionaries.enUS or {}
end
function I18n.Current() return I18n.active end
function I18n.Preference() return preference(RL.DB.Get("language")) or "auto" end
function I18n.Name(locale)
    return ({ auto=RL.L("LANGUAGE_AUTO"), zhCN="简体中文", enUS="English" })[locale] or "English"
end
function I18n.Set(value)
    local selected = preference(value)
    if not selected then return false end
    -- Persist now, apply on /reload so static frames and dynamic messages
    -- never end up in different languages in the same UI session.
    RL.DB.Set("language",selected)
    return true
end
function I18n.Next()
    local order={"auto","zhCN","enUS"}
    local current=I18n.Preference()
    for i,v in ipairs(order) do
        if v==current then I18n.Set(order[i % #order+1]) return I18n.Preference() end
    end
end
function RL.L(key,...)
    local english = I18n.dictionaries.enUS or {}
    local current = I18n.dictionaries[I18n.active] or english
    local text = current[key] or english[key] or key
    if select("#",...) > 0 then
        local ok, formatted = pcall(string.format,text,...)
        if ok then return formatted end
        -- A broken translation must not break a UI callback. Try the base
        -- dictionary before returning an unformatted diagnostic string.
        if english[key] and english[key] ~= text then
            ok, formatted = pcall(string.format,english[key],...)
            if ok then return formatted end
        end
    end
    return text
end
