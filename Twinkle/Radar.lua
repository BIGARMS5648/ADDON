local ADDON, ns = ...
local L, Data, Sparkle = ns.L, ns.Data, ns.Sparkle

-- Herbs and ore that are in range but not in front of you.
--
-- The game's interact targeting only looks at what is on screen, so a herb
-- behind you never gets a nameplate. ClosestGameObjectPosition(objectID)
-- still knows where the nearest node of each kind is, so we look up every
-- herb / ore object ID and draw a sparkle at the edge of the screen in the
-- node's direction: behind you = below your character, left = left, etc.

local SCAN_INTERVAL = 0.5 -- seconds between node lookups
local UPDATE_INTERVAL = 0.03 -- seconds between marker moves
local FRONT_CONE = math.rad(45) -- nodes this close to straight ahead are left to the nameplate sparkle
local MAX_MARKERS = 3
local MATCH_TOLERANCE = 3 -- yards; for working out the coordinate order

local abs, sin, cos, sqrt, floor, pi = math.abs, math.sin, math.cos, math.sqrt, math.floor, math.pi
local atan2 = math.atan2
local TWO_PI = pi * 2

local Radar = {}
ns.Radar = Radar

local nodes = {} -- last scan: { id, category, name, x, y }
local markers = {} -- sparkle frames in use
local status = { secret = false, missingAPI = false, swapped = nil, lastCount = 0 }
Radar.status = status

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

local function PlayerPosition()
    local ok, x, y = pcall(UnitPosition, "player")
    if not ok or IsSecret(x) or IsSecret(y) or x == nil or y == nil then
        return nil
    end
    return x, y
end

local function PlayerFacing()
    local facing = GetPlayerFacing and GetPlayerFacing()
    if IsSecret(facing) or facing == nil then
        return nil
    end
    return facing
end

local function Active()
    local db = ns.db
    return db and db.enabled and db.radar
end

-- Every object ID we know to be a herb or ore node, with a display name if known.
local function ForEachNodeID(fn)
    local db = ns.db
    for id, category in pairs(Data.NODE_IDS) do
        local known = db.nodes[id]
        fn(id, category, known and known.name)
    end
    for id, known in pairs(db.nodes) do
        if not Data.NODE_IDS[id] then
            fn(id, known.category, known.name)
        end
    end
end

-- Remember IDs of herb / ore objects we identified, so the radar also finds
-- nodes that aren't in the built-in list, and can show their names.
function ns:RememberNode(id, category, name)
    if not id or (category ~= "HERB" and category ~= "ORE") then
        return
    end
    local known = self.db.nodes[id]
    if not known or known.category ~= category or (name and known.name ~= name) then
        self.db.nodes[id] = { category = category, name = name or (known and known.name) }
    end
end

function Radar:Scan()
    wipe(nodes)
    if not ClosestGameObjectPosition then
        status.missingAPI = true
        return
    end
    local px, py = PlayerPosition()
    if not px then
        return
    end
    local db = ns.db
    ForEachNodeID(function(id, category, name)
        if not db.show[category] then
            return
        end
        local ok, x, y, distance = pcall(ClosestGameObjectPosition, id)
        if not ok then
            return
        end
        -- check for secret values before comparing anything
        if IsSecret(x) or IsSecret(y) or IsSecret(distance) then
            status.secret = true
            return
        end
        if x == nil or y == nil or distance == nil or distance > db.range + 10 then
            return
        end
        -- The API names its results x, y like UnitPosition does; check that
        -- the order really matches by comparing against the reported distance.
        if status.swapped == nil and distance > 1 then
            local direct = sqrt((x - px) ^ 2 + (y - py) ^ 2)
            local swapped = sqrt((y - px) ^ 2 + (x - py) ^ 2)
            if abs(direct - distance) <= MATCH_TOLERANCE and abs(swapped - distance) > MATCH_TOLERANCE then
                status.swapped = false
            elseif abs(swapped - distance) <= MATCH_TOLERANCE and abs(direct - distance) > MATCH_TOLERANCE then
                status.swapped = true
            end
        end
        if status.swapped then
            x, y = y, x
        end
        nodes[#nodes + 1] = { id = id, category = category, name = name, x = x, y = y }
    end)
    status.lastCount = #nodes
end

local function HideMarkers(from)
    for i = #markers, from, -1 do
        Sparkle.Release(markers[i])
        markers[i] = nil
    end
end

-- Moves the markers to follow the player's position and facing.
function Radar:Update()
    local px, py = PlayerPosition()
    local facing = PlayerFacing()
    local db = ns.db
    if not px or not facing or not Active() then
        HideMarkers(1)
        return
    end

    -- distance and direction relative to where the character faces
    -- (world x points north, y points west; facing is radians counterclockwise from north)
    local visible = {}
    for _, node in ipairs(nodes) do
        local dx, dy = node.x - px, node.y - py
        local distance = sqrt(dx * dx + dy * dy)
        if distance <= db.range then
            local relative = (atan2(dy, dx) - facing) % TWO_PI
            if relative > pi then
                relative = relative - TWO_PI
            end
            if abs(relative) > FRONT_CONE then
                visible[#visible + 1] = { node = node, distance = distance, relative = relative }
            end
        end
    end
    table.sort(visible, function(a, b) return a.distance < b.distance end)

    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local rx, ry = width * 0.22, height * 0.30
    local centerY = -height * 0.05
    local size = floor(db.size * 0.7 + 0.5)
    local count = math.min(#visible, MAX_MARKERS)
    for i = 1, count do
        local entry = visible[i]
        local fx = markers[i]
        if not fx then
            fx = Sparkle.Acquire()
            fx.isRadar = true
            markers[i] = fx
        end
        local node = entry.node
        local label = (node.name or L["CAT_" .. node.category]) .. " " .. L.DISTANCE:format(floor(entry.distance + 0.5))
        local x = -sin(entry.relative) * rx
        local y = cos(entry.relative) * ry + centerY
        fx:Play(UIParent, node.category, label, size, x, y)
    end
    HideMarkers(count + 1)
end

-- driver ------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local sinceScan, sinceUpdate = SCAN_INTERVAL, 0

driver:SetScript("OnUpdate", function(_, elapsed)
    if not Active() then
        if #markers > 0 then
            HideMarkers(1)
        end
        return
    end
    sinceScan = sinceScan + elapsed
    sinceUpdate = sinceUpdate + elapsed
    if sinceScan >= SCAN_INTERVAL then
        sinceScan = 0
        Radar:Scan()
    end
    if sinceUpdate >= UPDATE_INTERVAL then
        sinceUpdate = 0
        Radar:Update()
    end
end)

-- Forces a fresh scan on the next frame (after settings change).
function Radar:Refresh()
    sinceScan = SCAN_INTERVAL
    sinceUpdate = UPDATE_INTERVAL
    if not Active() then
        HideMarkers(1)
    end
end

function Radar:MarkerCount()
    return #markers
end

function Radar:DebugReport()
    local px, py = PlayerPosition()
    ns.Print(("  radar: %s, nodes in range %d, markers %d, position %s, facing %s"):format(
        Active() and "on" or "off", status.lastCount, #markers,
        px and ("%.1f, %.1f"):format(px, py) or "n/a",
        PlayerFacing() and ("%.2f"):format(PlayerFacing()) or "n/a"))
    if status.missingAPI then
        ns.Print("  radar: ClosestGameObjectPosition is not available")
    end
    if status.secret then
        ns.Print("  radar: node positions are hidden by the game here")
    end
    if status.swapped ~= nil then
        ns.Print("  radar: coordinate order " .. (status.swapped and "swapped" or "normal"))
    end
end
