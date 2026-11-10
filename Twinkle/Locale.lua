local ADDON, ns = ...

-- Strings default to English; koKR overrides below.
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

L.TITLE = "Twinkle"
L.LOADED = "Loaded. Type |cffffd100/tw|r for options."
L.ENABLE = "Enable Twinkle"

L.CAT_QUEST = "Quest object"
L.CAT_HERB = "Herb"
L.CAT_ORE = "Ore"
L.CAT_LOOT = "Treasure / container"
L.CAT_WATCH = "Watch list"
L.CAT_OTHER = "Other objects"

-- options: quest objects
L.HEADER_QUEST = "Quest objects (built-in effect)"
L.QUEST_STYLE = "Highlight style"
L.QUEST_STYLE_TT = "How the game itself highlights every quest object around you. This uses a built-in client setting that Forever hides from the options menu."
L.QUEST_STYLE_SPARKLE = "Sparkle"
L.QUEST_STYLE_OUTLINE = "Outline"
L.QUEST_STYLE_NONE = "Don't change"
L.OUTLINE_MODE = "Outline also on"
L.OUTLINE_MODE_TT = "Only used with the Outline style."
L.OUTLINE_MODE_1 = "Quest objects only"
L.OUTLINE_MODE_2 = "+ mouseover"
L.OUTLINE_MODE_3 = "+ mouseover and target"

-- options: nearby objects
L.HEADER_NEARBY = "Herbs, ore and nearby objects"
L.SOFT_ENABLED = "Sparkle the object in front of you"
L.SOFT_ENABLED_TT = "Uses the game's interact targeting to find the closest interactable object and draws an animated sparkle on it."
L.SHOW_CATEGORY = "Sparkle: %s"
L.RANGE = "Detection range"
L.RANGE_TT = "How far away an object can be picked up (yards)."
L.ARC = "Detection direction"
L.ARC_TT = "The game only picks objects you can see on screen. Objects behind you are shown by the direction markers below."
L.ARC_0 = "Straight ahead"
L.ARC_1 = "In front"
L.ARC_2 = "Anywhere on screen"
L.RADAR = "Show herbs and ore behind or beside you"
L.RADAR_TT = "Herbs and ore within the detection range that are not in front of you sparkle at the edge of the screen in their direction (behind you = below your character)."
L.DISTANCE = "%d yd"
L.SIZE = "Sparkle size"
L.OFFSET = "Vertical position"
L.SHOW_LABEL = "Show category label"
L.HUD = "Screen alert when no nameplate"
L.HUD_TT = "If the object has no nameplate (for example in dungeons), show the sparkle with its name near the top of the screen."
L.SOUND = "Play a sound for new objects"
L.BLIZZ_ICON = "Also show the game's interact icon"
L.QUEST_NAME_MATCH = "Detect quest objects by name"
L.QUEST_NAME_MATCH_TT = "Treat an object as a quest object when its name appears in an unfinished quest objective."
L.TEST = "Preview"
L.TEST_BUTTON = "Show"
L.RESTORE = "Game settings"
L.RESTORE_BUTTON = "Restore"
L.RESTORE_TT = "Disable the addon and put back every game setting it changed."
L.MINIMAP_SHOW = "Show minimap button"
L.MINIMAP_LEFT = "|cffffd100Left-click|r: options"
L.MINIMAP_RIGHT = "|cffffd100Right-click|r: turn on / off"
L.MINIMAP_MIDDLE = "|cffffd100Middle-click|r: preview"
L.MINIMAP_DRAG = "|cffffd100Drag|r: move this button"
L.STATUS_ON = "|cff33ff33On|r"
L.STATUS_OFF = "|cffff5555Off|r"

-- chat
L.ENABLED = "Enabled."
L.DISABLED = "Disabled. Game settings restored."
L.RESTORED = "Game settings restored. Use |cffffd100/tw on|r to enable again."
L.COMBAT_DEFERRED = "Some game settings will be applied after combat."
L.WATCH_ADDED = "Added to watch list: %s"
L.WATCH_REMOVED = "Removed from watch list: %s"
L.WATCH_EMPTY = "Watch list is empty."
L.WATCH_LIST = "Watch list:"
L.LEARNED_LIST = "Learned gathering nodes:"
L.LEARNED_CLEARED = "Learned nodes cleared."
L.DEBUG_ON = "Debug messages on."
L.DEBUG_OFF = "Debug messages off."
L.MINIMAP_HIDDEN = "Minimap button hidden. Type |cffffd100/tw minimap|r to show it again."
L.MINIMAP_SHOWN = "Minimap button shown."
L.OPTIONS_IN_COMBAT = "The options window can't be opened in combat."
L.NO_SOFT_TARGET = "No interact target right now. Face an object and try again."
L.HELP = {
    "|cffffd100/tw|r - open options",
    "|cffffd100/tw on|r, |cffffd100/tw off|r - enable / disable (off restores game settings)",
    "|cffffd100/tw test|r - preview the sparkle",
    "|cffffd100/tw minimap|r - show / hide the minimap button",
    "|cffffd100/tw watch add <name>|r - always sparkle objects with this name (with sound)",
    "|cffffd100/tw watch del <name>|r, |cffffd100/tw watch list|r",
    "|cffffd100/tw learned|r, |cffffd100/tw learned clear|r - nodes learned from gathering",
    "|cffffd100/tw debug|r - show what the addon sees for the current target",
}

if GetLocale() == "koKR" then
    L.TITLE = "Twinkle (반짝이)"
    L.LOADED = "불러옴. |cffffd100/tw|r 또는 |cffffd100/반짝|r 으로 설정을 엽니다."
    L.ENABLE = "Twinkle 사용"

    L.CAT_QUEST = "퀘스트 오브젝트"
    L.CAT_HERB = "약초"
    L.CAT_ORE = "광맥"
    L.CAT_LOOT = "보물상자 / 용기"
    L.CAT_WATCH = "관심 목록"
    L.CAT_OTHER = "기타 오브젝트"

    L.HEADER_QUEST = "퀘스트 오브젝트 (게임 내장 효과)"
    L.QUEST_STYLE = "강조 방식"
    L.QUEST_STYLE_TT = "주변의 모든 퀘스트 오브젝트를 게임이 직접 강조하는 방식입니다. 포에버 설정 메뉴에는 숨겨져 있는 클라이언트 설정을 사용합니다."
    L.QUEST_STYLE_SPARKLE = "반짝이"
    L.QUEST_STYLE_OUTLINE = "테두리"
    L.QUEST_STYLE_NONE = "변경 안 함"
    L.OUTLINE_MODE = "테두리 적용 대상"
    L.OUTLINE_MODE_TT = "강조 방식이 '테두리'일 때만 사용됩니다."
    L.OUTLINE_MODE_1 = "퀘스트 오브젝트만"
    L.OUTLINE_MODE_2 = "+ 마우스 올린 대상"
    L.OUTLINE_MODE_3 = "+ 마우스 올린 대상, 선택한 대상"

    L.HEADER_NEARBY = "약초 · 광맥 · 주변 오브젝트"
    L.SOFT_ENABLED = "앞에 있는 오브젝트 반짝이기"
    L.SOFT_ENABLED_TT = "게임의 상호작용 대상 지정 기능으로 가장 가까운 오브젝트를 찾아 반짝이는 효과를 그립니다."
    L.SHOW_CATEGORY = "반짝이: %s"
    L.RANGE = "탐지 거리"
    L.RANGE_TT = "얼마나 멀리 있는 오브젝트까지 찾을지 (미터)."
    L.ARC = "탐지 방향"
    L.ARC_TT = "게임은 화면에 보이는 오브젝트만 대상으로 고릅니다. 뒤쪽에 있는 오브젝트는 아래의 방향 표시로 알려 줍니다."
    L.ARC_0 = "정면만"
    L.ARC_1 = "앞쪽"
    L.ARC_2 = "화면에 보이는 곳 전체"
    L.RADAR = "뒤쪽·옆쪽 약초/광맥도 반짝이기"
    L.RADAR_TT = "탐지 거리 안에 있지만 앞에 있지 않은 약초와 광맥을, 화면 가장자리의 그 방향에 반짝이로 표시합니다 (뒤에 있으면 캐릭터 아래쪽)."
    L.DISTANCE = "%d미터"
    L.SIZE = "반짝이 크기"
    L.OFFSET = "세로 위치"
    L.SHOW_LABEL = "종류 이름 표시"
    L.HUD = "이름표가 없으면 화면에 알림"
    L.HUD_TT = "오브젝트에 이름표가 뜨지 않을 때 (던전 등) 화면 위쪽에 반짝이와 이름을 표시합니다."
    L.SOUND = "새 오브젝트 발견 시 소리"
    L.BLIZZ_ICON = "게임 기본 상호작용 아이콘도 표시"
    L.QUEST_NAME_MATCH = "이름으로 퀘스트 오브젝트 찾기"
    L.QUEST_NAME_MATCH_TT = "완료하지 않은 퀘스트 목표에 이름이 들어 있는 오브젝트를 퀘스트 오브젝트로 취급합니다."
    L.TEST = "미리보기"
    L.TEST_BUTTON = "보기"
    L.RESTORE = "게임 설정"
    L.RESTORE_BUTTON = "원래대로"
    L.RESTORE_TT = "애드온을 끄고, 애드온이 바꾼 게임 설정을 모두 원래 값으로 되돌립니다."
    L.MINIMAP_SHOW = "미니맵 버튼 표시"
    L.MINIMAP_LEFT = "|cffffd100좌클릭|r: 설정 열기"
    L.MINIMAP_RIGHT = "|cffffd100우클릭|r: 켜기 / 끄기"
    L.MINIMAP_MIDDLE = "|cffffd100휠 클릭|r: 미리보기"
    L.MINIMAP_DRAG = "|cffffd100드래그|r: 버튼 위치 옮기기"
    L.STATUS_ON = "|cff33ff33켜짐|r"
    L.STATUS_OFF = "|cffff5555꺼짐|r"

    L.ENABLED = "켜짐."
    L.DISABLED = "꺼짐. 게임 설정을 원래대로 되돌렸습니다."
    L.RESTORED = "게임 설정을 원래대로 되돌렸습니다. 다시 켜려면 |cffffd100/tw on|r"
    L.COMBAT_DEFERRED = "일부 게임 설정은 전투가 끝난 뒤 적용됩니다."
    L.WATCH_ADDED = "관심 목록에 추가: %s"
    L.WATCH_REMOVED = "관심 목록에서 삭제: %s"
    L.WATCH_EMPTY = "관심 목록이 비어 있습니다."
    L.WATCH_LIST = "관심 목록:"
    L.LEARNED_LIST = "채집하며 배운 오브젝트:"
    L.LEARNED_CLEARED = "배운 오브젝트 목록을 지웠습니다."
    L.DEBUG_ON = "디버그 메시지 켜짐."
    L.DEBUG_OFF = "디버그 메시지 꺼짐."
    L.MINIMAP_HIDDEN = "미니맵 버튼을 숨겼습니다. 다시 보려면 |cffffd100/tw minimap|r"
    L.MINIMAP_SHOWN = "미니맵 버튼을 표시합니다."
    L.OPTIONS_IN_COMBAT = "전투 중에는 설정 창을 열 수 없습니다."
    L.NO_SOFT_TARGET = "지금은 상호작용 대상이 없습니다. 오브젝트를 바라보고 다시 시도하세요."
    L.HELP = {
        "|cffffd100/tw|r - 설정 열기",
        "|cffffd100/tw on|r, |cffffd100/tw off|r - 켜기 / 끄기 (끄면 게임 설정 복원)",
        "|cffffd100/tw test|r - 반짝이 미리보기",
        "|cffffd100/tw minimap|r - 미니맵 버튼 보이기 / 숨기기",
        "|cffffd100/tw watch add <이름>|r - 이 이름의 오브젝트는 항상 반짝이 + 소리",
        "|cffffd100/tw watch del <이름>|r, |cffffd100/tw watch list|r",
        "|cffffd100/tw learned|r, |cffffd100/tw learned clear|r - 채집하며 배운 오브젝트",
        "|cffffd100/tw debug|r - 현재 대상에 대해 애드온이 보는 정보",
    }
end
