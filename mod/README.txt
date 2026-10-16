TekkenA11y 0.7.0 - screen reader and audio cues for Tekken 8
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

Keys
----
F5   distance and health
F6   opponent beacon on / off
F7   repeat the selected move with its notes
F8   repeat the last thing said
F9   read everything on screen
F11  speech on / off

Uninstall: delete the TekkenA11y folder above.
