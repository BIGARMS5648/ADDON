local ADDON, ns = ...

--------------------------------------------------------------------------
-- Party members' characters, kept for the ceremony
--
-- The game can only show a player's character (DressUpModel:SetUnit) while
-- that player is near you - their appearance isn't sent from farther away.
-- So whenever a group member is nearby and you're out of combat, their
-- character is loaded into a model frame of its own and kept
-- (SetKeepModelOnHide). If they're far away when the ceremony opens, the
-- kept character stands on the podium instead. Someone who was never near
-- you since the last /reload gets their class icon.
--------------------------------------------------------------------------

local Models = {}
ns.Models = Models

local Safe = ns.Safe
local REFRESH_AFTER = 120 -- seconds before a nearby player's character is loaded again
local LOAD_TIME = 3 -- seconds a newly loaded character stays shown (off screen) to finish loading
local MAX_GROUP = 10 -- larger raids aren't kept (memory); nearby players still show
local SCAN_EVERY = 15

local holder -- off-screen parent of the kept characters
local cache = {} -- [GUID] = { model =, time =, loaded =, inUse = }
local free = {} -- model frames from players no longer kept
local lastScan = -math.huge
Models.cache = cache

local function Holder()
    if not holder then
        holder = CreateFrame("Frame", nil, UIParent)
        holder:SetSize(360, 420)
        holder:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -100, 0) -- left of the screen
    end
    return holder
end

local function NewModel()
    local model = table.remove(free)
    if model then
        return model
    end
    model = CreateFrame("DressUpModel", nil, Holder())
    model:SetSize(300, 360)
    model:SetPoint("TOPLEFT")
    if model.SetKeepModelOnHide then
        pcall(model.SetKeepModelOnHide, model, true)
    end
    model:Hide()
    return model
end

local function Visible(unit)
    if not Safe(UnitExists(unit)) then
        return false
    end
    if not UnitIsVisible then
        return true
    end
    local ok, visible = pcall(UnitIsVisible, unit)
    return ok and Safe(visible) and true or false
end

local function Enabled()
    return ns.db and ns.db.enabled ~= false and ns.db.models ~= false
end

-- Group unit tokens (the player first).
function Models.Units()
    local units = { "player" }
    if IsInRaid() then
        for i = 1, 40 do
            units[#units + 1] = "raid" .. i
        end
    else
        for i = 1, 4 do
            units[#units + 1] = "party" .. i
        end
    end
    return units
end

-- The unit token of a player in the report, if they're still in the group.
function Models.FindUnit(p)
    for _, unit in ipairs(Models.Units()) do
        if Safe(UnitExists(unit)) then
            local guid = Safe(UnitGUID(unit))
            if guid and guid == p.key then
                return unit
            end
            local name, realm = UnitName(unit)
            name, realm = Safe(name), Safe(realm)
            if name and (p.name == name or (realm and realm ~= "" and p.name == name .. "-" .. realm)) then
                return unit
            end
        end
    end
    if p.isLocal then
        return "player"
    end
end

-- Drops the oldest kept characters beyond what we keep.
local function Trim()
    local entries = {}
    for guid, entry in pairs(cache) do
        if not entry.inUse then
            entries[#entries + 1] = { guid = guid, time = entry.time }
        end
    end
    local count = 0
    for _ in pairs(cache) do
        count = count + 1
    end
    table.sort(entries, function(a, b) return a.time < b.time end)
    local i = 1
    while count > MAX_GROUP and entries[i] do
        local entry = cache[entries[i].guid]
        cache[entries[i].guid] = nil
        if entry.model.ClearModel then
            pcall(entry.model.ClearModel, entry.model)
        end
        entry.model:Hide()
        free[#free + 1] = entry.model
        count, i = count - 1, i + 1
    end
end

-- Loads (or refreshes) a group member's character while they're nearby.
-- force: load again even if it was loaded a moment ago.
function Models:Store(unit, force)
    if not Enabled() then
        return nil
    end
    local guid = Safe(UnitGUID(unit))
    if not guid then
        return nil
    end
    local entry = cache[guid]
    if entry and (entry.inUse or (not force and entry.loaded and GetTime() - entry.time < REFRESH_AFTER)) then
        return entry
    end
    if not Visible(unit) then
        return entry -- too far: keep what we have
    end
    local model = entry and entry.model or NewModel()
    model:Show() -- (off screen) so the game finishes loading it
    local ok, success = pcall(model.SetUnit, model, unit)
    if not ok or success == false then
        if not (entry and entry.loaded) then
            model:Hide()
            if not entry then
                free[#free + 1] = model
            end
        end
        return entry
    end
    entry = entry or { model = model }
    entry.loaded, entry.time, entry.unit = true, GetTime(), unit
    cache[guid] = entry
    C_Timer.After(LOAD_TIME, function()
        if not entry.inUse then
            model:Hide()
        end
    end)
    Trim()
    return entry
end

-- Keeps every nearby group member's character (skipped in combat and in
-- big raids).
function Models:Scan(force)
    if not Enabled() or ns.InCombat() then
        return
    end
    if not force and GetTime() - lastScan < 5 then
        return
    end
    lastScan = GetTime()
    if IsInRaid() and (GetNumGroupMembers and GetNumGroupMembers() or 0) > MAX_GROUP then
        return
    end
    for i, unit in ipairs(Models.Units()) do
        if i > 1 and Safe(UnitExists(unit)) then
            self:Store(unit)
        end
    end
end

local function HasModel(model)
    if not model.GetModelFileID then
        return true
    end
    local ok, fileID = pcall(model.GetModelFileID, model)
    fileID = ok and Safe(fileID)
    return fileID ~= nil and fileID ~= 0
end

-- The character to put on the podium for a player in the report: loaded
-- now if they're nearby, otherwise the one kept from earlier. nil if none.
function Models:Get(p)
    if not Enabled() then
        return nil
    end
    local unit = Models.FindUnit(p)
    local entry
    if unit then
        entry = self:Store(unit, true)
    end
    local guid = unit and Safe(UnitGUID(unit)) or p.key
    entry = entry or (guid and cache[guid])
    if not (entry and entry.loaded) then
        return nil
    end
    -- A kept character must still have its model (checked unless just loaded).
    if entry.time < GetTime() and not HasModel(entry.model) then
        return nil
    end
    return entry
end

-- Forgets every kept character (option turned off, tests).
function Models:Forget()
    for guid, entry in pairs(cache) do
        if not entry.inUse then
            if entry.model.ClearModel then
                pcall(entry.model.ClearModel, entry.model)
            end
            entry.model:Hide()
            free[#free + 1] = entry.model
            cache[guid] = nil
        end
    end
    lastScan = -math.huge
end

-- Back off the podium into the off-screen holder (the character is kept).
function Models:Release(entry)
    if not entry then
        return
    end
    local model = entry.model
    entry.inUse = false
    model.slot = nil
    model:Hide()
    model:SetParent(Holder())
    model:ClearAllPoints()
    model:SetPoint("TOPLEFT")
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        Models:Scan()
    else
        -- give the game a moment to know where everyone is
        local force = event == "PLAYER_ENTERING_WORLD"
        C_Timer.After(2, function()
            Models:Scan(force)
        end)
    end
end)
for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
    pcall(events.RegisterEvent, events, event)
end
-- People walk in and out of range; look again now and then.
if C_Timer.NewTicker then
    C_Timer.NewTicker(SCAN_EVERY, function()
        if IsInGroup() then
            Models:Scan()
        end
    end)
end
