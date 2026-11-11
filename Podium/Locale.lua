local ADDON, ns = ...

-- Strings default to English; koKR overrides below.
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

L.TITLE = "Podium"
L.LOADED = "Loaded. An award ceremony appears when you clear a dungeon. |cffffd100/mvp|r shows the last one."

-- ceremony header
L.TAG_CLEAR = "DUNGEON CLEAR"
L.TAG_RAID = "RAID CLEAR"
L.TAG_RUN = "RUN SUMMARY"
L.TAG_DEMO = "PREVIEW"
L.TITLE_CLEAR = "Dungeon cleared!"
L.TITLE_RAID = "Raid cleared!"
L.TITLE_LEAVE = "Run complete"
L.TITLE_PARTIAL = "Run so far"
L.TITLE_DEMO = "Award ceremony"
L.SUB_TIME = "Time %s"
L.SUB_BOSSES = "%d bosses"
L.SUB_DEATHS = "%d deaths"
L.SUB_ONE_DEATH = "1 death"
L.SUB_NO_DEATHS = "No deaths"

-- cards
L.POTG = "Play of the Game"
L.POTG_TAG = "HIGHLIGHT"
L.MVP = "MVP"
L.SCORE = "Impact %d"
L.SCORE_HINT = "100 = typical for the role"
L.KEY_ABILITY = "Key ability"
L.KEY_ABILITY_SHARE = "%d%% of the total"
L.MORE_PLAYERS = "+%d more"

-- roles
L.ROLE_TANK = "Tank"
L.ROLE_HEALER = "Healer"
L.ROLE_DAMAGER = "Damage"

-- stats
L.STAT_DAMAGE = "Damage"
L.STAT_DPS = "DPS"
L.STAT_HEALING = "Healing"
L.STAT_HPS = "HPS"
L.STAT_TAKEN = "Damage taken"
L.STAT_AVOIDABLE = "Avoidable damage"
L.STAT_INTERRUPTS = "Interrupts"
L.STAT_DISPELS = "Dispels"
L.STAT_DEATHS = "Deaths"
L.STAT_SHARE = "%s (%d%%)"
L.STAT_COUNT = "%d"
L.STAT_LINE_INTERRUPTS = "Interrupts %d"
L.STAT_LINE_DISPELS = "Dispels %d"
L.STAT_LINE_DEATHS = "Deaths %d"
L.SCORE_BASE = "Role performance"
L.SCORE_BONUS = "Interrupts / dispels"
L.SCORE_PENALTY = "Deaths / avoidable damage"

-- awards
L.AWARD_DAMAGE = "Top damage"
L.AWARD_HEALING = "Top healer"
L.AWARD_TANK = "Iron wall"
L.AWARD_INTERRUPTS = "Interrupt king"
L.AWARD_DISPELS = "Cleanser"
L.AWARD_SURVIVOR = "Untouchable"
L.AWARD_FLOOR = "Floor fan"
L.AWARD_DEATHS = "Corpse runner"
L.VALUE_TIMES = "%d times"
L.VALUE_ONCE = "Once"
L.VALUE_FLOOR = "Avoidable %s"
L.VALUE_TAKEN = "%s taken"
L.VALUE_SURVIVOR = "No deaths, least avoidable damage"
L.VALUE_SURVIVOR_CLEAN = "No deaths, nothing avoidable taken"

-- play of the game
L.POTG_DAMAGE = "Did %d%% of the party's damage."
L.POTG_HEAL = "Kept the party up with %s healing per second (%.1fx usual)."
L.POTG_HEAL_SAFE = "%s healing per second (%.1fx usual) and nobody died."
L.POTG_TANK = "Took %s damage per second and stayed up."
L.POTG_TANK_TOTAL = "Took %s damage per second."
L.POTG_INTERRUPTS = "Interrupted %d casts."
L.FIGHT_N = "Fight #%d"

-- preview (/mvp test)
L.DEMO_INSTANCE = "Practice Dungeon"
L.DEMO_TRASH = "Trash pack"
L.DEMO_BOSS1 = "Gatekeeper"
L.DEMO_BOSS2 = "Foreman"
L.DEMO_BOSS3 = "Pirate Captain"
L.DEMO_TANK = "Ironhide"
L.DEMO_HEALER = "Lightmend"
L.DEMO_ROGUE = "Shadowstep"
L.DEMO_HUNTER = "Longshot"

-- buttons / footer
L.SHARE = "Share"
L.CLOSE = "Close"
L.HINT = "Click to skip  ·  Drag to move  ·  Esc to close"
L.AUTO_CLOSE = "Closes in %d s"

-- chat sharing (plain text, sent to group chat)
L.SHARE_HEADER = "[Podium] %s"
L.SHARE_MVP = "MVP: %s (impact %d)"
L.SHARE_POTG = "Play of the Game: %s - %s %s"
L.SHARE_AWARD = "%s: %s"
L.SHARE_SOLO = "Not in a group; the summary is shown here only."
L.SHARE_FAILED = "Couldn't send to group chat right now."

-- chat messages
L.NO_DATA = "No damage meter records for this run yet."
L.NO_RUN = "No dungeon run recorded yet. Try |cffffd100/mvp test|r for a preview."
L.METER_UNAVAILABLE = "The built-in damage meter isn't available (%s), so there is nothing to award."
L.METER_SECRET = "The damage meter still hides its numbers; trying again when combat is over."
L.HISTORY = "Recent runs (|cffffd100/mvp history <number>|r to show one):"
L.HISTORY_LINE = "%d. %s - %s, MVP %s"
L.HISTORY_EMPTY = "No runs recorded yet."
L.HISTORY_CLEARED = "Run history cleared."
L.ENABLED = "Ceremonies on."
L.DISABLED = "Ceremonies off."
L.OPTIONS_IN_COMBAT = "Options can't be opened in combat."
L.UNKNOWN = "Unknown"
L.HELP = {
    "|cffffd100/mvp|r - show the last ceremony (or the current run so far)",
    "|cffffd100/mvp test|r - preview with made-up numbers",
    "|cffffd100/mvp history|r - recent runs, |cffffd100/mvp history 2|r shows one",
    "|cffffd100/mvp share|r - post the last result to group chat",
    "|cffffd100/mvp options|r - settings,  |cffffd100/mvp on|r / |cffffd100off|r",
    "|cffffd100/mvp debug|r - what the addon sees from the damage meter",
}

-- options
L.ENABLE = "Show award ceremonies"
L.HEADER_WHEN = "When"
L.ON_LEAVE = "When leaving a dungeon, if the last boss wasn't detected"
L.ON_LEAVE_TT = "The last boss is found with the Adventure Guide. If it doesn't know the dungeon, the ceremony appears when you leave it instead (not when you run out as a ghost). Needs at least one boss kill."
L.RAIDS = "Also in raids"
L.HEADER_LOOK = "Look"
L.MODELS = "Players' own characters on the podium, with emotes"
L.MODELS_TT = "Each player's character stands on the podium and plays an emote for their result (the MVP flexes, the others cheer or applaud). The game only sends a player's appearance while they're near you, so each party member's character is kept from the last time they were nearby; anyone never seen nearby gets their class icon. Off: class icons for everyone."
L.MODEL_SIZE = "Character size"
L.MODEL_OFFSET = "Character height on the step"
L.MODEL_OFFSET_TT = "If the characters float above their step or sink into it, move them down (-) or up (+). Check with the Preview button."
L.CONFETTI = "Confetti when the MVP appears"
L.DIM = "Darken the screen behind it"
L.SOUND = "Sound effects"
L.FUN = "Joke awards (deaths, standing in fire)"
L.HIDE_IN_COMBAT = "Close when combat starts"
L.AUTO_CLOSE_OPT = "Close automatically after"
L.AUTO_CLOSE_TT = "Seconds. 0 = stay until closed. The timer pauses while the mouse is over it."
L.SECONDS = "%d s"
L.NEVER = "Never"
L.SCALE = "Size"
L.TEST = "Preview"
L.TEST_BUTTON = "Show"
L.LAST = "Last ceremony"
L.LAST_BUTTON = "Show"
L.COMPARTMENT_LEFT = "|cffffd100Left-click|r: last ceremony"
L.COMPARTMENT_RIGHT = "|cffffd100Right-click|r: options"
L.STATUS_ON = "|cff33ff33On|r"
L.STATUS_OFF = "|cffff5555Off|r"

-- number formatting: 1,234 / 12.3K / 4.56M / 1.2B
function ns.FormatNumber(value)
    value = tonumber(value) or 0
    local abs = math.abs(value)
    if abs >= 1e9 then
        return ("%.2fB"):format(value / 1e9)
    elseif abs >= 1e6 then
        return ("%.2fM"):format(value / 1e6)
    elseif abs >= 1e4 then
        return ("%.1fK"):format(value / 1e3)
    end
    local text = tostring(math.floor(value + 0.5))
    return (text:reverse():gsub("(%d%d%d)(%d)", "%1,%2"):reverse())
end

if GetLocale() == "koKR" then
    L.TITLE = "Podium (시상식)"
    L.LOADED = "로드됨. 던전을 클리어하면 시상식이 열립니다. |cffffd100/mvp|r 로 지난 시상식을 다시 볼 수 있습니다."

    L.TAG_CLEAR = "DUNGEON CLEAR"
    L.TAG_RAID = "RAID CLEAR"
    L.TAG_RUN = "RUN SUMMARY"
    L.TAG_DEMO = "PREVIEW"
    L.TITLE_CLEAR = "던전 클리어!"
    L.TITLE_RAID = "공격대 클리어!"
    L.TITLE_LEAVE = "던전 종료"
    L.TITLE_PARTIAL = "지금까지의 기록"
    L.TITLE_DEMO = "시상식 미리보기"
    L.SUB_TIME = "소요 시간 %s"
    L.SUB_BOSSES = "보스 %d"
    L.SUB_DEATHS = "사망 %d"
    L.SUB_ONE_DEATH = "사망 1"
    L.SUB_NO_DEATHS = "사망 없음"

    L.POTG = "최고의 플레이"
    L.POTG_TAG = "PLAY OF THE GAME"
    L.SCORE = "활약 지수 %d"
    L.SCORE_HINT = "100 = 그 역할의 평균"
    L.KEY_ABILITY = "주력 기술"
    L.KEY_ABILITY_SHARE = "전체의 %d%%"
    L.MORE_PLAYERS = "외 %d명"

    L.ROLE_TANK = "탱커"
    L.ROLE_HEALER = "힐러"
    L.ROLE_DAMAGER = "딜러"

    L.STAT_DAMAGE = "피해"
    L.STAT_HEALING = "치유"
    L.STAT_TAKEN = "받은 피해"
    L.STAT_AVOIDABLE = "피할 수 있는 피해"
    L.STAT_INTERRUPTS = "차단"
    L.STAT_DISPELS = "해제"
    L.STAT_DEATHS = "사망"
    L.STAT_LINE_INTERRUPTS = "차단 %d"
    L.STAT_LINE_DISPELS = "해제 %d"
    L.STAT_LINE_DEATHS = "사망 %d"
    L.SCORE_BASE = "역할 활약"
    L.SCORE_BONUS = "차단·해제 보너스"
    L.SCORE_PENALTY = "사망·바닥 감점"

    L.AWARD_DAMAGE = "최고 딜러"
    L.AWARD_HEALING = "최고 힐러"
    L.AWARD_TANK = "철벽"
    L.AWARD_INTERRUPTS = "차단왕"
    L.AWARD_DISPELS = "해제왕"
    L.AWARD_SURVIVOR = "무사고"
    L.AWARD_FLOOR = "바닥 수집가"
    L.AWARD_DEATHS = "영혼의 단골"
    L.VALUE_TIMES = "%d회"
    L.VALUE_ONCE = "1회"
    L.VALUE_FLOOR = "바닥 피해 %s"
    L.VALUE_TAKEN = "받은 피해 %s"
    L.VALUE_SURVIVOR = "사망 0, 바닥 피해 최소"
    L.VALUE_SURVIVOR_CLEAN = "사망 0, 바닥 피해 0"

    L.POTG_DAMAGE = "파티 피해의 %d%%를 혼자 책임졌습니다."
    L.POTG_HEAL = "초당 %s 치유로 파티를 버텨 냈습니다 (평소의 %.1f배)."
    L.POTG_HEAL_SAFE = "초당 %s 치유로 아무도 죽지 않게 지켰습니다 (평소의 %.1f배)."
    L.POTG_TANK = "초당 %s 피해를 받아내며 끝까지 버텼습니다."
    L.POTG_TANK_TOTAL = "초당 %s 피해를 받아냈습니다."
    L.POTG_INTERRUPTS = "시전을 %d번 끊어 냈습니다."
    L.FIGHT_N = "전투 #%d"

    L.DEMO_INSTANCE = "연습용 던전"
    L.DEMO_TRASH = "일반 몹"
    L.DEMO_BOSS1 = "문지기"
    L.DEMO_BOSS2 = "현장 감독"
    L.DEMO_BOSS3 = "해적 선장"
    L.DEMO_TANK = "강철피부"
    L.DEMO_HEALER = "빛치유"
    L.DEMO_ROGUE = "그림자걸음"
    L.DEMO_HUNTER = "명사수"

    L.SHARE = "파티에 공유"
    L.CLOSE = "닫기"
    L.HINT = "클릭: 건너뛰기  ·  드래그: 이동  ·  Esc: 닫기"
    L.AUTO_CLOSE = "%d초 후 닫힘"

    L.SHARE_HEADER = "[시상식] %s"
    L.SHARE_MVP = "MVP: %s (활약 지수 %d)"
    L.SHARE_POTG = "최고의 플레이: %s - %s %s"
    L.SHARE_SOLO = "파티 중이 아니라서 여기에만 표시합니다."
    L.SHARE_FAILED = "지금은 파티 대화로 보낼 수 없습니다."

    L.NO_DATA = "아직 이 던전의 미터기 기록이 없습니다."
    L.NO_RUN = "아직 기록된 던전이 없습니다. |cffffd100/mvp test|r 로 미리보기를 볼 수 있습니다."
    L.METER_UNAVAILABLE = "내장 미터기를 쓸 수 없어서(%s) 시상할 기록이 없습니다."
    L.METER_SECRET = "미터기가 아직 숫자를 숨기고 있습니다. 전투가 끝나면 다시 시도합니다."
    L.HISTORY = "최근 기록 (|cffffd100/mvp history 번호|r 로 다시 보기):"
    L.HISTORY_LINE = "%d. %s - %s, MVP %s"
    L.HISTORY_EMPTY = "기록이 없습니다."
    L.HISTORY_CLEARED = "기록을 지웠습니다."
    L.ENABLED = "시상식을 켰습니다."
    L.DISABLED = "시상식을 껐습니다."
    L.OPTIONS_IN_COMBAT = "전투 중에는 설정을 열 수 없습니다."
    L.UNKNOWN = "알 수 없음"
    L.HELP = {
        "|cffffd100/mvp|r - 지난 시상식 보기 (던전 진행 중이면 지금까지의 기록)",
        "|cffffd100/mvp test|r - 가짜 기록으로 미리보기",
        "|cffffd100/mvp history|r - 최근 기록, |cffffd100/mvp history 2|r 로 다시 보기",
        "|cffffd100/mvp share|r - 지난 결과를 파티 대화로 공유",
        "|cffffd100/mvp options|r - 설정,  |cffffd100/mvp on|r / |cffffd100off|r - 켜기 / 끄기",
        "|cffffd100/mvp debug|r - 애드온이 읽은 미터기 상태",
    }

    L.ENABLE = "시상식 켜기"
    L.HEADER_WHEN = "시상식 시점"
    L.ON_LEAVE = "마지막 보스를 모르는 던전은 나갈 때 시상식"
    L.ON_LEAVE_TT = "마지막 보스는 모험 안내서로 판단합니다. 안내서에 없는 던전이면 던전에서 나갈 때 시상식을 엽니다 (유령으로 달려 나간 경우는 제외). 보스를 하나 이상 잡았을 때만 열립니다."
    L.RAIDS = "공격대에서도 열기"
    L.HEADER_LOOK = "모양"
    L.MODELS = "단상에 각자 캐릭터가 감정표현하며 등장"
    L.MODELS_TT = "파티원 각자의 캐릭터가 단상에 서서 결과에 맞는 감정표현을 합니다 (MVP는 근육 자랑, 나머지는 환호나 박수). 게임은 가까이 있는 사람의 모습만 보내 주기 때문에, 파티원이 근처에 있을 때 캐릭터를 저장해 두었다가 멀리 있어도 그 캐릭터로 보여 줍니다. 한 번도 근처에 온 적이 없는 사람만 직업 아이콘으로 나옵니다. 끄면 모두 직업 아이콘."
    L.MODEL_SIZE = "캐릭터 크기"
    L.MODEL_OFFSET = "캐릭터 높낮이"
    L.MODEL_OFFSET_TT = "캐릭터가 단상 위에 떠 있거나 단상에 파묻혀 보이면 내리거나(-) 올리세요(+). 미리보기 버튼으로 확인할 수 있습니다."
    L.CONFETTI = "MVP 등장 때 꽃가루"
    L.DIM = "뒤쪽 화면 어둡게"
    L.SOUND = "효과음"
    L.FUN = "재미 부문 (사망, 바닥 피해)"
    L.HIDE_IN_COMBAT = "전투가 시작되면 닫기"
    L.AUTO_CLOSE_OPT = "자동으로 닫기"
    L.AUTO_CLOSE_TT = "초 단위. 0 = 직접 닫을 때까지. 마우스를 올려 두면 멈춥니다."
    L.SECONDS = "%d초"
    L.NEVER = "안 함"
    L.SCALE = "크기"
    L.TEST = "미리보기"
    L.TEST_BUTTON = "보기"
    L.LAST = "지난 시상식"
    L.LAST_BUTTON = "보기"
    L.COMPARTMENT_LEFT = "|cffffd100좌클릭|r: 지난 시상식"
    L.COMPARTMENT_RIGHT = "|cffffd100우클릭|r: 설정"
    L.STATUS_ON = "|cff33ff33켜짐|r"
    L.STATUS_OFF = "|cffff5555꺼짐|r"

    -- 1,234 / 1.2만 / 123만 / 1.23억
    function ns.FormatNumber(value)
        value = tonumber(value) or 0
        local abs = math.abs(value)
        if abs >= 1e8 then
            return ("%.2f억"):format(value / 1e8)
        elseif abs >= 1e6 then
            return ("%d만"):format(math.floor(value / 1e4 + 0.5))
        elseif abs >= 1e4 then
            return ("%.1f만"):format(value / 1e4)
        end
        local text = tostring(math.floor(value + 0.5))
        return (text:reverse():gsub("(%d%d%d)(%d)", "%1,%2"):reverse())
    end
end

-- "m:ss" or "h:mm:ss"
function ns.FormatTime(seconds)
    seconds = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
    if h > 0 then
        return ("%d:%02d:%02d"):format(h, m, s)
    end
    return ("%d:%02d"):format(m, s)
end
