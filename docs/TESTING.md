# Testing Forever Controller Tweaks in game

The specs (see [CONTRIBUTING.md](../CONTRIBUTING.md)) cover the logic. This checklist covers what only the game can show. Run the parts your change touches. Run all of them before a release.

## Setup

1. Link or copy `ForeverControllerTweaks/` into `_forever_/Interface/AddOns/`. **Restart the game completely** after adding new files.
2. Turn on **Enable Gamepad UI (Beta)**, and turn off any other addon that writes the controller config.
3. In chat:
   - `/fct selftest`
   - `/console taintLog 2`
   - `/console scriptErrors 1`
4. When you finish, `/reload`, then check `Logs/taint.log`. **No line may name ForeverControllerTweaks.**

**Every part must also show:** no Lua error, no "Blizzard blocked …" chat line from the addon, and no "blocked from an action" popup.

## A. Layout, glyphs, combat

1. Choose **Left = bars, Right = targeting**, in the first-start guide or with `/fct preset split`.
2. Each hold opens the right thing:

   | Hold | Opens |
   |---|---|
   | L2 | left bar |
   | L1 | right bar |
   | L1+L2 | bottom bar |
   | R1 | friendly targeting |
   | R2 | hostile targeting |
   | R1+R2 | shortcuts |

   Cast a spell from two different bars.
3. **Glyphs:**
   - under the bars, L1 shows for the right bar and L2 + L1 for the bottom bar;
   - the on-screen hints show R1 as friendly and R2 as hostile;
   - the right targeting marker is split, green on top and red below;
   - nothing flashes for a frame.
4. With bags or talents open, L1/R1 switch tabs as normal.
5. **Open the settings, then start combat.** The window closes. During the fight L1 still opens the right bar and R2 still targets enemies. After combat, the addon offers to resume.

## B. Opening and navigation

Use only the controller for this part, except where a step names Options.

1. **Shortcut:** hold L2 + R2 and press Create (PlayStation) or View (Xbox). The settings open on **Bindings**. The same press closes them. Create or View alone, without the triggers, still does what the game does.
2. **Minimap button** and the minimap **AddOns** menu open the settings. Hide the minimap button from Modifiers → More, and show it again.
3. **Options → AddOns → Forever Controller Tweaks:**
   - **Open Settings** opens the settings, and Options goes invisible underneath. Close the settings: Options is visible and usable again;
   - **Run setup guide** starts the first-start guide;
   - from the Game Menu, Log Out (then cancel) and Return to Game still work;
   - nothing is blocked afterwards.
4. **Navigation:** the D-pad moves the focus everywhere, and holding it repeats. The sticks don't move it. L1/R1 switch Bindings → Modifiers → Touch and back. Every footer lists working buttons.
5. **Look:** every window, dialog, tooltip and footer matches the game's own windows. At UI scale 1.15 and at 1280×800, nothing is cut off.

## C. Bindings and the picker

1. **Rows:** the focused row draws a gold line to its button on the drawing. "Page 1 of 3" shows in the header, and L2/R2 switch pages.
2. **Picker:**
   - L1/R1 switch categories, L2/R2 page, Circle closes;
   - a greyed entry explains itself when selected;
   - assign a spell, an item, a mount, a toy, your own macro, and the game actions Bags, Map, Target nearest enemy and Extra action;
   - each one shows on the crossbar and works;
   - Square clears a cell, and Triangle undoes the clear.
3. **Any button, any bar:** put a spell on a D-pad cell of the left bar, Jump on a D-pad cell of the right bar and Interact on a face cell of the bottom bar. Then:
   - each fires from its bar;
   - the moved spell shows its cooldown, range, mana and proc glow, its tooltip, and works with a mouse click;
   - Interact works on an NPC, and holding it on a corpse loots;
   - Jump works, and holding it in water swims up;
   - after opening and closing your bags, all three still work.
4. **Interact notice:** moving Interact shows a one-time notice about the world prompts. The prompts keep the game's default button. Options → Accessibility → Interact Key Icons → None hides them.
5. **Spell ranks:** a spell with several ranks opens its ranks page. Assign **Highest Rank**, learn a new rank (or use a character who can), and the cell casts the new rank. Assign a fixed low rank: it stays.
6. **AddOns:** with another addon that registers key bindings (for example WellMet), assign one of them from the **AddOns** category, and it works from the controller.
7. **Hidden slots:** with a keyboard, show action bars 6–8. Moved actions sit in slots 145–180 and use only slots that were empty. Clearing a cell frees its slot.
8. **Macros:**
   - `FCT:` macros exist;
   - a macro you create named `FCT:test` survives everything below;
   - on a second character, assign Bags, then log back: both characters' actions still work.

## D. Touch bars

1. Touch bars are off on a new character. In the **Touch** tab, turn them on.
2. Set 6 buttons per bar, change the size, spacing, distance from the edge, up / down and opacity. The preview and the real bars follow each change.
3. Assign a spell and an item to touch buttons. Click them with the mouse (or tap them over Steam Link): they fire, and show cooldowns and range like native slots.
4. Show: **In combat** shows the bars only in combat. **Gamepad UI** hides them when the Gamepad UI is off. **Never** hides them.
5. The bars work in combat, and settings changes are refused in combat with a chat line.

## E. Lifecycle

1. `/reload` in combat. After login, a chat line says the controller config was cleaned up, and the holds work.
2. Turn the Gamepad UI off. Glyphs and bumpers go native. Turn it back on: the layout returns.
3. Unplug and replug the controller: the layout returns.
4. `/fct release`: the addon's slots on keyboard bars 6–8 are empty and the `FCT:` macros are gone. Your own macros and slots stay.
5. Disable the addon and restart. The controller is fully native, and `WTF/GamePadConfig_Addons.json` has no entry from the addon.

## F. Controller type and setup

1. `/fct family reset`, then log in again (or `/fct setup`): the four controller type cards show. On Steam Link, Xbox is marked Suggested.
2. Pick **Not now**, `/reload`: the guide doesn't ask again for this controller.
3. Pick **Xbox**: glyphs and drawing switch to Xbox. `/fct family reset` puts it back.
4. Run `/fct detect` and do every step. It asks before it starts, because it needs a keyboard or mouse.
5. Skip a step with Space. Press one button twice: the message names the step that already uses it. Use Backspace once. Save with Enter.
6. Finish with a glyph style, then choose a layout. Part A steps 2–3 still pass.
7. Reset detection: the pad behaves as before.

## G. Other controllers

Repeat part A, steps 1–3, and part C, step 3, on every controller you have: Xbox, a Steam Input pad over Steam Link, Switch Pro, a pad with paddles, Steam Deck. Note in your report which controllers you used, with the lines `/fct selftest` prints.

## Reporting results

In a pull request or issue, list the parts you ran and the controllers you used, and say whether `taint.log` was clean. Attach screenshots of anything that looks wrong, with character names and chat cropped out.
