local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Slash commands: /ba, /bigarms, /빅암즈
--------------------------------------------------------------------------

local function FindModule(text)
    if not text or text == "" then
        return nil
    end
    local lower = text:lower()
    for _, module in ipairs(ns.modules) do
        if module.name:lower() == lower or module:GetTitle():lower() == lower then
            return module
        end
    end
    for _, module in ipairs(ns.modules) do
        if module.name:lower():find(lower, 1, true) then
            return module
        end
    end
    return nil
end
ns.FindModule = FindModule

local function ParseValue(text)
    local lower = text:lower()
    if lower == "true" or lower == "on" or lower == "yes" or lower == "1" then
        return true
    elseif lower == "false" or lower == "off" or lower == "no" or lower == "0" then
        return false
    end
    return tonumber(text) or text
end

local function ListModules()
    ns.Print(L.LIST_HEADER)
    for _, group in ipairs(ns.GROUPS) do
        local names = {}
        for _, module in ipairs(ns.modules) do
            if module.group == group then
                local color = module.enabled and "|cff40ff40" or "|cff888888"
                names[#names + 1] = ("%s%s|r"):format(color, module.name)
            end
        end
        if #names > 0 then
            ns.Print(("  |cffffd100%s|r: %s"):format(ns.GroupTitle(group), table.concat(names, ", ")))
        end
    end
end

local function SetValue(args)
    local moduleName, key, value = args:match("^(%S+)%s+(%S+)%s+(.+)$")
    local module = FindModule(moduleName)
    if not module or not key then
        ns.Print(L.SET_USAGE)
        return
    end
    if module.defaults[key] == nil then
        local keys = {}
        for k in pairs(module.defaults) do
            keys[#keys + 1] = k
        end
        table.sort(keys)
        ns.Print(L.SET_KEYS:format(module.name, table.concat(keys, ", ")))
        return
    end
    local parsed = ParseValue(ns.Trim(value))
    if type(module.defaults[key]) == "boolean" and type(parsed) ~= "boolean" then
        ns.Print(L.SET_USAGE)
        return
    end
    if type(module.defaults[key]) == "number" and type(parsed) ~= "number" then
        ns.Print(L.SET_USAGE)
        return
    end
    if type(module.defaults[key]) == "string" then
        parsed = tostring(parsed)
    end
    if key == "enabled" then
        ns:SetModuleEnabled(module.name, parsed)
    else
        module.db[key] = parsed
        module:SettingChanged(key, parsed)
    end
    ns:NotifySetting(module.name, key)
    ns.Print(L.SET_DONE:format(module.name, key, tostring(parsed)))
end

local function Help()
    ns.Print(L.HELP_HEADER)
    for _, line in ipairs(L.HELP_LINES) do
        ns.Print("  " .. line)
    end
end

function ns:HandleSlash(msg)
    msg = ns.Trim(msg)
    local command, args = msg:match("^(%S*)%s*(.*)$")
    command = (command or ""):lower()
    args = args or ""

    if command == "" or command == "options" or command == "config" or command == "설정" then
        self:OpenOptions()
    elseif command == "help" or command == "?" or command == "도움말" then
        Help()
    elseif command == "list" or command == "모듈" then
        ListModules()
    elseif command == "on" or command == "off" or command == "toggle" or command == "켜기" or command == "끄기" then
        local module = FindModule(args)
        if not module then
            ns.Print(L.NO_SUCH_MODULE:format(args))
            return
        end
        local enable
        if command == "on" or command == "켜기" then
            enable = true
        elseif command == "off" or command == "끄기" then
            enable = false
        else
            enable = not module.db.enabled
        end
        ns:SetModuleEnabled(module.name, enable)
        ns:NotifySetting(module.name, "enabled")
        ns.Print((enable and L.MODULE_ON or L.MODULE_OFF):format(module:GetTitle()))
    elseif command == "set" then
        SetValue(args)
    elseif command == "reset" or command == "초기화" then
        if StaticPopup_Show then
            StaticPopup_Show("BIGARMS_RESET")
        else
            ns:ResetSettings()
        end
    elseif command == "junk" or command == "잡템" then
        local module = ns:GetModule("AutoSellJunk")
        if module then
            module:HandleCommand(args)
        end
    elseif command == "quest" or command == "퀘스트" then
        local module = ns:GetModule("AutoQuest")
        if module then
            module:HandleCommand(args)
        end
    elseif command == "way" or command == "좌표" then
        local module = ns:GetModule("Waypoint")
        if module then
            if not module.enabled then
                ns:SetModuleEnabled("Waypoint", true)
            end
            module:HandleCommand(args)
        end
    elseif command == "gold" or command == "골드" then
        local module = ns:GetModule("Gold")
        if module then
            module:Report()
        end
    elseif command == "xp" or command == "경험치" then
        local module = ns:GetModule("XP")
        if module then
            module:Report()
        end
    elseif command == "copy" or command == "복사" then
        ns.ShowChatCopy()
    elseif command == "dura" or command == "내구도" then
        local lowest, average = ns.GetDurability()
        if lowest then
            ns.Print(L.DUR_REPORT:format(lowest, average))
        else
            ns.Print(L.DUR_UNKNOWN)
        end
    elseif command == "frames" or command == "창" then
        local module = ns:GetModule("Movers")
        if module and args:lower() == "reset" then
            module:ResetAll()
        else
            ns.Print(L.FRAMES_USAGE)
        end
    elseif command == "minimap" or command == "미니맵" then
        ns.db.minimap.hide = not ns.db.minimap.hide
        if ns.MinimapButton and ns.MinimapButton.Refresh then
            ns.MinimapButton:Refresh()
        end
        ns.Print(ns.db.minimap.hide and L.MINIMAP_HIDDEN or L.MINIMAP_SHOWN)
    elseif command == "debug" then
        ns.db.debug = not ns.db.debug
        ns.Print(ns.db.debug and L.DEBUG_ON or L.DEBUG_OFF)
    elseif command == "pull" or command == "풀" then
        local module = ns:GetModule("PullTimer")
        if module and module.enabled then
            module:Start(ns.Trim(args) ~= "" and tonumber(args) or nil)
        end
    elseif command == "errors" or command == "오류" then
        local module = ns:GetModule("ErrorCatcher")
        if module then
            module:HandleCommand(args)
        end
    elseif command == "alts" or command == "chars" or command == "캐릭" then
        local module = ns:GetModule("Gold")
        if module then
            module:ReportCharacters()
        end
    elseif command == "session" or command == "세션" then
        local module = ns:GetModule("Gold")
        if module then
            module:ReportSession()
        end
    elseif command == "volume" or command == "vol" or command == "볼륨" then
        local module = ns:GetModule("System")
        if module then
            module:HandleVolume(args)
        end
    elseif command == "cvar" then
        local module = ns:GetModule("System")
        if module then
            module:HandleCVar(args)
        end
    elseif command == "home" or command == "집" then
        ns.Print(L.HOME_LINE:format(GetBindLocation and GetBindLocation() or "?"))
    elseif command == "ah" or command == "경매" then
        local module = ns:GetModule("AuctionPrices")
        if module then
            module:HandleCommand(args)
        end
    elseif command == "buffs" or command == "버프" then
        local module = ns:GetModule("BuffReminder")
        if module then
            module:HandleCommand(args)
        end
    elseif command == "nodes" or command == "채집" then
        local module = ns:GetModule("Gathering")
        if module then
            if args:lower() == "clear" then
                module:Clear()
            else
                ns.Print(L.NODES_COUNT:format(#ns.db.nodes))
            end
        end
    elseif command == "rl" or command == "reload" then
        local ok = pcall(ReloadUI)
        if not ok then
            ns.Print(L.RELOAD_BLOCKED)
        end
    elseif command == "version" or command == "버전" then
        ns.Print(("BIGARMS %s"):format(ns.VERSION))
    else
        ns.Print(L.UNKNOWN_COMMAND:format(command))
        Help()
    end
end

SLASH_BIGARMS1 = "/ba"
SLASH_BIGARMS2 = "/bigarms"
SLASH_BIGARMS3 = "/빅암즈"
SlashCmdList["BIGARMS"] = function(msg)
    ns:HandleSlash(msg)
end

-- Short reload and clear-chat commands, only if nothing else owns them.
if not SlashCmdList["RELOADUI"] and not SlashCmdList["BIGARMS_RL"] then
    SLASH_BIGARMS_RL1 = "/rl"
    SlashCmdList["BIGARMS_RL"] = function()
        local ok = pcall(ReloadUI)
        if not ok then
            ns.Print(L.RELOAD_BLOCKED)
        end
    end
end
if not SlashCmdList["BIGARMS_CLEAR"] then
    SLASH_BIGARMS_CLEAR1 = "/clear"
    SlashCmdList["BIGARMS_CLEAR"] = function()
        for _, frame in ipairs(ns.ChatFrames()) do
            if frame.Clear then
                frame:Clear()
            end
        end
    end
end
