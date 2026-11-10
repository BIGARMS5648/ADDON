local ADDON, ns = ...
local L, Sparkle = ns.L, ns.Sparkle

-- Keeps objects sparkling after you turn away from them.
--
-- The game only gives a nameplate (and so a sparkle) to the object in front
-- of you, and it hides the positions of other objects from addons. So while
-- an object is sparkling we remember where it was: the direction from the
-- character's facing plus its spot on screen, and once you have seen it from
-- two places, its position on the ground. When it leaves the screen, a
-- sparkle sits at the screen edge in its direction (behind you = below your
-- character) until you turn back, gather it, or walk away.

local SAMPLE_INTERVAL = 0.1 -- seconds between samples / marker moves
local VISIBLE_GRACE = 0.4 -- seconds without a nameplate before a marker shows
local FRONT_CONE = math.rad(40) -- in front: the object is on screen, no marker
local MAX_MARKERS = 3
local MAX_ENTRIES = 8
local FORGET_AFTER = 180 -- seconds since last seen
local MOVE_LIMIT = 10 -- yards; direction-only memories are dropped after moving this far
local MIN_BASELINE = 1.5 -- yards between samples used for triangulation
local MIN_SPREAD = math.rad(6) -- sight lines must differ this much to triangulate
local MAX_TRIANGULATED = 50 -- yards; anything further is treated as a bad fix
local CONSUMED_RESET = 8 -- seconds; a gather that left the object in place

local abs, sin, cos, tan, atan, sqrt, floor, max, pi = math.abs, math.sin, math.cos, math.tan, math.atan, math.sqrt, math.floor, math.max, math.pi
local atan2 = math.atan2
local TWO_PI = pi * 2

local Memory = {}
ns.Memory = Memory

local entries = {} -- [guid] = { guid, category, name, lastSeen, obs = { {x, y, b} }, wx, wy, consumedAt }
local markers = {}

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

local function Wrap(angle)
    angle = angle % TWO_PI
    if angle > pi then
        angle = angle - TWO_PI
    end
    return angle
end

-- world x points north, y points west; facing is radians counterclockwise from north
local function PlayerState()
    local ok, x, y = pcall(UnitPosition, "player")
    if not ok or IsSecret(x) or IsSecret(y) or x == nil or y == nil then
        return nil
    end
    local facing = GetPlayerFacing and GetPlayerFacing()
    if IsSecret(facing) or facing == nil then
        return nil
    end
    return x, y, facing
end

local function Active()
    local db = ns.db
    return db and db.enabled and db.softEnabled and db.radar
end

-- Horizontal angle of a nameplate from the middle of the screen
-- (positive = to the right).
local function ScreenAngle(plate)
    local ok, x = pcall(plate.GetCenter, plate)
    if not ok or IsSecret(x) or x == nil then
        return 0
    end
    local screen = UIParent:GetWidth() * UIParent:GetEffectiveScale()
    if not screen or screen <= 0 then
        return 0
    end
    local offset = (x * plate:GetEffectiveScale()) / screen * 2 - 1
    offset = max(-1, math.min(1, offset))
    local fov = tonumber(C_CVar.GetCVar("cameraFov")) or 90
    return atan(offset * tan(math.rad(fov) / 2))
end

-- Least-squares crossing point of the sight lines, or nil if they are too
-- parallel or the answer makes no sense.
local function Triangulate(obs)
    if #obs < 2 then
        return nil
    end
    local first = obs[1].b
    local lo, hi = 0, 0
    local a11, a12, a22, c1, c2 = 0, 0, 0, 0, 0
    for _, o in ipairs(obs) do
        local diff = Wrap(o.b - first)
        if diff < lo then lo = diff end
        if diff > hi then hi = diff end
        local nx, ny = -sin(o.b), cos(o.b) -- normal of the sight line
        local d = nx * o.x + ny * o.y
        a11, a12, a22 = a11 + nx * nx, a12 + nx * ny, a22 + ny * ny
        c1, c2 = c1 + nx * d, c2 + ny * d
    end
    local det = a11 * a22 - a12 * a12
    if hi - lo < MIN_SPREAD or abs(det) < 1e-6 then
        return nil
    end
    local x = (a22 * c1 - a12 * c2) / det
    local y = (a11 * c2 - a12 * c1) / det
    for _, o in ipairs(obs) do
        local along = (x - o.x) * cos(o.b) + (y - o.y) * sin(o.b)
        if along <= 0 or along > MAX_TRIANGULATED then
            return nil
        end
    end
    return x, y
end

local function Prune()
    local count, oldestKey, oldestTime = 0, nil, math.huge
    for key, e in pairs(entries) do
        count = count + 1
        if e.lastSeen < oldestTime then
            oldestKey, oldestTime = key, e.lastSeen
        end
    end
    if count > MAX_ENTRIES and oldestKey then
        entries[oldestKey] = nil
    end
end

local function Observe(fx, now, px, py, facing)
    local guid = fx.guid
    if not guid or not fx.anchor then
        return
    end
    local e = entries[guid]
    local isNew = not e
    if isNew then
        e = { guid = guid, obs = {} }
        entries[guid] = e
    end
    e.category, e.name, e.lastSeen = fx.category, fx.objectName, now
    if isNew then
        Prune()
    end
    if e.consumedAt and now - e.consumedAt > CONSUMED_RESET then
        e.consumedAt = nil -- still there long after the cast: the gather didn't finish
    end
    local bearing = facing - ScreenAngle(fx.anchor)
    local last = e.obs[#e.obs]
    if last and (px - last.x) ^ 2 + (py - last.y) ^ 2 < MIN_BASELINE ^ 2 then
        last.x, last.y, last.b = px, py, bearing -- same spot: refine the latest sight line
    else
        e.obs[#e.obs + 1] = { x = px, y = py, b = bearing }
        if #e.obs > 10 then
            table.remove(e.obs, 1)
        end
    end
    local wx, wy = Triangulate(e.obs)
    if wx then
        e.wx, e.wy = wx, wy
    end
end

local function HideMarkers(from)
    for i = #markers, from, -1 do
        Sparkle.Release(markers[i])
        markers[i] = nil
    end
end

function Memory:Tick(now)
    if not Active() then
        HideMarkers(1)
        return
    end
    local px, py, facing = PlayerState()
    if not px then
        HideMarkers(1)
        return
    end
    local db = ns.db

    ns:ForEachActive(function(_, fx)
        Observe(fx, now, px, py, facing)
    end)

    local list = {}
    for guid, e in pairs(entries) do
        local rel, distance
        if now - e.lastSeen > FORGET_AFTER or not db.show[e.category] then
            entries[guid] = nil
        elseif now - e.lastSeen > VISIBLE_GRACE and not e.consumedAt then
            if e.wx then
                local dx, dy = e.wx - px, e.wy - py
                distance = sqrt(dx * dx + dy * dy)
                if distance > db.range + 15 then
                    entries[guid] = nil
                else
                    rel = Wrap(atan2(dy, dx) - facing)
                end
            else
                local last = e.obs[#e.obs]
                if (px - last.x) ^ 2 + (py - last.y) ^ 2 > MOVE_LIMIT ^ 2 then
                    entries[guid] = nil
                else
                    rel = Wrap(last.b - facing)
                end
            end
        end
        if rel and abs(rel) > FRONT_CONE then
            list[#list + 1] = { e = e, rel = rel, distance = distance }
        end
    end
    table.sort(list, function(a, b)
        if (a.distance ~= nil) ~= (b.distance ~= nil) then
            return a.distance ~= nil
        end
        if a.distance and a.distance ~= b.distance then
            return a.distance < b.distance
        end
        return a.e.lastSeen > b.e.lastSeen
    end)

    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local rx, ry = width * 0.22, height * 0.30
    local centerY = -height * 0.05
    local size = max(32, floor(db.size * 0.8 + 0.5))
    local count = math.min(#list, MAX_MARKERS)
    for i = 1, count do
        local item = list[i]
        local fx = markers[i]
        if not fx then
            fx = Sparkle.Acquire()
            fx.isRadar = true
            markers[i] = fx
        end
        local e = item.e
        local label = e.name or L["CAT_" .. e.category]
        if item.distance then
            label = label .. " " .. L.DISTANCE:format(floor(item.distance + 0.5))
        end
        fx:Play(UIParent, e.category, label, size, -sin(item.rel) * rx, cos(item.rel) * ry + centerY)
    end
    HideMarkers(count + 1)
end

-- A spell cast at an object (gathering, opening) means it is about to vanish.
function Memory:OnCastAt(name, now)
    for _, e in pairs(entries) do
        if e.name == name and now - e.lastSeen < 3 then
            e.consumedAt = now
        end
    end
end

function Memory:Clear()
    wipe(entries)
    HideMarkers(1)
end

function Memory:Refresh()
    if not Active() then
        HideMarkers(1)
    end
end

function Memory:MarkerCount()
    return #markers
end

function Memory:EntryCount()
    local count = 0
    for _ in pairs(entries) do
        count = count + 1
    end
    return count
end

local driver = CreateFrame("Frame")
local since = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since >= SAMPLE_INTERVAL then
        since = 0
        Memory:Tick(GetTime())
    end
end)

function Memory:DebugReport()
    local px, py, facing = PlayerState()
    local count, located = 0, 0
    for _, e in pairs(entries) do
        count = count + 1
        if e.wx then
            located = located + 1
        end
    end
    ns.Print(("  memory: %s, remembered %d (located %d), markers %d, position %s, facing %s"):format(
        Active() and "on" or "off", count, located, #markers,
        px and ("%.1f, %.1f"):format(px, py) or "n/a",
        facing and ("%.2f"):format(facing) or "n/a"))
end
