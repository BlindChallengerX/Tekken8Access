TekkenA11y 0.7.1 - screen reader and audio cues for Tekken 8
=============================================================

Speech goes through Prism (NVDA, JAWS and others, or the Windows voice if no
screen reader runs). A small helper program, speaker\TekkenA11yHelper.exe,
starts and stops with the game by itself.

Needs UE4SS for Tekken 8 in ...\TEKKEN 8\Polaris\Binaries\Win64\ (already
installed on this PC). This folder lives in
...\TEKKEN 8\Polaris\Binaries\Win64\Mods\TekkenA11y\

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
- Arcade Quest talk and tutorial captions, Tekken Ball ball and damage info.
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
- Tekken Ball: a short dry tock for the ball. Panned to its side, higher
  when the ball is higher in the air (whole steps from the floor up to
  about 3.5 meters), ticking faster as it gets closer. F5 also says how far
  the ball is, which side, and whether it is low, chest high or high.

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
F3   subtitles on / off
F4   Tekken Ball sound on / off
F5   distance and health (and the ball in Tekken Ball)
F6   opponent beacon on / off
F7   repeat the selected move with its notes (in a combo challenge: its steps)
F8   repeat the last thing said
F9   read everything on screen
F2   throw break sounds on / off (F10 is taken by the UE4SS console)
F11  speech on / off

Uninstall: delete the TekkenA11y folder above.
