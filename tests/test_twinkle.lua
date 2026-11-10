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
    eq(mock.cvars.SoftTargetIconGameObject, "1", "icon")
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

-- radar (herbs / ore behind you) -------------------------------------------------

local function radarMarkers()
    local list = {}
    for _, f in ipairs(mock.frames) do
        if f.isRadar and f.shown then list[#list + 1] = f end
    end
    return list
end

local function radar()
    ns.Radar:Scan()
    ns.Radar:Update()
    return radarMarkers()
end

local function marker(m)
    local p = m.points[#m.points]
    return p[4], p[5]
end

test("herb behind you sparkles below the character", function()
    mock.settings.TWINKLE_range.set(20)
    mock.player = { x = 0, y = 0, facing = 0 } -- facing north
    mock.objects = { [1617] = { x = -8, y = 0 } } -- 8 yards south
    local list = radar()
    eq(#list, 1, "one marker")
    eq(list[1].category, "HERB", "herb color")
    local x, y = marker(list[1])
    assert(math.abs(x) < 0.01 and y < -200, "below the character: " .. x .. ", " .. y)
    assert(list[1].label.text:find("8", 1, true), "distance in the label")
end)

test("herb in front is left to the nameplate sparkle", function()
    mock.objects = { [1617] = { x = 8, y = 0 } }
    eq(#radar(), 0, "no marker straight ahead")
end)

test("herb to the left and right", function()
    mock.objects = { [1617] = { x = 0, y = 8 } } -- west = left when facing north
    local x = marker(radar()[1])
    assert(x < -200, "left side: " .. x)
    mock.objects = { [1617] = { x = 0, y = -8 } } -- east = right
    x = marker(radar()[1])
    assert(x > 200, "right side: " .. x)
end)

test("turning around brings a herb from behind to the front", function()
    mock.objects = { [1617] = { x = -8, y = 0 } }
    eq(#radar(), 1, "behind while facing north")
    mock.player.facing = math.pi -- now facing south
    eq(#radar(), 0, "in front after turning around")
    mock.player.facing = 0
end)

test("only nodes inside the detection range", function()
    mock.objects = { [1617] = { x = -25, y = 0 }, [1731] = { x = -10, y = 3 } }
    local list = radar()
    eq(#list, 1, "far herb ignored")
    eq(list[1].category, "ORE", "close ore shown")
end)

test("radar respects category toggles and its own switch", function()
    mock.objects = { [1731] = { x = -10, y = 0 } }
    mock.settings.TWINKLE_SHOW_ORE.set(false)
    eq(#radar(), 0, "ore hidden when ore sparkles are off")
    mock.settings.TWINKLE_SHOW_ORE.set(true)
    eq(#radar(), 1, "back")
    mock.settings.TWINKLE_radar.set(false)
    eq(#radarMarkers(), 0, "markers removed when the radar is turned off")
    eq(#radar(), 0, "nothing while off")
    mock.settings.TWINKLE_radar.set(true)
end)

test("radar copes with swapped coordinate order", function()
    mock.swapObjectXY = true
    ns.Radar.status.swapped = nil
    mock.player = { x = -9120.5, y = 380.25, facing = 0 } -- somewhere in Elwynn
    mock.objects = { [1617] = { x = -9117.5, y = 392.25 } } -- 12 yards west (left), 3 north
    local x = marker(radar()[1])
    eq(ns.Radar.status.swapped, true, "detected")
    assert(x < -200, "still on the left: " .. x)
    mock.swapObjectXY = false
    ns.Radar.status.swapped = nil
    mock.player = { x = 0, y = 0, facing = 0 }
end)

test("radar does nothing with secret positions", function()
    mock.objects = { [1617] = { x = -8, y = 0 } }
    mock.secretPositions = true
    eq(#radar(), 0, "no markers")
    eq(ns.Radar.status.secret, true, "noted for /tw debug")
    mock.secretPositions = false
end)

test("radar learns new node IDs and names from nameplates", function()
    local id = 555123
    mock.addPlate("nameplate20", { name = "신비한 꽃", guid = guid(id), gameObject = true, cursor = 131018 })
    mock.removePlate("nameplate20")
    eq(TwinkleDB.nodes[id].category, "HERB", "remembered")
    mock.objects = { [id] = { x = -6, y = 0 } }
    local list = radar()
    eq(#list, 1, "found by the learned ID")
    assert(list[1].label.text:find("신비한 꽃", 1, true), "uses the learned name")
    -- built-in IDs get names too once seen
    mock.addPlate("nameplate21", { name = "은엽수", guid = guid(1617), gameObject = true, cursor = 131018 })
    mock.removePlate("nameplate21")
    mock.objects = { [1617] = { x = -6, y = 0 } }
    assert(radar()[1].label.text:find("은엽수", 1, true), "named built-in node")
    mock.objects = {}
    eq(#radar(), 0, "cleared")
end)

test("debug report includes the radar", function()
    SlashCmdList.TWINKLE("debug")
    local found = false
    for _, line in ipairs(mock.printed) do
        if line:find("radar:", 1, true) then found = true end
    end
    assert(found, "radar line printed")
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
