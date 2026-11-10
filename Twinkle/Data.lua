local ADDON, ns = ...

local Data = {}
ns.Data = Data

-- Category of every interact-cursor texture the game can hand back from
-- SetUnitCursorTexture(). The game picks the cursor from the object's lock /
-- interaction type, so this is a language-independent way to tell herbs,
-- ore and quest objects apart. FileDataIDs come from the community listfile
-- (interface/cursor/*.blp).
Data.CURSOR_FILEIDS = {
    -- HERB
    [131018] = "HERB", -- interface/cursor/gatherherbs.blp
    [131045] = "HERB", -- interface/cursor/unablegatherherbs.blp
    [4675631] = "HERB", -- interface/cursor/crosshair/gatherherbs.blp
    [4675683] = "HERB", -- interface/cursor/crosshair/unablegatherherbs.blp
    [7958141] = "HERB", -- interface/cursor/uicursorgather2x.blp
    [7958221] = "HERB", -- interface/cursor/crosshair/uicrosshairgather2x.blp
    -- ORE
    [131025] = "ORE", -- interface/cursor/mine.blp
    [131052] = "ORE", -- interface/cursor/unablemine.blp
    [4675640] = "ORE", -- interface/cursor/crosshair/mine.blp
    [4675692] = "ORE", -- interface/cursor/crosshair/unablemine.blp
    [7958147] = "ORE", -- interface/cursor/uicursormine2x.blp
    [7958227] = "ORE", -- interface/cursor/crosshair/uicrosshairmine2x.blp
    -- QUEST
    [131030] = "QUEST", -- interface/cursor/quest.blp
    [131031] = "QUEST", -- interface/cursor/questrepeatable.blp
    [131032] = "QUEST", -- interface/cursor/questturnin.blp
    [131057] = "QUEST", -- interface/cursor/unablequest.blp
    [131058] = "QUEST", -- interface/cursor/unablequestrepeatable.blp
    [131059] = "QUEST", -- interface/cursor/unablequestturnin.blp
    [1006596] = "QUEST", -- interface/cursor/questinteract.blp
    [1006597] = "QUEST", -- interface/cursor/unablequestinteract.blp
    [4624272] = "QUEST", -- interface/cursor/uicampaignquestcursor2x.blp
    [4675649] = "QUEST", -- interface/cursor/crosshair/quest.blp
    [4675650] = "QUEST", -- interface/cursor/crosshair/questinteract.blp
    [4675651] = "QUEST", -- interface/cursor/crosshair/questrepeatable.blp
    [4675652] = "QUEST", -- interface/cursor/crosshair/questturnin.blp
    [4675701] = "QUEST", -- interface/cursor/crosshair/unablequest.blp
    [4675702] = "QUEST", -- interface/cursor/crosshair/unablequestinteract.blp
    [4675703] = "QUEST", -- interface/cursor/crosshair/unablequestrepeatable.blp
    [4675704] = "QUEST", -- interface/cursor/crosshair/unablequestturnin.blp
    [5148916] = "QUEST", -- interface/cursor/uilegendaryquestcursor2x.blp
    [5196721] = "QUEST", -- interface/cursor/uiquestinteractcursor2x.blp
    [5201666] = "QUEST", -- interface/cursor/uiimportantquestcursor2x.blp
    [5376505] = "QUEST", -- interface/cursor/uiwrapperquestcursor2x.blp
    [5376508] = "QUEST", -- interface/cursor/uirepeatablequestcursor2x.blp
    [6009167] = "QUEST", -- interface/cursor/uiquestcursor2x.blp
    [6074836] = "QUEST", -- interface/cursor/crosshair/uiwrapperquestcrosshair2x.blp
    [6074839] = "QUEST", -- interface/cursor/crosshair/uirecurringquestcrosshair2x.blp
    [6074842] = "QUEST", -- interface/cursor/crosshair/uiquestcrosshair2x.blp
    [6074857] = "QUEST", -- interface/cursor/crosshair/uilegendaryquestcrosshair2x.blp
    [6074860] = "QUEST", -- interface/cursor/crosshair/uiimportantquestcrosshair2x.blp
    [6074863] = "QUEST", -- interface/cursor/crosshair/uicampaignquestcrosshair2x.blp
    [6075065] = "QUEST", -- interface/cursor/crosshair/uiquestinteractcrosshair2x.blp
    -- LOOT
    [131023] = "LOOT", -- interface/cursor/lootall.blp
    [131026] = "LOOT", -- interface/cursor/picklock.blp
    [131027] = "LOOT", -- interface/cursor/pickup.blp
    [131050] = "LOOT", -- interface/cursor/unablelootall.blp
    [131053] = "LOOT", -- interface/cursor/unablepicklock.blp
    [131054] = "LOOT", -- interface/cursor/unablepickup.blp
    [4675637] = "LOOT", -- interface/cursor/crosshair/lootall.blp
    [4675644] = "LOOT", -- interface/cursor/crosshair/picklock.blp
    [4675645] = "LOOT", -- interface/cursor/crosshair/pickup.blp
    [4675689] = "LOOT", -- interface/cursor/crosshair/unablelootall.blp
    [4675696] = "LOOT", -- interface/cursor/crosshair/unablepicklock.blp
    [4675697] = "LOOT", -- interface/cursor/crosshair/unablepickup.blp
    [4954108] = "LOOT", -- interface/cursor/uilockcursor2x.blp
    [5008300] = "LOOT", -- interface/cursor/uilootallcursor2x.blp
    [5159888] = "LOOT", -- interface/cursor/uipickupcursor2x.blp
    [6075058] = "LOOT", -- interface/cursor/crosshair/uipickupcrosshair2x.blp
    [6075457] = "LOOT", -- interface/cursor/uipicklockcursor2x.blp
    [6075466] = "LOOT", -- interface/cursor/crosshair/uipicklockcrosshair2x.blp
    [6075469] = "LOOT", -- interface/cursor/crosshair/uilockcrosshair2x.blp
    [6116514] = "LOOT", -- interface/cursor/crosshair/uilootallcrosshair2x.blp
}

-- Fallback when the texture comes back as a path or atlas name instead of a
-- known FileDataID. Checked in order; the first match wins.
Data.CURSOR_KEYWORDS = {
    { "gather", "HERB" },
    { "herb", "HERB" },
    { "mine", "ORE" },
    { "mining", "ORE" },
    { "quest", "QUEST" },
    { "lootall", "LOOT" },
    { "pickup", "LOOT" },
    { "picklock", "LOOT" },
}

-- Gathering node object IDs (the 6th field of a GameObject GUID), taken from
-- the classic world database (gameobject_template, type 3 = chest).
-- Used when the cursor texture can't be read.
Data.NODE_IDS = {
    -- HERB
    [1617] = "HERB", -- Silverleaf
    [1618] = "HERB", -- Peacebloom
    [1619] = "HERB", -- Earthroot
    [1620] = "HERB", -- Mageroyal
    [1621] = "HERB", -- Briarthorn
    [1622] = "HERB", -- Bruiseweed
    [1623] = "HERB", -- Wild Steelbloom
    [1624] = "HERB", -- Kingsblood
    [1628] = "HERB", -- Grave Moss
    [2041] = "HERB", -- Liferoot
    [2042] = "HERB", -- Fadeleaf
    [2043] = "HERB", -- Khadgar's Whisker
    [2044] = "HERB", -- Wintersbite
    [2045] = "HERB", -- Stranglekelp
    [2046] = "HERB", -- Goldthorn
    [2866] = "HERB", -- Firebloom
    [3724] = "HERB", -- Peacebloom
    [3725] = "HERB", -- Silverleaf
    [3726] = "HERB", -- Earthroot
    [3727] = "HERB", -- Mageroyal
    [3729] = "HERB", -- Briarthorn
    [3730] = "HERB", -- Bruiseweed
    [142140] = "HERB", -- Purple Lotus
    [142141] = "HERB", -- Arthas' Tears
    [142142] = "HERB", -- Sungrass
    [142143] = "HERB", -- Blindweed
    [142144] = "HERB", -- Ghost Mushroom
    [142145] = "HERB", -- Gromsblood
    [176583] = "HERB", -- Golden Sansam
    [176584] = "HERB", -- Dreamfoil
    [176586] = "HERB", -- Mountain Silversage
    [176587] = "HERB", -- Plaguebloom
    [176588] = "HERB", -- Icecap
    [176589] = "HERB", -- Black Lotus
    [176636] = "HERB", -- Sungrass
    [176637] = "HERB", -- Gromsblood
    [176638] = "HERB", -- Golden Sansam
    [176639] = "HERB", -- Dreamfoil
    [176640] = "HERB", -- Mountain Silversage
    [176641] = "HERB", -- Plaguebloom
    [176642] = "HERB", -- Arthas' Tears
    [180164] = "HERB", -- Sungrass
    [180165] = "HERB", -- Purple Lotus
    [180166] = "HERB", -- Mountain Silversage
    [180167] = "HERB", -- Golden Sansam
    [180168] = "HERB", -- Dreamfoil
    [183046] = "HERB", -- Blindweed
    -- ORE
    [324] = "ORE", -- Small Thorium Vein
    [1610] = "ORE", -- Incendicite Mineral Vein
    [1667] = "ORE", -- Incendicite Mineral Vein
    [1731] = "ORE", -- Copper Vein
    [1732] = "ORE", -- Tin Vein
    [1733] = "ORE", -- Silver Vein
    [1734] = "ORE", -- Gold Vein
    [1735] = "ORE", -- Iron Deposit
    [2040] = "ORE", -- Mithril Deposit
    [2047] = "ORE", -- Truesilver Deposit
    [2054] = "ORE", -- Tin Vein
    [2055] = "ORE", -- Copper Vein
    [2653] = "ORE", -- Lesser Bloodstone Deposit
    [3763] = "ORE", -- Copper Vein
    [3764] = "ORE", -- Tin Vein
    [19903] = "ORE", -- Indurium Mineral Vein
    [73939] = "ORE", -- Ooze Covered Iron Deposit
    [73940] = "ORE", -- Ooze Covered Silver Vein
    [73941] = "ORE", -- Ooze Covered Gold Vein
    [103711] = "ORE", -- Tin Vein
    [103713] = "ORE", -- Copper Vein
    [105569] = "ORE", -- Silver Vein
    [123309] = "ORE", -- Ooze Covered Truesilver Deposit
    [123310] = "ORE", -- Ooze Covered Mithril Deposit
    [123848] = "ORE", -- Ooze Covered Thorium Vein
    [150079] = "ORE", -- Mithril Deposit
    [150080] = "ORE", -- Gold Vein
    [150081] = "ORE", -- Truesilver Deposit
    [150082] = "ORE", -- Small Thorium Vein
    [165658] = "ORE", -- Dark Iron Deposit
    [175404] = "ORE", -- Rich Thorium Vein
    [176643] = "ORE", -- Small Thorium Vein
    [176645] = "ORE", -- Mithril Deposit
    [177388] = "ORE", -- Ooze Covered Rich Thorium Vein
    [180215] = "ORE", -- Hakkari Thorium Vein
    [181108] = "ORE", -- Truesilver Deposit
    [181109] = "ORE", -- Gold Vein
    [181248] = "ORE", -- Copper Vein
    [181249] = "ORE", -- Tin Vein
}

-- Gathering spells. A successful cast tells us what kind of node the
-- target was, so the addon learns node names in any language.
Data.GATHER_SPELLS = {
    [2366] = "HERB", [2368] = "HERB", [3570] = "HERB", [11993] = "HERB", -- Herb Gathering
    [2575] = "ORE", [2576] = "ORE", [3564] = "ORE", [10248] = "ORE", -- Mining
}

-- Display order and colors (r, g, b) for each category.
Data.CATEGORIES = { "QUEST", "HERB", "ORE", "LOOT", "WATCH", "OTHER" }

Data.COLORS = {
    QUEST = { 1.00, 0.82, 0.10 },
    HERB = { 0.35, 1.00, 0.35 },
    ORE = { 0.45, 0.80, 1.00 },
    LOOT = { 0.80, 0.55, 1.00 },
    WATCH = { 1.00, 0.40, 0.80 },
    OTHER = { 0.95, 0.95, 0.95 },
}
