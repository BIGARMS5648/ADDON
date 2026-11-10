-- Behavior tests for Twinkle against tests/wow_mock.lua.
-- Run with: python3 tests/run_tests.py

local mock = _G.mock
local ns = _G.ns
local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(msg or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function guid(id, spawn)
    return ("GameObject-0-4170-0-12-%d-%010X"):format(id, spawn or 1)
end

local function herb(name, spawn)
    return { name = name, guid = guid(1617, spawn), gameObject = true, cursor = 131018 }
end

local function countActive()
    local n = 0
    for _, f in ipairs(mock.frames) do
        if f.scripts.OnUpdate and f.shown and f.anchor and f.anchor ~= UIParent and not f.isRadar then
            n = n + 1
        end
    end
    return n
end

local function fxOn(plate)
    for _, f in ipairs(mock.frames) do
        if f.scripts.OnUpdate and f.shown and f.anchor == plate then
            return f
        end
    end
end

local function hud()
    for _, f in ipairs(mock.frames) do
        if f.scripts.OnUpdate and f.shown and f.anchor == UIParent and not f.isRadar then
            return f
        end
    end
end

local function lastPrint()
    return mock.printed[#mock.printed] or ""
end

-- boot ------------------------------------------------------------------------

test("loads and applies CVars on login", function()
    mock.fire("ADDON_LOADED", "Twinkle")
    mock.fire("PLAYER_LOGIN")
    mock.fire("PLAYER_ENTERING_WORLD", true, false)
    mock.flushTimers()
    local db = TwinkleDB
    assert(db and db.enabled, "db created")
    eq(mock.cvars.SoftTargetInteract, "3", "SoftTargetInteract")
    eq(mock.cvars.SoftTargetNameplateInteract, "1", "SoftTargetNameplateInteract")
    eq(tonumber(mock.cvars.SoftTargetInteractRange), 20, "range")
    eq(mock.cvars.SoftTargetInteractArc, "2", "arc")
    eq(mock.cvars.SoftTargetIconGameObject, "0", "no object icons")
    eq(mock.cvars.SoftTargetIconInteract, "0", "no NPC icons")
    eq(mock.cvars.interactKeyWarningTutorial, "1", "no 'interact key not bound' warning")
    eq(mock.cvars.softTargetInteractionTutorialTotalInteractions, "2", "no interact help tips")
    eq(db.size, 40, "default size")
    eq(db.offsetY, -30, "default vertical position")
    eq(db.dbVersion, 2, "settings version")
    eq(mock.cvars.Outline, "0", "Outline")
    eq(mock.cvars.outlineModeShowLootEffectWhenDisabled, "1", "loot sparkle")
    eq(db.savedCVars.SoftTargetInteract, "1", "original saved")
    eq(db.savedCVars.SoftTargetInteractRange, "10.000000", "original range saved")
    assert(mock.registeredCategory, "settings category registered")
    assert(lastPrint():find("Twinkle"), "welcome message")
end)

test("applying twice writes nothing new", function()
    local before = mock.cvarWrites
    ns:ApplyCVars()
    eq(mock.cvarWrites, before, "cvar writes")
end)

-- classification -------------------------------------------------------------

test("herb via cursor gets a green sparkle on its nameplate", function()
    local plate = mock.addPlate("nameplate1", herb("은엽수"))
    local fx = fxOn(plate)
    assert(fx, "sparkle attached")
    eq(fx.category, "HERB", "category")
    eq(fx:GetParent(), plate, "parented to nameplate")
    eq(fx.ignoreParentAlpha, true, "ignores parent alpha")
end)

test("nameplate removal releases the sparkle", function()
    local plate = mock.units.nameplate1.plate
    mock.removePlate("nameplate1")
    eq(fxOn(plate), nil, "released")
    eq(countActive(), 0, "no active sparkles")
end)

test("ore by object id when no cursor is available", function()
    local plate = mock.addPlate("nameplate2", { name = "Copper Vein", guid = guid(1731), gameObject = true, cursor = false })
    eq(fxOn(plate).category, "ORE", "category")
    mock.removePlate("nameplate2")
end)

test("quest object via quest cursor", function()
    local plate = mock.addPlate("nameplate3", { name = "보급품 상자", guid = guid(999001), gameObject = true, cursor = 1006596 })
    eq(fxOn(plate).category, "QUEST", "category")
    mock.removePlate("nameplate3")
end)

test("quest object via quest objective name", function()
    mock.quests = {
        { info = { questID = 1, isHeader = false },
          objectives = { { text = "Bundle of Wood: 3/8", finished = false } } },
        { info = { questID = 2, isHeader = false },
          objectives = { { text = "늑대 가죽: 0/5", finished = false } } },
    }
    mock.fire("QUEST_LOG_UPDATE")
    mock.flushTimers()
    -- generic "interact" cursor (gear) that maps to nothing specific
    local plate = mock.addPlate("nameplate4", { name = "Bundle of Wood", guid = guid(999002), gameObject = true, cursor = 131021 })
    eq(fxOn(plate).category, "QUEST", "category")
    mock.removePlate("nameplate4")
end)

test("finished objectives don't match", function()
    mock.quests[1].objectives[1].finished = true
    mock.fire("QUEST_LOG_UPDATE")
    mock.flushTimers()
    local plate = mock.addPlate("nameplate4", { name = "Bundle of Wood", guid = guid(999002), gameObject = true, cursor = 131021 })
    eq(fxOn(plate), nil, "no sparkle for OTHER")
    mock.removePlate("nameplate4")
end)

test("other objects are ignored by default", function()
    local plate = mock.addPlate("nameplate5", { name = "Mailbox", guid = guid(999003), gameObject = true, cursor = 131024 })
    eq(fxOn(plate), nil, "no sparkle")
    assert(ns.unknownCursors["131024"], "unknown cursor remembered for debug")
    mock.removePlate("nameplate5")
end)

test("NPC nameplates are ignored", function()
    local plate = mock.addPlate("nameplate6", { name = "Wolf", guid = "Creature-0-1-0-12-299-01", gameObject = false, cursor = 131013 })
    eq(fxOn(plate), nil, "no sparkle")
    mock.removePlate("nameplate6")
end)

test("treasure chests use the loot category", function()
    local plate = mock.addPlate("nameplate7", { name = "Battered Chest", guid = guid(2843), gameObject = true, cursor = 131023 })
    eq(fxOn(plate).category, "LOOT", "category")
    mock.removePlate("nameplate7")
end)

-- learning, watch list --------------------------------------------------------

test("gathering casts teach node names", function()
    mock.fire("UNIT_SPELLCAST_SENT", "player", "신비한 버섯", "Cast-1", 2366)
    mock.flushTimers()
    eq(TwinkleDB.learned["신비한 버섯"], "HERB", "learned")
    local plate = mock.addPlate("nameplate8", { name = "신비한 버섯", guid = guid(999004), gameObject = true, cursor = false })
    eq(fxOn(plate).category, "HERB", "category")
    mock.removePlate("nameplate8")
end)

test("gathering casts by localized spell name", function()
    mock.fire("UNIT_SPELLCAST_SENT", "player", "이상한 광석", "Cast-2", 123456)
    eq(TwinkleDB.learned["이상한 광석"], nil, "unknown spell ignored")
    mock.spellNames[123456] = "채광"
    mock.fire("UNIT_SPELLCAST_SENT", "player", "이상한 광석", "Cast-3", 123456)
    eq(TwinkleDB.learned["이상한 광석"], "ORE", "learned via spell name")
end)

test("watch list objects sparkle with an alert sound", function()
    SlashCmdList.TWINKLE("watch add 검은 연꽃")
    eq(TwinkleDB.watch["검은 연꽃"], "검은 연꽃", "stored")
    local sounds = #mock.sounds
    local plate = mock.addPlate("nameplate9", { name = "검은 연꽃", guid = guid(176589), gameObject = true, cursor = 131018 })
    eq(fxOn(plate).category, "WATCH", "category")
    eq(#mock.sounds, sounds + 1, "sound played")
    eq(mock.sounds[#mock.sounds], SOUNDKIT.RAID_WARNING, "alert sound")
    -- same object again shortly after: no repeated sound
    mock.removePlate("nameplate9")
    mock.addPlate("nameplate9", { name = "검은 연꽃", guid = guid(176589), gameObject = true, cursor = 131018 })
    eq(#mock.sounds, sounds + 1, "throttled")
    mock.removePlate("nameplate9")
    SlashCmdList.TWINKLE("watch del 검은 연꽃")
    eq(TwinkleDB.watch["검은 연꽃"], nil, "removed")
end)

-- screen alert ------------------------------------------------------------------

test("screen alert when the soft target has no nameplate", function()
    local data = herb("뱀뿌리", 77)
    mock.setSoftInteract(data)
    mock.flushTimers()
    local h = hud()
    assert(h, "hud shown")
    eq(h.category, "HERB", "hud category")
    assert(h.label.text:find("뱀뿌리"), "hud label has the name")
    -- nameplate arrives: hud goes away
    mock.units.nameplate10 = { name = data.name, guid = data.guid, gameObject = true, cursor = data.cursor,
                               plate = CreateFrame("Frame", nil, UIParent) }
    mock.fire("NAME_PLATE_UNIT_ADDED", "nameplate10")
    eq(hud(), nil, "hud hidden once the nameplate exists")
    mock.removePlate("nameplate10")
    mock.setSoftInteract(nil)
    mock.flushTimers()
    eq(hud(), nil, "hud hidden without target")
end)

-- animation -----------------------------------------------------------------------

test("animation runs for many frames without errors", function()
    local plate = mock.addPlate("nameplate11", herb("평온꽃", 5))
    local fx = fxOn(plate)
    local update = fx.scripts.OnUpdate
    for i = 1, 600 do
        update(fx, (i % 7) * 0.01 + 0.001)
    end
    assert(fx.star.rotation ~= nil, "star rotates")
    assert(fx.glow.width > 0, "glow sized")
    mock.removePlate("nameplate11")
end)

test("preview shows three sparkles", function()
    SlashCmdList.TWINKLE("test")
    local n = 0
    for _, f in ipairs(mock.frames) do
        if f.scripts.OnUpdate and f.shown and f.anchor == UIParent and not f.isRadar then n = n + 1 end
    end
    eq(n, 3, "preview sparkles")
    mock.flushTimers()
    n = 0
    for _, f in ipairs(mock.frames) do
        if f.scripts.OnUpdate and f.shown and f.anchor == UIParent and not f.isRadar then n = n + 1 end
    end
    eq(n, 0, "preview hidden after timeout")
end)

-- settings ----------------------------------------------------------------------

test("settings panel toggles categories", function()
    local s = mock.settings.TWINKLE_SHOW_HERB
    assert(s and s.control == "checkbox", "herb checkbox")
    local plate = mock.addPlate("nameplate12", herb("마법초", 9))
    assert(fxOn(plate), "shown before")
    s.set(false)
    eq(fxOn(plate), nil, "hidden after unchecking herbs")
    s.set(true)
    assert(fxOn(plate), "shown again")
    mock.removePlate("nameplate12")
end)

test("settings sliders and dropdowns drive CVars", function()
    mock.settings.TWINKLE_range.set(35)
    eq(mock.cvars.SoftTargetInteractRange, "35", "range cvar")
    mock.settings.TWINKLE_arc.set(1)
    eq(mock.cvars.SoftTargetInteractArc, "1", "arc cvar")
    eq(mock.settings.TWINKLE_range.options.formatter(35), "35", "slider label")
    local styles = mock.settings.TWINKLE_questStyle.choices
    eq(#styles, 3, "quest style choices")
end)

test("outline style sets Outline mode", function()
    mock.settings.TWINKLE_questStyle.set("outline")
    eq(mock.cvars.Outline, "1", "Outline")
    eq(mock.cvars.outlineModeShowLootEffectWhenDisabled, "0", "loot sparkle off")
    mock.settings.TWINKLE_outlineMode.set(3)
    eq(mock.cvars.Outline, "3", "Outline 3")
    mock.settings.TWINKLE_questStyle.set("none")
    eq(mock.cvars.Outline, "0", "Outline restored")
    eq(mock.cvars.outlineModeShowLootEffectWhenDisabled, "0", "loot sparkle restored")
    eq(TwinkleDB.savedCVars.Outline, nil, "no longer managed")
    mock.settings.TWINKLE_questStyle.set("sparkle")
    eq(mock.cvars.outlineModeShowLootEffectWhenDisabled, "1", "loot sparkle on again")
end)

-- enable / disable / combat --------------------------------------------------------

test("/tw off restores every CVar and removes sparkles", function()
    local plate = mock.addPlate("nameplate13", herb("찔레가시", 11))
    assert(fxOn(plate), "sparkle before")
    SlashCmdList.TWINKLE("off")
    eq(mock.cvars.SoftTargetInteract, "1", "SoftTargetInteract restored")
    eq(mock.cvars.SoftTargetNameplateInteract, "0", "nameplate restored")
    eq(tonumber(mock.cvars.SoftTargetInteractRange), 10, "range restored")
    eq(mock.cvars.SoftTargetInteractArc, "0", "arc restored")
    eq(mock.cvars.SoftTargetIconGameObject, "0", "icon restored")
    eq(mock.cvars.SoftTargetIconInteract, "1", "NPC icons restored")
    eq(mock.cvars.outlineModeShowLootEffectWhenDisabled, "0", "loot sparkle restored")
    eq(next(TwinkleDB.savedCVars), nil, "nothing left to restore")
    eq(fxOn(plate), nil, "sparkle removed")
    mock.removePlate("nameplate13")
end)

test("turning on during combat waits for combat to end", function()
    mock.inCombat = true
    SlashCmdList.TWINKLE("on")
    eq(mock.cvars.SoftTargetInteract, "1", "unchanged in combat")
    local found = false
    for _, line in ipairs(mock.printed) do
        if line:find(ns.L.COMBAT_DEFERRED, 1, true) then found = true end
    end
    assert(found, "told the user")
    mock.inCombat = false
    mock.fire("PLAYER_REGEN_ENABLED")
    eq(mock.cvars.SoftTargetInteract, "3", "applied after combat")
end)

-- robustness ---------------------------------------------------------------------

test("secret values from the client don't break anything", function()
    local plate = mock.addPlate("nameplate14", { name = mock.SECRET, guid = mock.SECRET, gameObject = true, cursor = 131025 })
    eq(fxOn(plate).category, "ORE", "still classified from the cursor")
    mock.removePlate("nameplate14")
    local plate2 = mock.addPlate("nameplate15", { name = mock.SECRET, guid = mock.SECRET, gameObject = true, cursor = false })
    eq(fxOn(plate2), nil, "nothing known: no sparkle, no error")
    mock.removePlate("nameplate15")
    mock.fire("UNIT_SPELLCAST_SENT", "player", mock.SECRET, "Cast-9", 2366)
end)

test("guid parsing", function()
    local kind, id = ns.ParseGUID("GameObject-0-4170-0-12-176589-000012ABCD")
    eq(kind, "GameObject", "kind")
    eq(id, 176589, "id")
    kind, id = ns.ParseGUID("Creature-0-4170-0-12-299-000012ABCD")
    eq(kind, "Creature", "creature kind")
    eq(ns.ParseGUID(nil), nil, "nil")
end)

test("debug report and help don't error", function()
    mock.setSoftInteract(herb("황금가시", 42))
    SlashCmdList.TWINKLE("debug")
    SlashCmdList.TWINKLE("debug on")
    eq(TwinkleDB.debug, true, "debug on")
    SlashCmdList.TWINKLE("debug off")
    SlashCmdList.TWINKLE("learned")
    SlashCmdList.TWINKLE("watch list")
    SlashCmdList.TWINKLE("help")
    SlashCmdList.TWINKLE("")
    eq(mock.openedCategory, 42, "options opened")
    mock.setSoftInteract(nil)
    mock.flushTimers()
end)

-- minimap button ---------------------------------------------------------------

local function minimapButton()
    return ns.MinimapButton:GetFrame()
end

test("minimap button is created around the minimap", function()
    local b = minimapButton()
    assert(b and b.shown, "button shown")
    eq(b:GetParent(), Minimap, "parented to the minimap")
    local p = b.points[#b.points]
    eq(p[1], "CENTER", "anchor")
    -- default angle 225 degrees: bottom-left, on a circle of radius 70 + 5
    assert(math.abs(p[4] + 53.03) < 0.1 and math.abs(p[5] + 53.03) < 0.1, "position " .. p[4] .. ", " .. p[5])
    eq(b.icon.texture, "Interface\\AddOns\\Twinkle\\Media\\icon", "icon texture")
end)

test("minimap button clicks", function()
    local b = minimapButton()
    local click = b.scripts.OnClick
    click(b, "RightButton")
    eq(TwinkleDB.enabled, false, "right-click turns off")
    eq(b.icon.desaturated, true, "grey icon when off")
    eq(mock.cvars.SoftTargetInteract, "1", "game settings restored")
    click(b, "RightButton")
    eq(TwinkleDB.enabled, true, "right-click turns on")
    eq(b.icon.desaturated, false, "colored icon when on")
    mock.openedCategory = nil
    click(b, "LeftButton")
    eq(mock.openedCategory, 42, "left-click opens options")
    mock.openedCategory = nil
    mock.inCombat = true
    click(b, "LeftButton")
    eq(mock.openedCategory, nil, "not in combat")
    eq(lastPrint():find(ns.L.OPTIONS_IN_COMBAT, 1, true) ~= nil, true, "explains why")
    mock.inCombat = false
    click(b, "MiddleButton")
    local n = 0
    for _, f in ipairs(mock.frames) do
        if f.scripts.OnUpdate and f.shown and f.anchor == UIParent and not f.isRadar then n = n + 1 end
    end
    eq(n, 3, "middle-click shows the preview")
    mock.flushTimers()
end)

test("minimap button tooltip", function()
    local b = minimapButton()
    b.scripts.OnEnter(b)
    eq(GameTooltip.owner, b, "tooltip owner")
    local text = table.concat(GameTooltip.lines, "\n")
    assert(text:find(ns.L.STATUS_ON, 1, true), "shows status")
    assert(text:find(ns.L.MINIMAP_DRAG, 1, true), "shows drag hint")
    b.scripts.OnLeave(b)
    eq(GameTooltip.shown, false, "hidden on leave")
end)

test("dragging the minimap button moves it", function()
    local b = minimapButton()
    b.scripts.OnDragStart(b)
    -- cursor straight above the minimap center
    mock.cursor = { Minimap.centerX, Minimap.centerY + 100 }
    b.scripts.OnUpdate(b, 0.016)
    b.scripts.OnDragStop(b)
    assert(math.abs(TwinkleDB.minimap.angle - 90) < 0.001, "angle " .. TwinkleDB.minimap.angle)
    local p = b.points[#b.points]
    assert(math.abs(p[4]) < 0.01 and math.abs(p[5] - 75) < 0.01, "moved to the top")
end)

test("/tw minimap hides and shows the button", function()
    SlashCmdList.TWINKLE("minimap")
    eq(minimapButton().shown, false, "hidden")
    eq(TwinkleDB.minimap.hide, true, "saved")
    SlashCmdList.TWINKLE("minimap")
    eq(minimapButton().shown, true, "shown again")
    local setting = mock.settings.TWINKLE_minimap
    setting.set(false)
    eq(minimapButton().shown, false, "options checkbox hides it")
    eq(setting.get(), false, "checkbox reads hidden")
    setting.set(true)
    eq(minimapButton().shown, true, "options checkbox shows it")
end)

test("addon compartment entry", function()
    Twinkle_OnAddonCompartmentClick("Twinkle", "RightButton")
    eq(TwinkleDB.enabled, false, "compartment right-click turns off")
    Twinkle_OnAddonCompartmentClick("Twinkle", "RightButton")
    eq(TwinkleDB.enabled, true, "and on")
    local menuButton = CreateFrame("Frame")
    Twinkle_OnAddonCompartmentEnter("Twinkle", menuButton)
    eq(GameTooltip.owner, menuButton, "tooltip on the menu entry")
    Twinkle_OnAddonCompartmentLeave("Twinkle", menuButton)
    eq(GameTooltip.shown, false, "tooltip hidden")
end)

-- settings from older versions ----------------------------------------------------

test("old default size and position move to the new defaults", function()
    local saved = ns.Migrate({ size = 72, offsetY = -16, blizzIcon = true, nodes = { [1] = {} } })
    eq(saved.size, 40, "size")
    eq(saved.offsetY, -30, "vertical position")
    eq(saved.blizzIcon, false, "icons")
    eq(saved.nodes, nil, "old radar data dropped")
    eq(saved.dbVersion, 2, "version")
end)

test("values the player chose are kept", function()
    local saved = ns.Migrate({ size = 60, offsetY = -50 })
    eq(saved.size, 60, "size")
    eq(saved.offsetY, -50, "vertical position")
    saved = ns.Migrate({ dbVersion = 2, size = 72, offsetY = -16, blizzIcon = true })
    eq(saved.size, 72, "already migrated: untouched")
    eq(saved.blizzIcon, true, "already migrated: untouched")
end)

test("game interact icons can be turned back on", function()
    mock.settings.TWINKLE_blizzIcon.set(true)
    eq(mock.cvars.SoftTargetIconGameObject, "1", "object icons")
    eq(mock.cvars.SoftTargetIconInteract, "1", "NPC icons back to the player's own value")
    mock.settings.TWINKLE_blizzIcon.set(false)
    eq(mock.cvars.SoftTargetIconInteract, "0", "hidden again")
end)

-- keep sparkling after turning away -------------------------------------------------

local SCREEN_W = 1366

-- screen x of an object `angle` radians to the right of the middle of the view
local function screenX(angle)
    return (math.tan(angle) / math.tan(math.rad(45)) + 1) / 2 * SCREEN_W
end

local function edgeMarkers()
    local list = {}
    for _, f in ipairs(mock.frames) do
        if f.isRadar and f.shown then list[#list + 1] = f end
    end
    return list
end

local function tick(dt)
    mock.time = mock.time + (dt or 0.1)
    ns.Memory:Tick(mock.time)
    return edgeMarkers()
end

local function markerPos(m)
    local p = m.points[#m.points]
    return p[4], p[5]
end

local function showHerb(token, name, spawn, x)
    local plate = mock.addPlate(token, { name = name, guid = guid(1617, spawn), gameObject = true, cursor = 131018 })
    plate.centerX = x or SCREEN_W / 2
    return plate
end

local function resetMemory()
    ns.Memory:Clear()
    mock.settings.TWINKLE_range.set(20)
    mock.player = { x = 0, y = 0, facing = 0 }
end

test("a herb keeps sparkling below the character after turning around", function()
    resetMemory()
    showHerb("nameplate30", "은엽수", 30)
    eq(#tick(), 0, "on screen: only the nameplate sparkle")
    mock.removePlate("nameplate30")
    mock.player.facing = math.pi -- turned around
    local list = tick(0.5)
    eq(#list, 1, "edge sparkle")
    eq(list[1].category, "HERB", "herb color")
    local x, y = markerPos(list[1])
    assert(math.abs(x) < 0.01 and y < -200, "below the character: " .. x .. ", " .. y)
    assert(list[1].label.text:find("은엽수", 1, true), "named")
    mock.player.facing = 0 -- turned back
    eq(#tick(), 0, "in front again: no edge sparkle")
end)

test("the herb's place on screen sets its direction", function()
    resetMemory()
    showHerb("nameplate31", "평온꽃", 31, screenX(math.rad(30))) -- 30 degrees right
    tick()
    mock.removePlate("nameplate31")
    mock.player.facing = math.pi / 2 -- turned 90 degrees left
    local x, y = markerPos(tick(0.5)[1])
    assert(x > 0 and y < 0, "behind on the right: " .. x .. ", " .. y)
end)

test("gathered objects don't come back", function()
    resetMemory()
    showHerb("nameplate32", "마법초", 32)
    tick()
    mock.fire("UNIT_SPELLCAST_SENT", "player", "마법초", "Cast-20", 2366)
    mock.removePlate("nameplate32")
    mock.player.facing = math.pi
    eq(#tick(0.5), 0, "no edge sparkle for a gathered herb")
end)

test("walking away forgets a herb seen from one spot", function()
    resetMemory()
    showHerb("nameplate33", "찔레가시", 33)
    tick()
    mock.removePlate("nameplate33")
    mock.player.facing = math.pi
    eq(#tick(0.5), 1, "remembered")
    mock.player.y = 15 -- walked 15 yards west
    eq(#tick(), 0, "forgotten")
end)

test("seeing a herb from two spots gives its distance", function()
    resetMemory()
    -- herb at 10 yards north; look at it from 5 yards east, then 5 yards west
    mock.player = { x = 0, y = -5, facing = 0 }
    local plate = showHerb("nameplate34", "생채기풀", 34, screenX(-math.atan2(5, 10)))
    tick()
    mock.player.y = 5
    plate.centerX = screenX(math.atan2(5, 10))
    tick()
    mock.removePlate("nameplate34")
    -- walk past it: now 10 yards north of the herb, still facing north
    mock.player = { x = 20, y = 0, facing = 0 }
    local list = tick(0.5)
    eq(#list, 1, "edge sparkle")
    local x, y = markerPos(list[1])
    assert(math.abs(x) < 1 and y < -200, "behind: " .. x .. ", " .. y)
    assert(list[1].label.text:find("10", 1, true), "distance: " .. list[1].label.text)
    mock.player.x = 60 -- far away now
    eq(#tick(), 0, "forgotten when out of range")
end)

test("memories expire", function()
    resetMemory()
    showHerb("nameplate35", "황금가시", 35)
    tick()
    mock.removePlate("nameplate35")
    mock.player.facing = math.pi
    eq(#tick(0.5), 1, "remembered")
    eq(#tick(181), 0, "expired")
end)

test("switches: keep-sparkling option and category toggles", function()
    resetMemory()
    showHerb("nameplate36", "왕꽃잎풀", 36)
    tick()
    mock.removePlate("nameplate36")
    mock.player.facing = math.pi
    eq(#tick(0.5), 1, "shown")
    mock.settings.TWINKLE_radar.set(false)
    eq(#edgeMarkers(), 0, "hidden when the option is off")
    eq(#tick(), 0, "stays hidden")
    mock.settings.TWINKLE_radar.set(true)
    eq(#tick(), 1, "back")
    mock.settings.TWINKLE_SHOW_HERB.set(false)
    eq(#tick(), 0, "herbs off")
    mock.settings.TWINKLE_SHOW_HERB.set(true)
    eq(#tick(), 0, "forgotten while herbs were off")
end)

test("hidden nameplate position falls back to straight ahead", function()
    resetMemory()
    showHerb("nameplate37", "무덤이끼", 37, mock.SECRET)
    tick()
    mock.removePlate("nameplate37")
    mock.player.facing = math.pi
    local x, y = markerPos(tick(0.5)[1])
    assert(math.abs(x) < 0.01 and y < -200, "behind")
end)

test("loading screens clear memories", function()
    resetMemory()
    showHerb("nameplate38", "야생 철쭉", 38)
    tick()
    mock.removePlate("nameplate38")
    mock.player.facing = math.pi
    eq(#tick(0.5), 1, "remembered")
    mock.fire("PLAYER_ENTERING_WORLD", false, false)
    mock.flushTimers()
    eq(#tick(), 0, "cleared")
end)

test("only the most recent objects are remembered", function()
    resetMemory()
    for i = 1, 12 do
        showHerb("nameplate40", "은엽수", 100 + i)
        tick()
        mock.removePlate("nameplate40")
    end
    eq(ns.Memory:EntryCount(), 8, "capped")
    mock.player.facing = math.pi
    eq(#tick(0.5), 3, "at most three edge sparkles")
end)

test("debug report includes memory", function()
    SlashCmdList.TWINKLE("debug")
    local found = false
    for _, line in ipairs(mock.printed) do
        if line:find("memory:", 1, true) then found = true end
    end
    assert(found, "memory line printed")
end)

-- run ----------------------------------------------------------------------------

local passed, failed = 0, 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        passed = passed + 1
        io.write("  ok   ", t.name, "\n")
    else
        failed = failed + 1
        io.write("  FAIL ", t.name, "\n       ", tostring(err), "\n")
    end
end
io.write(("\n%d passed, %d failed\n"):format(passed, failed))
return failed
