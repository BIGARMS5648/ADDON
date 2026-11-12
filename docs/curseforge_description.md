<!--
CurseForge 업로드용 문구.
- "Summary"(요약) 칸: 아래 "요약" 한 줄
- "Description"(설명) 칸: Markdown 형식을 고르고 "설명" 부분을 통째로 붙여 넣기
-->

# 요약 (Summary)

**한국어:** 던전을 클리어하면 AOS 게임처럼 MVP·최고의 플레이(POTG) 시상식이 열립니다. 내장 미터기와 게임 정보로 파티원 각자의 캐릭터가 단상에 올라 감정표현을 합니다.

**English:** An end-of-match award ceremony for every dungeon clear: MVP, Play of the Game and 20+ awards, with your party's own characters emoting on a 3D-style podium. Built on the game's own damage meter.

---

# 설명 (Description) — 한국어

## 🏆 BIG PODIUM — 던전 클리어 시상식

AOS 게임이 끝나면 나오는 **MVP / 최고의 플레이(POTG)** 화면, 와우에서도 보고 싶지 않으셨나요?

**BIG PODIUM**은 **WoW Forever**에서 던전을 클리어하는 순간, 파티원 모두의 활약을 정리해 **시상식**을 열어 주는 애드온입니다. 금·은·동 단상 위에 **파티원 각자의 실제 캐릭터**가 올라가 자기가 받은 상에 맞는 **감정표현**을 하고, 조명이 MVP를 비추며 꽃가루가 떨어집니다.

별도 미터기 애드온은 필요 없습니다. 게임에 내장된 **미터기 기록**과, 미터기에 없는 **게임 정보**(어그로, 체력, 시전, 전리품 등)를 함께 써서 공정하게 평가합니다.

---

### ✨ 이런 화면이 열립니다

- **던전 클리어!** 제목과 함께 연출이 시작됩니다.
- **최고의 플레이 (POTG)** — 던전에서 가장 빛났던 **한 순간**을 골라 보여 줍니다.
  - 예: "해적 선장 전투에서 파티 피해의 47%를 혼자 책임졌습니다", "초당 1,491 치유로 아무도 죽지 않게 지켰습니다 (평소의 1.6배)"
  - 그 사람의 **주력 기술**과 비중도 함께 나옵니다.
- **단상 입장** — 활약 지수 순서대로 5명이 단상에 섭니다. 가운데 **금색 단상이 MVP**(다른 사람보다 크게!), 양옆이 은·동, 바깥쪽이 4·5등입니다.
- **MVP 등장** — 마지막으로 MVP가 빛줄기와 함께 등장하고, 위쪽 양 모서리의 **무대 조명**이 MVP를 비추며 **꽃가루**가 떨어집니다.
- **부문별 시상** — 각자 머리 위에 받은 상이 붙습니다.
- 창 맨 아래 줄에는 던전 이름, 소요 시간, 보스 수, 사망·전멸 수, **던전 최고 기록**이 나옵니다. 기록을 깨면 **NEW RECORD!**

클릭하면 연출을 건너뛰고, 드래그로 옮기고, Esc로 닫습니다. 마우스를 캐릭터에 올리면 세부 기록과 점수 계산이 나옵니다. **파티에 공유** 버튼 하나로 결과를 파티 대화에 올릴 수 있습니다.

---

### 🎭 내 캐릭터가 단상에서 감정표현을

단상에는 아이콘이 아니라 **파티원 각자의 실제 3D 캐릭터**가 올라갑니다. 받은 상에 따라 감정표현이 달라집니다.

- **MVP** — 근육 자랑 → 포효
- **최고의 플레이** — 환호 → 춤
- **최고 딜러** 포효 · **최고 힐러** 인사 · **철벽** 경례 · **차단왕** 가리키기 · **해제왕** 손 흔들기
- **수다왕** 말하기 · **득템왕** 춤 · **주사위의 신** 환호
- 재미 부문 — **바닥 수집가** 닭 흉내 · **영혼의 단골** 울기 · **헛손질** 웃기 · **잠수부** 잠자기
- 상을 못 받은 사람은 **MVP에게 박수**를 칩니다 👏

게임은 가까이 있는 사람의 모습만 알려 주기 때문에, BIG PODIUM은 던전을 도는 동안 파티원이 근처에 올 때마다 **캐릭터를 저장**해 둡니다. 그래서 시상식 때 멀리 떨어져 있는 파티원도 단상에 서고, 한 번도 근처에 온 적이 없는 사람만 직업 아이콘으로 나옵니다.

---

### 📊 활약 지수 (MVP 점수) — 딜량 1등이 무조건 MVP가 아닙니다

각자의 **역할 기준**으로 비교합니다. **100 = 그 역할의 평균적인 활약**입니다.

- **딜러** — 파티 전체 피해 중 내 비중
- **힐러** — 파티 전체 치유 중 내 비중 (80%) + 피해 비중 (20%)
- **탱커** — 파티가 받은 피해 중 내 비중 (50%) + 피해 비중 (50%)
- 보너스: 차단·해제 1회당 **+2** (최대 +20), 탱커가 어그로를 안정적으로 잡고 있던 비율에 따라 최대 **+10**
- 감점: 사망 1회당 **-12** (최대 -48), 피할 수 있는 피해 비중만큼 최대 **-20**, 탱커가 아닌데 몹이 달려든 횟수 1번당 **-2** (최대 -10)
- 역할은 던전 찾기 역할을 쓰고, 없으면 기록으로 자동 판단합니다.

---

### 🏅 시상 부문 (20개 이상)

**기본** — 최고 딜러 · 최고 힐러 · 철벽(탱커) · 차단왕 · 해제왕 · 무사고

**실력 (미터기 밖의 정보로 판단)**
- **어그로 장인** — 전투 중 탱커가 어그로를 잡고 있던 비율
- **쉴 틈 없는 손** — 전투 중 분당 시전 횟수
- **구사일생** — 체력 10% 이하까지 떨어졌다가 살아남은 횟수
- **레디 번개** — 전투 준비 확인에 가장 빨리 응답한 사람

**재미** (설정에서 끌 수 있음)
- **바닥 수집가** — 피할 수 있는 피해를 가장 많이 받은 사람
- **영혼의 단골** — 가장 많이 죽은 사람
- **탱커 지망생** — 탱커도 아닌데 몹을 가장 많이 끌어온 사람
- **헛손질** — 시전이 가장 많이 끊긴 사람
- **득템왕** — 고급 이상 아이템을 가장 많이 얻은 사람
- **주사위의 신 / 꽝손** — 입찰 주사위 90 이상 / 10 이하
- **수다왕** — 파티 대화를 가장 많이 한 사람
- **분위기 메이커** — 감정표현을 가장 많이 한 사람
- **랜선 여행자 / 잠수부** — 접속 끊김 / 자리 비움

---

### ⏱ 언제 열리나요?

- **마지막 보스 처치** — 모험 안내서의 보스 목록으로 판단합니다.
- **던전 찾기 · 시나리오 · 쐐기 완료** — 게임의 완료 신호로 판단합니다.
- 안내서가 모르는 던전 — 보스를 하나 이상 잡고 **던전에서 나갈 때** 열립니다 (유령으로 달려 나간 경우 제외).
- 전투 중에는 열리지 않고, 전투가 끝나고 2초 뒤에 열립니다. 시상식 중 전투가 시작되면 자동으로 닫힙니다.
- 공격대에서도 열립니다 (단상에는 상위 5명).

---

### ⌨ 명령어

| 명령 | 설명 |
| --- | --- |
| `/mvp` | 지난 시상식 보기 (던전 진행 중이면 지금까지의 기록) |
| `/mvp test` | 미리보기 (혼자면 내 캐릭터 5명, 파티 중이면 파티원 캐릭터) |
| `/mvp history` | 최근 기록 5개, `/mvp history 2` 로 다시 보기 |
| `/mvp share` | 지난 결과를 파티 대화로 공유 |
| `/mvp options` | 설정 창 |
| `/mvp on` / `/mvp off` | 시상식 켜기 / 끄기 (꺼도 기록은 남깁니다) |
| `/mvp debug` | 미터기·던전 기록 상태 확인 |

`/시상식`, `/bigpodium` 도 같습니다. 미니맵 옆 **애드온 목록 버튼**에서도 열 수 있습니다 (좌클릭: 지난 시상식, 우클릭: 설정).

---

### ⚙ 설정 (`ESC > 설정 > 애드온 > BIG PODIUM`)

- 시상식 켜기 / 끄기
- 마지막 보스를 모르는 던전은 나갈 때 시상식
- 공격대에서도 열기
- 단상에 각자 캐릭터가 감정표현하며 등장 (끄면 직업 아이콘)
- 캐릭터 크기 (80–120%), 캐릭터 높낮이
- MVP 등장 때 꽃가루, 뒤쪽 화면 어둡게, 효과음
- 재미 부문 켜기 / 끄기
- 전투가 시작되면 닫기, 자동으로 닫기 (기본 60초)
- 창 크기 (60–140%)
- 미리보기 / 지난 시상식 버튼

---

### 💡 알아 두면 좋은 점

- **전투 중에는 게임이 미터기 숫자를 숨기기 때문에**(비밀 값), 전투가 끝날 때마다 그 전투 기록을 따로 저장해 둡니다. 미터기를 초기화해도 이미 저장한 기록은 남습니다.
- 던전 안에서 `/reload` 하거나, 재접속하거나, 죽어서 달려 들어와도 같은 던전 기록으로 이어집니다. 던전에 들어가기 전과 나온 뒤의 전투는 포함하지 않습니다.
- 게임이 일부 정보(체력, 위협 수준 등)를 숨기는 상황에서는 그 항목을 건너뛰므로, 해당 상은 나오지 않을 수 있습니다.
- 채팅은 **횟수만** 셉니다. 내용은 저장하지 않으며, 모든 기록은 내 컴퓨터에만 남습니다. 파티 대화로는 **공유 버튼을 눌렀을 때만** 보냅니다.
- 11명 이상 공격대에서는 메모리를 아끼기 위해 캐릭터를 미리 저장하지 않습니다 (가까이 있는 사람은 그대로 캐릭터로 나옵니다).
- 한국어 · 영어 클라이언트를 지원합니다.

---

### 📦 설치

1. 압축을 풀어 나온 **BigPodium** 폴더를 `World of Warcraft\_forever_\Interface\AddOns\` 안에 넣습니다.
2. 캐릭터 선택 화면의 **애드온** 목록에서 BIG PODIUM이 켜져 있는지 확인합니다.
3. 게임에서 `/mvp test` 로 바로 미리보기를 볼 수 있습니다.

---

### 🐞 문제가 있을 때

시상식이 열리지 않거나 기록이 이상하면, 던전 안에서 `/mvp debug` 를 입력한 결과와 던전 이름을 댓글로 남겨 주세요. 미터기 상태, 읽은 전투 수, 모험 안내서 보스 목록이 나와서 원인을 찾는 데 큰 도움이 됩니다.

즐거운 던전 되세요! 🎉

---

# Description — English

## 🏆 BIG PODIUM — a dungeon clear award ceremony

Ever wanted the **MVP / Play of the Game** screen from the end of a MOBA match in WoW?

**BIG PODIUM** opens an **award ceremony** in **WoW Forever** the moment your group clears a dungeon. **Each player's own character** stands on a gold, silver and bronze podium and plays an **emote** that fits the award they won, while stage lights shine on the MVP and confetti falls.

No damage meter addon needed: it reads the game's **built-in damage meter**, plus **game information the meter doesn't have** (aggro, health, casts, loot and more).

### ✨ The ceremony

- **Dungeon cleared!** — the title opens the show.
- **Play of the Game** — the single best moment of the run, e.g. "Did 47% of the party's damage" on the last boss, or "1,491 healing per second (1.6x usual) and nobody died", with that player's key ability.
- **The podium** — the top five by impact score: the **MVP on the gold step in the middle** (bigger than everyone else), 2nd and 3rd on silver and bronze, 4th and 5th outside.
- **The MVP** appears last with light rays, **stage lights** from the top corners and **confetti**.
- **Awards** appear above each player's head.
- The bottom line shows the dungeon, time, bosses, deaths, wipes and your **best time** for that dungeon — beat it and you get **NEW RECORD!**

Click to skip, drag to move, Esc to close. Hover a character for their full stats and score breakdown. **Share** posts the results to group chat.

### 🎭 Your characters, emoting

The podium shows **real 3D characters**, not icons. The MVP flexes and roars, the Play of the Game cheers and dances, award winners roar, bow, salute, point or wave, the joke award winners do the chicken, cry, laugh or fall asleep — and everyone without an award **applauds the MVP**.

The game only shows a player's appearance while they're near you, so BIG PODIUM **saves each party member's character** whenever they're nearby during the run. Party members who wandered off still stand on the podium; only someone never seen nearby gets a class icon.

### 📊 Impact score — top damage isn't automatically MVP

Everyone is compared with what their **role** usually does: **100 = typical for the role**.

- **Damage**: share of the party's damage
- **Healer**: share of the party's healing (80%) + damage (20%)
- **Tank**: share of the damage the party took (50%) + damage (50%)
- Bonus: **+2** per interrupt or dispel (up to +20), up to **+10** for a tank holding aggro
- Penalty: **-12** per death (up to -48), up to **-20** for avoidable damage, **-2** each time a mob turns on a non-tank (up to -10)
- Roles come from the group finder, or are worked out from the numbers.

### 🏅 20+ awards

**Core** — Top damage, Top healer, Iron wall (tank), Interrupt king, Cleanser, Untouchable

**Skill (from outside the meter)** — Aggro master, Busy hands (casts per minute), Close call (survived below 10% health), Ready first (fastest ready check)

**Just for fun** (can be turned off) — Floor fan, Corpse runner, Tank wannabe, Butterfingers, Loot king, Dice god, Unlucky roller, Chatterbox, Mood maker, Connection trouble, Gone fishing

### ⏱ When does it open?

- When the **last boss** dies (Adventure Guide boss list), or the **group finder / scenario / keystone** reports the dungeon complete.
- For dungeons the guide doesn't know: when you **leave** after killing at least one boss (not when you run out as a ghost).
- Never in combat: 2 seconds after combat ends. It closes if combat starts.
- Works in raids too (top five on the podium).

### ⌨ Commands

`/mvp` last ceremony · `/mvp test` preview · `/mvp history [n]` recent runs · `/mvp share` post to group chat · `/mvp options` settings · `/mvp on|off` · `/mvp debug` status. Also `/bigpodium`, and the addon compartment button by the minimap.

### 💡 Good to know

- The game hides meter numbers during combat, so each fight is saved as soon as combat ends; resetting the meter doesn't lose them. `/reload`, relogging and corpse runs continue the same run.
- When the game hides some information (health, threat), that award is simply skipped.
- Chat is only **counted**, never stored; everything stays on your computer, and nothing is posted unless you press **Share**.
- English and Korean clients are supported.

### 📦 Installation

Put the **BigPodium** folder into `World of Warcraft\_forever_\Interface\AddOns\`, enable it in the AddOns list, and type `/mvp test` in game.

### 🐞 Problems?

If a ceremony doesn't open, please comment with the dungeon name and the output of `/mvp debug` typed inside the dungeon.
