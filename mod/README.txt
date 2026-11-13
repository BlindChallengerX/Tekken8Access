Tekken 8 Access 1.0.1 - screen reader and audio cues for Tekken 8
=================================================================

Speech goes through Prism (NVDA, JAWS and others, or the Windows voice if no
screen reader runs). A small helper program, speaker\TekkenA11yHelper.exe,
starts and stops with the game by itself.

Install
-------
1. Open the Tekken 8 folder: in Steam, right-click TEKKEN 8, Manage,
   Browse local files. Go into Polaris, then Binaries, then Win64
   (the folder with Polaris-Win64-Shipping.exe).
2. Extract everything in the zip into that Win64 folder. Say yes if asked
   to replace files. The zip brings UE4SS 3.0.1 (the mod loader, MIT
   licence, github.com/UE4SS-RE/RE-UE4SS) and this mod, which ends up in
   Win64\Mods\TekkenA11y\.
3. Start Tekken 8 from Steam as usual. Speech starts at the title screen.

What is read
------------
- Main menu: tabs (switch with the tab keys) and every row as you move.
  Descriptions from the bar at the bottom are read when you stop on an item.
- Side select (left / right side).
- Character select: the fighter's name at once, then fighting style,
  nationality, height and weight when you rest. The other side's cursor is
  said as "Opponent: name". Picking says "name selected".
- Stage select: stage names, and Random.
- Practice pause menu (B on the keyboard): every column, sub-option and value
  list, then the help line.
- Pause menu in other modes, Yes/No dialogs, most other menu rows.
- Jukebox: the album carousel (series, All, My Playlists; "selected" marks
  the one playing), series tabs, track and stage music lists, preset options.
- Story and cutscene subtitles are read as they appear (F3 turns them off).
- Tekken Ball ball and damage info.
- Button prompts use controller names even when the game shows keyboard
  keys: "X button, Punish. Or Left, Dodge." Xbox names by default; Shift+F11
  switches to PlayStation names (Square, Cross ...) or to the keyboard keys
  themselves, and the choice is remembered.
- Story mode: timed button prompts (with a tone when they open, a success
  tone and a miss tone), the Chapter 5 fighter choice, Chapter 10 radio lines,
  notices and tutorial pop-ups. Shift+F5 reads the control list shown in
  story fights. The fighter you pick in Chapter 5 is the one the beacon
  and sounds treat as you, and in story fights the beacon and attack
  sounds start when the round starts, not during the intro scene.
- News (Information): the game opens it after the title when there is news,
  or from the main menu's shortcut bar (Esc, then News). Each headline is
  read with "new" if unread and its place ("2 of 8"); Enter reads the whole
  article and its buttons (Store, Close). The Log tab and notices that pop
  up (friends, unlocks) are read too. Dialogs on the title screen
  ("Connecting to the server") are read now as well.
- Move list and sample combos: number, move name and the command in Tekken
  notation (d/f+1, hold f, 1+2 ...), then notes and damage when you rest.
  "then" marks the next part of a string or combo.

Fights
------
- "Name versus name" when the fight starts; half health, low health, K.O.
- Opponent beacon (after Mist World): two soft beeps. The first note never
  changes. The second note is the same when the opponent is square-on,
  higher when they are in the background (up the screen) and lower when in
  the foreground: one step for a sidestep, two steps when they are well off
  to the side. The beeps are panned to their side and come faster as they
  get closer.
- The beacon pauses while a pause or practice menu is open.
- Online the mod finds your side by your online ID on the fight HUD. It
  learns your ID from any offline fight where you picked a side (Practice
  is enough), so play one Practice match before going online. When you are
  on the right side online it says "You are on the right."
- Throw break sounds. In Tekken 8 a plain throw (1+3 or 2+4) breaks with
  1 or 2, either one; 1+2 does not break it. Command throws can need 1+2
  (or only 1, or only 2).
  In matches: when the opponent starts any throw you hear one low note:
  press 1. The game gives the mod no way to tell a 1+2 command throw from
  a plain one, so those also play the low note.
  In Throw Escape Training the mod reads the game's escape tip and plays
  the exact sound as the grab lands: low note = 1 (or 2), two quick high
  notes = 2, a fast high trill = 1+2. Use it to learn which of a
  character's throws need 1+2. Throws from behind can't be broken.
- Attack height sounds: as each of the opponent's attacks starts you hear
  how to block it, panned to their side. High = a high note with a bright
  rising whoosh (duck it), mid = a middle note (block standing), low = a low
  note with a falling whoosh (block crouching), special mid = the middle note
  then the low one (blocks either way), unblockable = a low buzz (get away).
  The sound comes as the move starts, before it hits (about a fifth of a
  second ahead for a quick mid). Throws keep their own sounds.
  Shift+F2 chooses whose attacks you hear: the opponent's (the default),
  your own, both, or off; the choice is remembered. Your own attacks play on
  your side and a little quieter, so the opponent's stand out when both are
  on. Ctrl+F2 plays each sound with its name.
- Walls: soft hums that grow louder as a wall gets closer.
  Wall behind you: a low hum on your side of the screen, from about 2.5
  meters away. Wall behind the opponent (you can carry them into it): the
  same hum a little higher and quieter, on their side, from about 2 meters.
  Sidestep walls: a pulsing hum, higher for a wall up the screen (sidestep
  up), lower for a wall toward the camera (sidestep down), from about 1.5
  meters; when the pulse turns fast, sidestepping that way is blocked.
  On stages with floor or balcony breaks the mod follows the floor you are
  on. F5 says the distances ("Wall behind you 1.2 meters ... Sidestep up
  blocked"), and names balconies and breakable walls. Ctrl+F6 turns the
  wall sounds off and on.
- Tekken Ball: a short dry tock for the ball. Panned to its side, higher
  when the ball is higher in the air (whole steps from the floor up to
  about 3.5 meters), ticking faster as it gets closer. F5 also says how far
  the ball is, which side, and whether it is low, chest high or high.

Arcade Quest
------------
- You walk your avatar around the arcade. F1 picks the nearest person or
  machine and says how far and which way ("Max, 2 meters ahead"); press F1
  again for the next one, Shift+F1 to go back. Ghosts with a treasure chest
  say "treasure".
- The opponent beacon then points at your pick: the same two soft beeps as
  in fights, panned to its side of the screen, second note higher when it
  is ahead of you (up the screen) and lower when behind, faster as you get
  closer. It goes quiet once you are in reach and while a talk window, Max's
  menu or the arcade map is open. F6 turns it off.
- When you are close enough you hear a short tone and the name with the
  game's prompt ("Max, Numpad 4 key, Talk"), or "in reach" when they are out
  of the camera's view (the game hides the prompt then; the key still works).
- Talk lines are read with the speaker's name. The objective is read when it
  changes; F5 says it again with where your pick is.
- Max's menu reads each row and then his line about it; the arcade map
  (Head Out) reads each arcade, and "locked".
- The pause menu in Arcade Quest is B on the keyboard.

Character Episodes
------------------
- The character list reads each name with "cleared" or "locked", then full
  name, fighting style, country, height and weight when you rest.
- The episode's story text and spoken lines are read as subtitles.

Throw Escape and Punishment Training (Practice pause menu)
---------------------------------------------------------
- The left column reads the difficulty, the right column each move with its
  command; in Throw Escape Training also "on" or "off" (whether the dummy
  uses that throw; Enter switches it).

Combo Challenges (Practice pause menu)
--------------------------------------
- The list reads each challenge (and "cleared" once you have done it), then
  its steps in Tekken notation, difficulty out of 5, damage and the note.
- When a challenge starts you hear its steps once. While you play:
  a short tone each time a step lands (higher for each later step), a low
  falling tone when the combo drops back to the start, a rising chime and
  "Challenge cleared!" when you finish.
- F7 repeats the steps and says "Next:" before the one you are on.
- The opponent beacon follows the challenge dummy.

Keys
----
F1   Arcade Quest: next person or machine (Shift+F1: previous)
F3   subtitles on / off
F4   Tekken Ball sound on / off
F5   distance and health, then the walls (and the ball in Tekken Ball; in
     Arcade Quest the objective and where your pick is)
Shift+F5  story fights: read the control list
F6   opponent beacon on / off (also the Arcade Quest beacon)
Ctrl+F6  wall sounds on / off
F7   repeat the selected move with its notes (in a combo challenge: its steps)
F8   repeat the last thing said
F9   read everything on screen
F2   throw break sounds on / off (F10 is taken by the UE4SS console)
Shift+F2  attack sounds: opponent's, yours, both or off; Ctrl+F2 hear each one with its name
F11  speech on / off
Shift+F11  button names: Xbox, PlayStation or keyboard keys

Changes in 1.0.1
----------------
- Attack height sounds work again after the Tekken 8 update of
  11 November 2026 (it moved the fight data they read). If a later update
  moves it a little again, the mod finds it by itself.
- Story mode: the fighter you pick on the Chapter 5 choice screen counts
  as you (picking the right-hand fighter used to leave the beacon on the
  wrong fighter).
- Story mode: the beacon, attack sounds and throw tones wait for the round
  to start instead of playing during the intro scenes.
- No more "K.O." for both fighters when a story fight closes.
- New name: Tekken 8 Access (was TekkenA11y). The mod folder is still
  Win64\Mods\TekkenA11y, so extracting over 1.0 keeps your settings.

Uninstall: delete Win64\Mods\TekkenA11y. To remove UE4SS too, also delete
dwmapi.dll, UE4SS.dll and UE4SS-settings.ini from Win64.
