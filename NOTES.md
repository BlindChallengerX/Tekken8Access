# TekkenA11y developer notes (rebuild 0.7.0, 2026-10-16, game ver. 3.02.02)

## Layout
- `mod/Scripts` - UE4SS Lua (main, out, menus, fight, tam = Arcade Quest, watch, data, lib/ui,
  lib/notation, dev).
- `helper/` - TekkenA11yHelper.exe (C, 64-bit w64devkit): named pipe `\\.\pipe\TekkenA11y`,
  Prism speech (speech.c from SC2 Access), waveOut synth (audio.c from SC2), beacon.c.
- `build.sh` (Git Bash) -> `out/TekkenA11y`; `deploy.ps1` copies into the game's Mods folder.
- `tools/` - t8.py (bot: dev console, keys, screenshots; `boot`, `practice [right]`,
  `pmenu "<row>"`, `state`; every step checks the screen or the mod's speech and stops with
  BotError instead of pressing on; the window is found by the game's process), lat.py
  (key-to-SAY latency), flow.py (main menu -> practice match), discover.lua (hook every
  hover-like Blueprint function and log calls), sweep_names.py, icon_rows.py, restart.ps1.
- `old-v0.6/` - the June build this replaces (file outbox + external speaker, polling).

## Dev console
Create `Mods\TekkenA11y\dev.txt`; `python tools\t8.py lua "return 1"` or `luaf file.lua`
runs Lua on the game thread, `--async` first line runs it off-thread. Output in
%TEMP%\TekkenA11y\out.txt. Helper log (SAY lines with ms times): %TEMP%\TekkenA11y\helper.log.

## UE4SS 3.0.1 rules learned the hard way (hangs and crashes, 2026-10-16)
- Never hook native `/Script/...` functions with a Lua callback: the Lua thread froze.
- RegisterHook only on the game thread, and not inside a hook callback. From the async thread
  it deadlocked, and on a function the game thread was running that frame it crashed UE4SS
  (access violation in hook dispatch, crash report 16:31).
- ExecuteInGameThread: never two outstanding. A second call while one was queued/running
  deadlocked (game thread waiting for the Lua lock, async thread holding it and waiting on the
  queue mutex; seen with tools\threads.py). Windows then killed the game as hung (user saw it).
  Treat a job as finished only ~0.2 s after it returned; jobs can also be dropped (title).
- Never touch game objects from the async thread: RegisterKeyBind callbacks run there too, so
  keys only queue work.
- ExecuteInGameThread from the async thread at all: it waits for a lock the game thread holds
  while it runs a Lua hook, which waits for the Lua lock the async thread holds. With per-frame
  hooks this hung the game within minutes (second "fatal error"). Not used anywhere now.
- So: one bootstrap LoopAsync registers WBP_UI_InformationBar_C:OnSetMessage (fires only on
  screen/help changes) and stops. Everything else runs in game-thread hooks: frame() (hooked
  EffectManager/StageEffectManager/ItemEffectManager ReceiveTick, InformationBar Tick; ~35 ms)
  and maint() (1 s: RegisterHook for loaded classes, preload, scans). RegisterHook from inside a
  hook callback for a different function works; never for the function being dispatched.
- StaticFindObject of a class that is not loaded costs ~13 ms (2026-10-31, measured in a fight;
  found classes are quick), and so does a failed RegisterHook. 0.7.2's Arcade Quest hooks stayed
  pending outside Arcade Quest, and maint() looked for all of them and retried them every second:
  a ~200 ms freeze each second, felt as input lag in fights. Now maint() does nothing in a fight,
  checks one class per pass (fixed hooks first, every 5 s when menus are idle) and registers only
  hooks of classes it found. lib/prof.lua logs "prof gaps" / "prof busy" to helper.log every 5 s
  in fights (frame gaps and the mod's costliest hooks and steps).
- FindFirstOf/FindAllOf cost 10-26 ms (a whole frame): in fights
  nothing searches. Fight detection = WBP_UI_HUD_S2_C:Tick hook; menu widgets come from their
  hooks; fighters/ball/PlayerController searched once per fight; scans only after menu activity;
  check_pending looks at 12 generic classes per second plus the fixed ones. Measured in a fight:
  Fight.tick 0.1 ms, subtitles 0.08 ms (were 5 ms with 70 ms spikes, and 15 ms). The user had
  felt this as major slowdown in fights.
- Do not call ExecuteInGameThread from inside a hook callback (froze); use Menus.defer (run by
  frame()).
- Hooking every function of a screen (tools\discover_all.lua) can break that screen (input
  stayed disabled in Jukebox and story chapter select). Use it, then restart the game.
- A subtitle hook (CreateFrontSubtitle) froze Lua during a loading screen: subtitles are polled.
- FindFirstOf can return a dead object: check IsValid before GetClass (a console query
  without the check probably crashed the game once).
- LoadAsset needs the class path: `/Game/.../WBP_X.WBP_X_C`.
- package.path is one string; match `[^;]*` not `.-` when finding the mod folder.
- TMap ForEach and UFunction parameter lists are not readable here.

## Screens and hooks
- Main menu rows: `WBP_UI_MainMenu_Menu_List_C:play_hover` (text TB_title_ON). Tabs:
  `WBP_UI_MainMenu_Tab_Item_C:PlayAnimSelect` (generic). Tab keys: Num - / Num 9.
- Generic: any widget class with play_hover / PlayAnimHover / PlayAnimSelect / OnHover...,
  or `Select` on a *Button* class, reads its visible ON texts (menus.lua scan_classes).
  BlackPen / Banner classes skipped (they animate on every move).
- Help bar: `WBP_UI_InformationBar_C:OnSetMessage` -> spoken after 350 ms rest.
- Char select: `WBP_UI_CharSelect_C:OnSetCurrentName(isLeft, fighterId)`;
  `OnSetCurrentFighterInfo(isLeft, CharSelectFighterInfo{style, Origin, Height, Weight})`
  are text ids -> `PolarisUMGFunctionLibrary:GetLocalizeText`. Names are textures, so
  data.lua maps ids (read off the screen). One locked slot (likely Roger Jr.) sends no name.
- Stage select: `WBP_UI_StageSelect_C:_SetSelectedStageID(id, bool)` every frame; Random
  cycles preview ids while `WBP_UI_StageSelect_RandomBG` is visible.
- Side select: `WBP_UI_SideSelect_C:OnSelectLeftSide / OnSelectRightSide`.
- Practice menu (`/Game/UI/Widget/Practice/WBP_UI_PracticeMenu`): `SetCursorButton1..4(i)`
  for ListView_1, ListView_2, WBP_UI_PracticeMenu_Menu_3.ListView_3, ListView_4. Items
  (BP_PracticeMenu_Button_*_item_C) hold `.Widget`, `.Text`, `.text2`. The game re-sends
  all columns each move; active_layer_index / cursor_index_1 never change. Row `is_active`
  marks the parent of the focused column. See practice_flush / practice_fallback.
- Move list (`WBP_UI_CommandList_C:SetCursorIndex(i)`, also sample combos):
  `.WBP_UI_CommandList_Win.ListView_1:GetItemAt(i)` -> BP_CommandList_Button_Item_C
  {isHeading, no, nameText, commandText, noteText, damageText, isRawNameText}, text ids.
- Pause menu (other modes): `WBP_UI_Pause_MenuButton_C:Select` (tested in Tekken Ball and story).
  Open state: `WBP_UI_Pause_C` IsVisible (never "in viewport", it is nested).
- Jukebox (watch.lua): carousel = WBP_UI_JukeBox_C.select_jacket_next into play_list_infos
  (JukeBoxPlayList textId/Selected/Unlocked); BgmWin/StageWin ListView_Buttons + selected_index,
  items .Info JukeBoxBGM {BgmTextId, Equipped, Playing, Unlocked, Store} / JukeBoxMyList
  {SceneTextId, BgmTextId, Climax}; series name = BgmWin.TB_titleName; PresetWin_C:Select(i).
  Tabs switch with Num -.
- Tekken Ball: WBP_UI_TB_BallSlot_C:OnCursorMoveUMG(count, index) + OnSetInfoUMG(desc); names on
  WBP_UI_TB_BallSlot_Panel_C {SlotNum, side, IsLocked, TB_name_1P/2P}. WBP_UI_TB_DamageSet_C:
  OnCursorMoveUMG -> WBP_UI_TB_DamageSet_Window_C.TB_num. CPU difficulty:
  WBP_UI_DifficultySelect_MenuButton_C:Select. Ball: PolarisBallActor (IsVisibleActor),
  K2_GetActorLocation; floor ~ fighter actor Z - 100.
- Story: WBP_UI_Story_ChapterSelect_C:SetChapterTitleText -> TB_ChapterName_Main/_Sub
  (Left/Right). Subtitles: WBP_UI_Subtitle_C read every tick. Story fighters have their own ids
  (e.g. 121, 118, classes BP_Character_XXE/XXB): fight start says "Fight start".
- Dialogs: `WBP_UI_Dialog_TextButton_C:Select` (Yes/No, Up/Down keys), dialog PlayAnimIn.

## Command icons (lib/notation.lua)
cmd_01/02 bracket pair; 03-10 tap d/b d d/f b f u/b u u/f; 11-18 hold; 20-34 buttons =
19 + bitmask (1=1, 2=2, 3=4, 4=8); 35 star; 38 "then". Button icon: left dot 1, top 2,
bottom 3, right 4. kbd_NNN_en_US are keyboard key pictures (key unknown -> "keyboard key").

## Fight
- `PolarisCharacterActor` with PlayerNumber 0 / 1 (2 = practice dummy). FighterId,
  GetHPPercentage (0 until the round is set up), K2_GetActorLocation (cm).
- Char select also has these actors: a fight needs `WBP_UI_HUD_S2_C` shown.
- Camera yaw: PlayerController.PlayerCameraManager:GetCameraRotation(). Screen right =
  (-sin, cos). Opponent depth = (op - me) . camera forward / distance.
- "Me" = the side picked on side select (left = PlayerNumber 0, right = 1), else 0.
- Verified 2026-10-16: sidestep down (toward camera) -> depth +0.41 -> level +1 (higher).

## Side detection and throws (0.7.1, 2026-10-29)
- `/Script/Polaris.Default__PolarisBlueprintLibrary` (StaticFindObject once) takes a player id
  (= PlayerNumber 0/1): GetSideByPlayerID, GetTargetPlayerID, GetFighterIDByPlayerID,
  IsFighterAttackingMot, GetFighterAttackingDamageValue, GetFighterAttackingBone. GetMotName
  returns garbage. Two calls cost 0.01 ms.
- Me: side select (Menus.side) if picked; else the HUD online IDs
  `WBP_UI_HUD_S2_C.WBP_UI_HUD_Gauge_S2.WBP_UI_HUD_Player_S2.TB_OnlIneID_L2 / _R2` compared with
  own_name.txt (learned in any offline fight with a picked side); else the only non-empty name
  (vs CPU). Retried every 0.5 s for 10 s after the fight starts. Verified in Practice from both
  sides and with faked online names; not yet in a real online match.
- Throws: damage value has bit 0x4000 (16384) for every throw while it starts; the bone is the
  grabbing hand (13 left, 9 right) and 1+2 command throws grab with 13 too, so the break is not
  in anything the library exposes. Tested in Throw Escape Training (2026-10-29, Kazuya, health
  as the judge): plain 1+3 / 2+4 break with 1 (or 2) pressed ~0.15-0.45 s after the start; 1+2
  does not break them; rolling 1 into 1+2 breaks plain throws but not 1+2 throws. So in
  matches every throw plays "throw1".
- Practice: WBP_UI_Practice_S2_C.WBP_UI_Practice_TIPS.TB_Command = "Throw escape <cmd_20> or
  <cmd_21>" / "<cmd_22>". Between throws the panel can stay up with dimmed icons (cmd_20d); the
  icons light up when the grab connects (~0.2 s after the start). The cue waits for lit icons
  (0.45 s limit). The Practice HUD is found when the pause menu is used (menus.lua,
  Menus.practice_hud) and dropped when the fight stops. F2 toggles the cues (F10 opens the
  UE4SS ConsoleEnabler console).
- Throw Escape / Punishment Training menu: WBP_UI_CounterPractice_C SetCurrentTab(i) = left
  column (difficulty, Win.VerticalBox_DifficultyButton TB_Menu_ON), SetCursorIndex(i) = right
  (Win.ScrollBox_Command, _Command_C TB_Number/TB_name/TB_Command; T_UI_CheckMark Hidden = off),
  SetActiveLayer(0/1). All three fire on open (merged into one reading). TB_Note is placeholder
  text. Enter on the left column starts the training; B in training opens this screen. The
  pause menu replays its row (cursor hooks and the help-bar fallback) while it is open: muted.

## Combo Challenges (2026-10-29)
- List: `WBP_UI_ComboChallenge_C:SetCursorIndex(i)`; items in Win.ListView_Challenge
  (BP_ComboChallenge_Button_Item_C {Text id, checked}); steps = visible
  WBP_UI_ComboChallenge_Command_C children of Win.VerticalBox_Command (Command_1..5 are hidden
  placeholders), TB_Command rich text, read 0.1 s after the cursor; TB_Damage_2, TB_Note,
  difficulty = highest visible T_UI_PL_Difficulty_N. Start = PlayAnimDecide (OnDecide never fires).
- In a challenge: WBP_UI_Practice_ComboChallenge_C (TB_Challenge, VerticalBox_Command of _Line_C,
  TB_Command_ON). Current step loops Anim_Hover, landed step plays Anim_Completed, a drop moves
  the hover back to row 1; no BP event fires, so rows are polled every 50 ms (IsAnimationPlaying).
  Clear detection (last row Completed) not yet seen in game.
- CRASH: polling row widgets kept from before the challenge list (B) was opened killed the game
  ~8 s later, no crash report (reproduced 3 times, gone with the poll off). Now no row is kept
  between polls and the panel is dropped while any menu is open, then searched once after.
- In a challenge player 2's fighter is hidden and the dummy is PlayerNumber 2: Fight uses it as
  the opponent (Fight.refind() on challenge start/end); PolarisBlueprintLibrary is only called
  once fighters 0 and 1 are up and health has been read (lib_safe).
- Star icon cmd_35 = "n" (neutral), e.g. f, n, d, d/f+2.
- Esc from the challenge list leaves the challenge (back to free practice).
- Dev console: never walk every property of a big widget (WBP_UI_Practice_S2_C froze the game).

## Arcade Quest (tam.lua, 0.7.2, 2026-10-29)
- Classes under /Game/TrueArcadeMode/. Player BP_TAM_Player_C (ReceiveTick hooked: hands over the
  player, no searches). collision_npc = the NPC in reach; ui_talk (WBP_TAM_Npc_Talk_C),
  ui_battle_talk (WBP_UI_TAM_Talk_C), ui_menu_2d (WBP_UI_TAM_BuddyMenu_C, Max's menu);
  IsTalkTurn / IsEventFlag / IsPauseMenu.
- NPCs: BP_TAM_NPC_Base_C subclasses (Ghost, Menu = Max, GhostMenu = ghost battle machine,
  MachineBattle_Base at (0,0,2000) = placeholder, skipped). Names: GhostName (string),
  AvatarHeadName (Max), else NpcName (often NULL). IsWon, IsTreasure, GhostRank.
- Head widgets WBP_UI_Lobby_AvatarHead_C: TB_name2, Rep_T_UI_LOBBY_ICON texture T_UI_LB_Icon_09 =
  treasure chest, _03 = none. Prompt WBP_UI_Lobby_HeadGuide_C ("<kbd> Talk/Battle"), only while
  the NPC is on screen; a guide with no parent is not shown.
- Talk: Npc_Talk.showingMessage holds the whole line while it types out; "Event Show" /
  "Event Show Next Text" fire per line. The window stays IsVisible after closing.
- UE4SS gives a new Lua object for the same UObject: compare actors by GetFullName, not ==.
- Max's menu rows are made at run time: WBP_UI_TAM_BuddyMenuList_C:OnButtonSelect (and
  _SubList_C) give the row (TB_text_ON); BuddyMenu.TB_Msg = Max's line for it. Arcade map
  WBP_UI_TAM_RPG_Map_C (Event_Start), spots WBP_UI_TAM_RPG_Icon_C:PlayAnim_Hover, IsUnlock.
- Keyboard in Arcade Quest: WASD move (camera-relative), J and Numpad 4 use people/machines,
  B opens the menu (Quick Select, Sound Options, Controller Setup, Main Menu), N switches the
  name tags (name / Steam id / Polaris id). The camera turns with the avatar.
- Beacon: "F mx my ox oy cx cy far near" (far 1500, near 120 cm); silent in reach and while busy.
- kbd_NNN icons: NNN = scan code (kbd_036 J, kbd_048 B, kbd_049 N, kbd_075 Numpad 4).

## Character Episodes (2026-10-29)
- WBP_UI_Story_CharaEpisode_C: SetBgInfo(_, name, style, origin, height, weight) text ids, then
  SelectEpisode(index). Rows = ScrollBox_List children (TB_text_ON upper case, Locked,
  img_Clear visibility 0 = cleared). Episode intro/ending text comes through the subtitle reader.

## Testing notes
- Keyboard in fights belongs to whichever device pressed a button at the title. If a
  controller pressed first, keyboard works in menus but not in battle (B, arrows).
- Practice pause key on keyboard: B. Esc on the main menu jumps to the shortcut bar.

## Measured key-to-speech (helper log)
Main menu rows 65-85 ms, tabs ~40 ms, character names 9-64 ms, stages 21-35 ms,
dialog buttons 28-51 ms, move list 16-75 ms, practice rows 100-170 ms (deferred one
tick), practice Enter/Esc column change 250-480 ms. Old 0.6: 150 ms poll + file outbox.

## Not done / unverified
- Arcade Quest: story/battle talk (WBP_UI_TAM_Talk_C) not yet seen in game; the "!" icon texture
  over a head is not known (unknown icons are logged "TAM icon"); campaign chapters (other maps)
  not tested, only the post-campaign ghost arcade (TAM_Ghost_PL).
- Keyboard key names for kbd_ icons; Roger Jr. id; story fighter names.
- Beacon only uses the camera frame; no wall cues yet. Ball cue untested by ear.
- The keyboard is ignored at the title screen after a restart while a controller is plugged in
  (every restart on 2026-10-29): someone has to press a controller button there. The attract
  movie (WBP_UI_StoryMoviePlayer_C, not in viewport) needs Esc; t8.py boot presses it.

## Story mode special screens (story.lua, 2026-11-11)
- Button prompts: WBP_UI_Story_STE_Menu_C:SetupButton(index, type, textId, texture, "{gui_use}") per
  button, then AnimIn; AnimSuccess / AnimMiss end it (window ~5 s). Button_0N.TB_Btn = key picture
  (kbd_NNN) on keyboard, Rep_T_UI_STE_BTN texture (T_UI_STE_BTN_PS5_SQUARE / _XSX_X) on a pad;
  TB_GuideText = action. Texts TEXT_000_UI_MAINSTORY_INGAME_CMD_001..011 (Dodge, Block, Punish,
  Counter, Follow-up attack, [Hold] Get up, Wind God Fist, three "I will not deny..." lines, Demon's Paw).
  Spoken "U key, Punish. Or A key, Dodge." + tones open / round (success) / drop (miss).
  Seen in game: Chapter 1 round 1 (Punish / Dodge). Guides: also Ch 5 (Leroy), 14, 15 (hold, mandatory).
- Fighter choice: Chapter 5 tournament, WBP_UI_Story_TwoChoices_C (PlayAnimIn twice, second has names),
  SelectItem_L/_R PlayAnimHover = cursor, ProfList rows. Tested: question, names, profiles.
  The fighter under the cursor when the screen closes is the one you play, and the game puts it on
  its own side (picked King on the right -> King is PlayerNumber 1). story.lua keeps the name in
  Story.chosen; fight.lua start() makes the matching fighter "me" and skips resolve_side; the first
  fight without that fighter, chapter select or the main menu clears it.
- Story fights show WBP_UI_HUD_S2 during the intro scenes. PolarisBlueprintLibrary IsBattleMain
  (no args) turns true when the round starts (Ch5: HUD 23:51:20, IsBattleMain 23:51:22.8 with the
  first attack); IsMatchRound is true already with the HUD. In story mode (IsStoryMode) the beacon,
  attack and throw cues wait for IsBattleMain; other modes still start with the HUD. Called
  through a whole fight load by tools sampling at 4 Hz with no trouble. Not yet checked in the
  early chapters where the user heard the beacon long before the fight.
- Story fight end: both health bars read 0 in one tick as the fight is torn down; health() says
  nothing then (it said both K.O. lines).
- Chapter 10: WBP_UI_HelpDialog_C tutorial pop-up (2 pages, O/P turn, K closes; UpdateCursor(page)),
  IW MessageWin FrameIn (radio line) and NoticeWin FrameIn. No beacon there: the HUD is
  WBP_UI_Story_IW_HUD_C, not HUD_S2, so fight.lua is idle (open item).
- WBP_UI_HUD_ControlGuide_C:SetButtonData(side, row, "{gui_bank0_LP}", textId, kind) = the control list
  of story fights; Shift+F5 reads it.
- Maintenance does not run during story movies; preload() now marks its classes ready at once.
- Not yet run in game after the last build: prompt speech, pop-up, radio lines, Shift+F5, the pad
  button names, DLC story (WBP_UI_Story_DLC_C timeline menu is unread). tools: story_spy.lua,
  story_classes.lua, story.py, watch.py, fightwatch.py.

## Button names (lib/pad.lua, 2026-11-11)
- Prompts speak pad buttons even when the game draws keyboard keys. Style: Xbox (default),
  PlayStation, or keyboard keys; Shift+F11 cycles, saved in Mods\TekkenA11y\pad.txt.
- Pad pictures in rich text: <img id="btn_LB_xsx"/>, btn_A_ps5 (Xbox letters + family; LSB/RSB =
  stick clicks). Hidden guide widgets keep a ps5 default picture with an Xbox pad, so the style is
  never guessed from pictures.
- Keyboard to pad, read off the main menu guide bar with keyboard and then pad: U I J K = X Y A B
  (1 2 3 4), O P = LB RB (tabs, help pages), L ; = LT RT (banner), C = left stick click (Tekken
  Shop), N = right stick click (Hide UI), WASD/arrows = directions. B = Menu button (pause) is
  inferred, not seen. Unmapped keys (V, Insert, Home ...) are still said as keys.
- kbd_NNN: NNN = scan code, +128 for extended keys (210 Insert, 199 Home, 200 Up arrow).
- After a pad press Tekken 8 ignores the keyboard in menus too (even after a restart); bot tests
  need the pad unplugged.
- CRASH (2026-11-11): pause during a story movie, Skip Movie, game gone ~12 s later as the fight
  loaded, no report. The movie's WBP_UI_Pause_C was kept (menus.lua pause_found, fight.lua
  menus.pause) and polled after it was destroyed. Fix: fight.lua forget_widgets() drops every kept
  widget (pause, practice HUD, battle HUD, TwoChoices) whenever the fight HUD comes or goes;
  pause_seen no longer checks a kept widget. Survived the same path 4 times after the fix.
- Help dialog: Pages/Marks are maps (no count in UE4SS); "page button visible" = more pages.
  UpdateCursor fires just before PlayAnimIn (was read twice). Chapter 10 resumes at a checkpoint
  on replay, so the 2-page "Operation Rebellion" pop-up only shows from the chapter start.
- Main menu Hide UI (N / right stick click) leaves no widgets and the mod silent; not announced yet.

## Attack height (helper/attack.c, 2026-11-11)
- Nothing in UObjects or PolarisBlueprintLibrary gives the hit level (GetFighterAttackingDamageValue
  is plain damage plus the 0x4000 throw bit). The fight data is native; the helper reads it with
  ReadProcessMemory on its own thread, so the game thread does nothing new (fight frames stayed
  16.7 ms avg, 22 ms max during the test).
- [exe + 0x9b90bc0] -> battle object; +0x30 / +0x38 = block of PlayerNumber 0 / 1 (checked from both
  sides). Block: +0x168 char id (6 Jin, 8 Kazuya), +0x511 attack type dword (TekkenBot's 0x4f1 moved
  by 0x20: 0xa00005 high, 0x800002 mid, 0x200001 low, 0x600004 special mid, 0xc00007 unblockable,
  0x60000a throw, 0xc00000 recovering), +0x550 move id (0x8001 standing; new id per move),
  +0x3540 and +0x35c0 point back at the block.
- The exe offset changes with patches: attack.c scans the exe's writable data for a pointer whose
  +0x30/+0x38 are two blocks (60-80 ms), caches it in Mods\TekkenA11y\attack_root.txt with the PE
  build stamp, and retries every 3 s while the fight is still loading. If the block layout itself
  moves, the log says "no battle object found": find the offsets again with tools/memscan.py (pause
  Practice mid-move, find 0x00800002, keep 0x00200001) and tools/ptrchain.py.
- The type is set as the move starts (df+1: ~0.22 s before IsFighterAttacking). Mod: "A n" while a
  fight is on and no menu is open, "A0" otherwise (fight.lua attack_set).
- Practice: Opponent Actions = Mimic makes the dummy copy your moves at once (useful for tests;
  resets when the game restarts). The Practice HUD's "Hit Properties" line shows the same data.
- Modes (Shift+F2, Mods\TekkenA11yttack_mode.txt): opponent / own / both / off. Mod sends
  "A me mode" (mode bits 1 opponent, 2 own); own attacks pan to -opponent pan at 0.6 volume.
  All four checked in Practice with a Mimic dummy (2026-11-11).
- Not tested: online (rollback), sounds by the user's ear, levels against game audio.
- Patch of 2026-11-11 17:39 (PE stamp 6adb1ad5): root moved to exe+0x9be1ba8 and the back pointers
  to +0x3600 / +0x3680 (were 0x3540 / 0x35c0); +0x168, +0x511, +0x550 and the +0x30/+0x38 pair
  unchanged. attack.c now tries the known offsets, then searches 0x3000-0x4000 of the block for
  a pointer to itself repeated 0x80 later (fighter id < 200 as a check), and keeps the offset as a
  third field in attack_root.txt.
