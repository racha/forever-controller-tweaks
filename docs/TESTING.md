# Testing Forever Controller Tweaks in game

The specs (see [CONTRIBUTING.md](../CONTRIBUTING.md)) cover the logic. This checklist covers what only the game can show. Run the parts your change touches. Run all of them before a release.

## Setup

1. Link or copy `ForeverControllerTweaks/` and its three `ForeverControllerTweaks_*` module folders into `_forever_/Interface/AddOns/`. **Restart the game completely** after adding new files.
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
2. **Minimap button** and the minimap **AddOns** menu open the settings. Hide the minimap button from More, and show it again.
3. **Options:** open Options and type in its search box. No "blocked" message or popup names this addon, and the AddOns list in Options has no Forever Controller Tweaks page. From the Game Menu, Log Out (then cancel) and Return to Game still work.
4. **Navigation:** the D-pad moves the focus everywhere, and holding it repeats. The sticks don't move it. L1/R1 switch Bindings → Touch → Keyboard → Rings → Tweaks and back. Every footer lists working buttons.
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

## H. Rings

1. Build a ring of 8 slots and put **Open ring** on a face cell and on a D-pad cell. A new ring aims with the **Right** stick.
2. The ring looks like the game's own radial menu: the wheel only, no title or band.
3. **Show: Toggle.**
   - Press the button: the ring opens. Flick the stick to a slot and let the stick go: it fires and the ring closes.
   - Open it, aim, press **Cross**: it fires.
   - Open it and let go of the button with the stick centred: the ring stays open. Circle, a stick press or the button again closes it, and nothing fires.
4. **Show: Hold.** The ring shows only while the button is held. Let go while aiming: it fires. Let go with nothing aimed: it closes and nothing fires.
5. Let go of the button and the stick at the same moment: the slot fires once.
6. Aim at every diagonal in turn. No direction sticks, and the next open starts clean.
7. **Stale pick:** push the stick to a slot first, then press the ring's button. That slot isn't lit and doesn't fire. Centre the stick or move it to another slot, and that one works.
8. Repeat 3 and 4 in combat. After a ring closes, the aiming stick doesn't walk you or turn the camera until it's centred.
9. **Style: Compact.** Set a ring to Compact in the tab: the preview and the ring in game look like the game's radial flyout (a paladin's aura picker): the round base, the icons in round slots and an empty socket where a slot is empty, no names. Aiming lights the slot, turns the indicator towards it and points the arrow at it.
   - Open it from a face cell and from a D-pad cell, each on two layers (no modifier and a modifier, say L2 + R1). It opens centred on that crossbar button, with the ring's icon in the middle and the layer's modifier glyphs under it (none on the base layer). Known gap: a ring on a face cell's base layer opens in the middle of the screen.
   - Change the UI scale and open it again: still on the button. Each slot points the same way as in Full.
   - Try it with Show Toggle and with Hold, out of combat and in combat.
   - Open it from a touch button and click a slot with the mouse: the slot under the pointer fires.
   - In combat, open a Compact ring, close it, then open a Full ring (and back): each ring's slots click where they're drawn.
10. `/fct ringlog` prints the last ring events.

## I. Keyboard and chat

1. **Keyboard tab:** On, Open, Layout, Scale and Word suggestions, one per row. **Reset keyboard to defaults** is in More. Compact shows each set's letters.
2. **Quick messages:** open it from the Keyboard tab.
   - The situations are on the left and their lines on the right; left / right switch columns.
   - Add a line with the on-screen keyboard: Send saves, Close cancels. The suggestion list offers fill-ins such as `{target}` with their current value.
   - Edit, move and delete your own line. Square on a built-in line hides it; **Restore** brings it back.
   - Your line comes first in that situation's suggestions.
3. **Sending chat**, with the on-screen keyboard. After each Send the keyboard closes, the chat box stays open and empty, and one more Circle closes it:
   - **say** (`/s`);
   - **party** (`/p`, in a group);
   - **guild** (`/g`);
   - a **whisper** (`/w Name`);
   - a **reply** (`/r`) to a whisper you got.
   Each line arrives once, on the right channel. Try both Chat Styles (Options → Social): Classic and IM both send.
4. **In combat:** party, guild and a whisper send. A say line stays in the box with a note; send it after the fight.
5. After all of the above, `/reload`. `Logs/taint.log` with `/console taintLog 2` has no line naming ForeverControllerTweaks.

## J. Tweaks

Turn each tweak on in the **Tweaks** tab, try it, then turn it off again. Every one is off on a new install.

1. **The tab:** four columns. Up / down move within a column. Left / right change a dropdown or slider, and at its end move to the next column. Triangle opens More. Tooltips stay beside their row.
2. **Bags & vendors:** the Sort button on the combined bags' title bar (and on separate bags), not over the search box. At a merchant: junk sells and one chat line lists the items; gear repairs, from guild funds first when allowed. **Buy a full stack** buys a stack; on a sold-out item it says so.
3. **Quests & NPCs:**
   - a flight master, vendor or banker with one option opens that service;
   - an NPC with a single chat-bubble option (a teleport, an event, a story skip) is left to you;
   - Learn all at a trainer; Open all at the mailbox.
4. **Group & social:** a guildmate's invite is accepted; the same invite while you're queued for a dungeon or battleground is left to you. A friend's summon is accepted outside an instance and left to you inside one. A duel is declined. A whisper shows its card.
5. **Loot & gear:** fast loot, an upgrade arrow on a better piece in the bags and the loot window, Pass on an item your class can't use, and the reward card after a quest (hold Triangle to wear).
6. **Picker actions:** put each new action on a button and use it: Cancel, the potions and grenade (in combat too), Look behind and Peek map (hold, then let go), Mark next (in combat too), Eat & drink, Quest item, Track nearest quest, Ready check, Pull countdown and Minimap zoom.

## K. Rumble, light bar and battery

1. **Rumble:** turn on **Rumble on events**. Cross on **Strength** plays a Double tap; change the strength and press again. Cross on each group's row plays its pattern. Off silences a group.
2. Trigger a few events: a whisper (twice in quick succession: one rumble), a ready check, a trade request, a level up. Each plays its group's pattern. With **Procs** set to a pattern and not in a group: critical hits on an enemy target rumble, at most once a second; normal hits, and crits while in a group, don't.
3. **Light bar** (a pad with a light bar, such as a DualSense, not over Steam): Class colour, Custom with each colour, and Combat flash (red in combat). Game default gives the light back.
4. **Battery:** on a wireless pad that reports its charge, the battery button sits on the minimap's ring with the other buttons and shows the charge. Unplug or switch pads: it follows. The low-battery line shows once when the charge drops.

## L. Next to Controller Forever

1. Install Controller Forever next to this addon, both enabled, and log in.
2. No Lua error and no "blocked" message from this addon. `taint.log` has no line naming ForeverControllerTweaks.
3. Note which addon's layout is active, and that both keep working as far as they can (don't change both addons' layouts at once).

4. Disable this addon and restart: Controller Forever's own setup is back and works.
5. Report what you saw, with the `/fct selftest` lines.

## M. Healer mode

Best in a party of five, then in a raid group. Turn on `/console taintLog 2` first.

1. **Switch:** in **Bindings**, focus a cell holding a heal and press **Triangle**. **Healer mode: Off** is the first row in More, with the green cross. Pick it: More closes and the cell gets the green cross at its top right. Its tooltip says **Healer mode: On**. Triangle again shows **Healer mode: On**; picking it turns it off.
   - Do this on a face cell's base layer, a D-pad cell, a cell on a modifier layer (a native crossbar slot), a paddle without a role, and a touch button (**Touch** tab, Triangle on a cell).
   - On a mount, a macro, a game action and an empty cell the row is grey with **Spells and items**; its tooltip says what the button holds. Picking it changes nothing.
   - Turn it on for a native crossbar cell, then off: the slot's spell is still there and casts on your target again.
2. **In play:** the crossbar cell (and the touch button) shows the same green cross.
3. **The ring:** hold the button. A small round ring opens on that crossbar button, with the spell in the middle: You at the top, then Party 1 to 4, Target and Focus clockwise. Each place has the unit's round portrait, a health ring in its class colour and its role icon. An empty place is a dim empty socket.
   - It aims with the right stick on a D-pad button and a paddle, the left stick on a face button.
   - Aim at someone: the gold border, the indicator and the arrow point at them, and the game's own tooltip for that unit shows at the bottom right.
   - Let go: the spell lands on that unit, not on your target. Let go in the middle: nothing is cast.
   - Aim at an empty place, a hostile target or no focus: no border or arrow, nothing cast. A hostile target's place is grey and dim, its ring red, and the tooltip still names it.
   - A dead ally is grey with a skull, and can be picked: a resurrection lands on them.
   - On a touch button: a tap opens the ring, a tap on a place casts there, a tap on an empty place does nothing.
4. **In combat:** repeat 3. The health rings move as people take damage and get healed, and party changes in combat follow.
5. **Health ring extras** (all new and checked here first):
   - **Health:** the ring fills clockwise from the top. Note if it starts elsewhere or runs the other way.
   - **Incoming heals:** start a slow heal on someone: a teal stretch continues the health ring and never runs past the top.
   - **Shield:** shield someone (Power Word: Shield): a thin outer arc from the top.
   - **Heal absorb:** if a fight puts a heal absorb on someone, a darker stretch at the end of their health.
   - **Critical:** under 30% health a red glow behind the place pulses about once a second; above 30% it's gone.
   - **Dispel:** on a class that can dispel, a debuff you can remove gives the place a tinted glow and its type icon (Magic blue, Curse purple, Disease orange, Poison green) at its bottom right. On a class that can't, no tint.
6. Take screenshots of the ring with a full party, in combat, and with one of each extra.
7. After all of the above, `/reload`. `Logs/taint.log` has no line naming ForeverControllerTweaks; write down any that does (above all one near GameTooltip or the healer ring).

## Reporting results

In a pull request or issue, list the parts you ran and the controllers you used, and say whether `taint.log` was clean. Attach screenshots of anything that looks wrong, with character names and chat cropped out.
