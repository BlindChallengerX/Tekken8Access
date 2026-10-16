# TekkenA11y developer notes (rebuild 0.7.0, 2026-10-16, game ver. 3.02.02)

## Layout
- `mod/Scripts` - UE4SS Lua (main, out, menus, fight, data, lib/ui, lib/notation, dev).
- `helper/` - TekkenA11yHelper.exe (C, 64-bit w64devkit): named pipe `\\.\pipe\TekkenA11y`,
  Prism speech (speech.c from SC2 Access), waveOut synth (audio.c from SC2), beacon.c.
- `build.sh` (Git Bash) -> `out/TekkenA11y`; `deploy.ps1` copies into the game's Mods folder.
- `tools/` - t8.py (dev console client, keys, screenshots, boot/flow helpers), lat.py
  (key-to-SAY latency), flow.py (main menu -> practice match), discover.lua (hook every
  hover-like Blueprint function and log calls), sweep_names.py, icon_rows.py, restart.ps1.
- `old-v0.6/` - the June build this replaces (file outbox + external speaker, polling).

## Dev console
Create `Mods\TekkenA11y\dev.txt`; `python tools\t8.py lua "return 1"` or `luaf file.lua`
runs Lua on the game thread, `--async` first line runs it off-thread. Output in
%TEMP%\TekkenA11y\out.txt. Helper log (SAY lines with ms times): %TEMP%\TekkenA11y\helper.log.

## UE4SS 3.0.1 rules learned the hard way
- Never hook native `/Script/...` functions with a Lua callback: the Lua thread froze.
- Call RegisterHook only on the game thread (from an async loop it deadlocked when a hook
  fired at the same time).
- Do not call ExecuteInGameThread from inside a hook callback (froze); use Menus.defer,
  run by the 40 ms game-thread tick.
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
- Pause menu (other modes): `WBP_UI_Pause_MenuButton_C:Select` - not tested in game yet.
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

## Testing notes
- Keyboard in fights belongs to whichever device pressed a button at the title. If a
  controller pressed first, keyboard works in menus but not in battle (B, arrows).
- Practice pause key on keyboard: B. Esc on the main menu jumps to the shortcut bar.

## Measured key-to-speech (helper log)
Main menu rows 65-85 ms, tabs ~40 ms, character names 9-64 ms, stages 21-35 ms,
dialog buttons 28-51 ms, move list 16-75 ms, practice rows 100-170 ms (deferred one
tick), practice Enter/Esc column change 250-480 ms. Old 0.6: 150 ms poll + file outbox.

## Not done / unverified
- Regular pause menu in Arcade/Versus/Story; story subtitles (old 0.6 had a poll).
- Keyboard key names for kbd_ icons; Roger Jr. id.
- Beacon only uses the camera frame; no wall/ring cues yet.
