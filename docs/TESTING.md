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
2. **Bags & vendors:** the Sort button at the right end of the combined bags' title bar, where the close X would be (and on separate bags), not over the search box. It stays there after you pick up, move and use items in the bags many times, and after closing and opening them again. At a merchant: junk sells and one chat line lists the items; gear repairs, from guild funds first when allowed. **Buy a full stack** buys a stack; on a sold-out item it says so.
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

## N. 1.5.0

Turn on `/console taintLog 2` first.

### N1. Aim stick through a cast

1. Put a heal with a cast time of 2 seconds or more on a face button in Healer mode (it aims with the left stick).
2. Hold the button, aim at someone with the left stick, let go of the button and keep the stick pushed: the heal finishes. You don't walk while it casts.
3. Centre the stick mid-cast, then push it again: you walk and the cast breaks (the stick is free once it's back in the middle).
4. A channelled spell aimed the same way: held for the whole channel.
5. Out of a cast (an instant spell, or a slot that isn't a spell): the stick still walks you a second after the release at the latest.

### N2. A ring remembers the last pick

1. In the Rings tab, a ring with 4 or more slots: the new **Middle** row sits under Show and reads **Cancel**. D-pad left / right steps it, Cross cycles it, and its tooltip explains both values. The preview is a little smaller and Rename / Icon / Delete keep their place.
2. Set Show to **Hold** and Middle to **Use last**. Use a slot from the ring once.
   - The crossbar button, the Bindings cell and a touch button with that ring now show that slot's icon.
   - Open the ring: in **Full** the middle shows that slot's icon and name while nothing is aimed; aiming hides them. In **Compact** the centre shows that icon.
3. Hold the ring's button and let go in the middle: that slot fires. Do it in combat too.
4. Open it, press **Cross** with nothing aimed: that slot fires. **Circle** still closes without firing.
5. Show **Toggle**: the button's release only opens the ring; pressing the button again closes it. Cross with nothing aimed fires the last slot.
6. `/reload`: the icon and the middle release still use the same slot. Log onto another character: its own last pick (none yet).
7. Change or clear that slot in the Rings tab: the buttons show the ring's own icon again and a middle release fires nothing.
8. Middle **Cancel**: a middle release fires nothing and the buttons show the ring's icon, as before.

### N3. Healer mode: last target

1. Bindings, a cell in Healer mode, **Triangle**: **Middle: Cancel** is the second row, under Healer mode: On, with no icon. Its tooltip explains Last target. Pick it: More closes. Triangle again: **Middle: Last target**. On a cell with Healer mode off the row isn't there.
2. With Last target: heal Party 2 through the ring. Hold the button again with the stick centred: Party 2's place has the gold aimed border and the game's tooltip for Party 2, with no indicator or arrow. The ring's centre keeps the spell, and so does the crossbar button.
3. Let go in the middle: the heal lands on Party 2. In combat too.
4. Aim at someone else: the light moves there; back in the middle it returns to the remembered place.
5. Party 2 leaves the group (or the remembered place is Target and it's now hostile): nothing lights, and a middle release casts nothing.
6. `/reload`: the same place is remembered. Turn Healer mode off and on again: Middle is back to Cancel.
7. Middle: Cancel: a middle release casts nothing, as before.

### N4. Ring marker

1. Put Open ring on a face cell, a D-pad cell, a cell on a modifier layer and a touch button. Each shows the small flyout arrow at its top edge: on the crossbar, in Bindings, in the Touch tab and on the touch button. Compare it with a native flyout button (a paladin's aura or a mage's portals) on your crossbar.
2. Healer mode buttons show only the green cross, no arrow. Other actions show neither.
3. **Middle from the button:** on a Bindings cell and a touch button holding Open ring, **Triangle**: under the greyed Healer mode row, **Middle: Cancel** with a tooltip saying every button that opens this ring shares it. Pick it: More closes; Triangle again reads **Middle: Use last**, and the Rings tab's Middle row for that ring says Use last too (and the reverse). A button holding anything else has no Middle row; a Healer mode button keeps its own "Middle: Last target" row.
4. Open the ring (held, toggled and touch): the arrows of that ring's buttons hide while it is open and come back when it closes. In combat too.
5. Rings tab, the foot of "Your rings": **Arrow on ring buttons** is ticked. Cross unticks it: every arrow goes at once, in combat too after a `/reload`. Tick it again: they're back.
6. Take a screenshot of the crossbar with a ring button collapsed and expanded.

### N5. L3 / R3 cells and the sort bags key

1. Bindings: an **L3** row at the bottom of the left column and an **R3** row at the bottom of the right one (on an Xbox pad L3 sits higher, as on the drawing), each with four square cells and "L3 · TOP bar". With nothing on them, every cell shows the game's own action with its gold icon: **Auto-run** on L3, **Ping** on R3 (the row's name too); its tooltip says it's the game's own action, the same on every bar. Put an action on one bar: that cell shows it and the other three go empty ("Not bound"); clear it: Auto-run / Ping are back on all four. Focus one: the line runs into the stick on the drawing, which lights. The tooltip says "Stick press · the same on every page", that empty bars do nothing while it has an action, and how to get Auto-run / Ping back. On Xbox and Switch the rows say LS / RS: note what the glyphs show.
2. Nothing on R3: R3 pings (the game's own). Put a spell on **R3**'s right bar (R1 + R3 in the default layout): R1 + R3 casts it; R3 alone now does nothing. Clear it: R3 pings again. Same for L3 and Auto-run.
3. Put Jump on L3's top bar and an item on L2 + L3: both work, in combat too. Change the crossbar page: still the same.
4. Put **Open ring** (Dynamic stick) on R3: it aims with the left stick; on L3 with the right one.
5. Open the on-screen keyboard or chat with something on L3 / R3: pressing them doesn't fire the stick cells.
6. **Sort bags key:** Tweaks → Bags & vendors, a "Sort bags key" row under Sort bags button, reading **L3**. The tab hint says "Most are off until you turn them on."
   - Open your bags, press L3: they sort. Close them: L3 auto-runs.
   - L2 + L3 (or a shoulder + L3) with bags open: no sort.
   - Set it to R3: R3 sorts with bags open, pings when closed. Off: neither sorts.
   - With bags open and a spell on L3's top bar: L3 sorts (the bags win); bags closed: the spell.
   - Open the bags, start a fight: L3 auto-runs in the fight (no sort); after it, with bags still open, L3 sorts again.
7. **Footer prompt:** with the bags open, the bags' gamepad footer (Select · Collapse · Manage Bag · Close) has an "L3 Sort" segment joined to its right end: the same dark box and border, one line dividing the two, the pad's own L3 glyph and "Sort" in the footer's gold. Take a screenshot and compare it with the approved mock-up.
   - Move the cursor between items and the bag buttons: the footer's prompts change and the segment stays on its right edge.
   - Focus the search box: the footer and the segment hide together; leave it: both come back.
   - Sort bags key R3: the R3 glyph. Off: no segment. In a fight: no segment; after it, back.
   - Separate bags (if your setup shows them): an "L3 Sort" segment alone under the backpack.
   - With an Xbox pad: the LS glyph.

### N6. What's new

Needs a packaged build (a real version in the toc): a dev build (`@project-version@`) never opens it on its own. Edit `WTF/Account/<account>/SavedVariables/ForeverControllerTweaks.lua` with the game closed to set `news`.

1. Fresh SavedVariables: nothing shows; `news.seen` is the running version.
2. `news = { seen = "1.2.1-beta.2" }`, log in: about 3 seconds after the world loads (after the setup guide, if it opens) the window shows the newest notes down to 1.3.0, the version line "Version … · updated from 1.2.1-beta.2". With `seen = "1.0.0-beta.1"`: the 5 newest, then "Older versions:" and the website.
3. It looks like the Character window: the metal frame with the addon icon in the portrait ring, the title "Controller Tweaks · What's new", the focus glow round the portrait. The body lets about a quarter of the world through; the frame, text and box are solid. Put the Character window next to it and take a screenshot of both.
4. Focus opens on the notes, the box unticked, the hint glyph D-pad Up. A does nothing. D-pad Up at the top: the box (row wash, cursor, its tooltip under it, the hint turns to A, Select in the footer). A ticks it. D-pad Down: back to the notes.
5. Scroll: the right stick (with either focus), D-pad Down / Up held, the mouse wheel, the bar's arrows and thumb. The bar and the Scroll prompt hide when the notes fit.
6. B closes; `/reload`: nothing. `news.seen` is the running version. Repeat with the box ticked: `news.never = true`, and with an older `seen` it stays shut.
7. Tick the box, pull a mob: the window closes. After the fight it opens again, unticked; nothing was stored. A second fight in the same session: it doesn't come back.
8. Open chat first, then `/reload` with an older `seen`: it waits until the chat box closes. Open the settings first: it waits until they close.
9. `/fct whatsnew`: "What's new is on again" (if it was off), the window with this version's notes only, "Version x.y.z", unticked. The X closes it like B. In combat: the combat line, nothing opens.
10. A downgrade (`seen = "9.0.0"`): nothing, and `seen` stays. A dev build: nothing on its own; the command shows "Development build · notes for …" and closing stores nothing.
11. Steam Deck size (1280 × 800): it fits, with the footer.
12. `taint.log` has no line naming ForeverControllerTweaks after opening, scrolling and closing it.

### N7. Lost settings: FCT: macros and hidden slots

1. With a few game actions (Backpack, Map) on face cells, the crossbar and touch buttons, log out and **move** `WTF/Account/<account>/SavedVariables/ForeverControllerTweaks.lua` aside (keep it, to put back after).
2. Log in. To reproduce the old bug first, an older build makes "FCT:Bags 2"… in the macro window here; with this build:
   - one chat line says it tidied up (only if there was something to tidy), and the macro window has one "FCT:Bags" (or one numbered copy) per action, not a pile;
   - the crossbar slots and touch buttons that held a copy still work and hold the kept one;
   - Touch tab: "Slots x / 36" counts only what your buttons use.
3. A macro of yours named like ours ("FCT:Bags 4") but with other text is still there, unchanged.
4. `/reload`: nothing changes, no chat line. Put your settings file back with the game closed.
4a. **`/fct cleanup`** (Gamepad UI on, out of combat): one chat line with the counts (macros registered again, duplicates deleted, slots pointed at the kept copy, hidden slots given back, freed). Run it again: all zeros. In combat it says why it can't. With `/fct debug on`, a login with the Gamepad UI off logs "leftovers: waiting (gamepad UI off)", and turning it on runs it.
4b. Make a copy by hand of the macro "FCT:Bags" text, name it "FCT:Bags 2", then put Backpack on a cell: the addon reuses its own "FCT:Bags" (no "FCT:Bags 3" appears).
4c. **Two computers** (or move the settings file aside, which looks the same to the addon): set up a face cell and a touch button with Backpack and a spell on computer A, then log the same character in on computer B with the same cells set up there. No "FCT:Bags 2" appears and "Slots x / 36" doesn't grow: B reuses A's hidden slots. Switch back to A: still no growth.
5. **Full slots:** fill bars 6-8 (36 actions of your own on keyboard bars 6-8, or many touch buttons), then put a spell on a touch button: it's accepted and casts when tapped; its tooltip in the Touch tab says it has no hidden slot (no live cooldown). Clear one of bars 6-8's slots and `/reload`: the button gets a slot and shows its cooldown.
6. **Free up slots:** with some of your own spells or items on keyboard bars 6-8 (put them there with a keyboard, or with the Gamepad UI off), the Touch tab shows a **Free up slots** button right of "Slots x / 36" (none when bars 6-8 hold only the addon's). Its tooltip counts them. Press it: our own confirm box lists each one with its icon and name (10, then "and N more") and says they're cleared from those bars for good. **Cancel** changes nothing. **Clear them**: those slots empty, one chat line, the button goes, the counter has room, and a touch button waiting for a slot gets one. In combat it refuses with the combat line. Your spells, items and macros themselves are still in the spellbook, bags and macro window.

### N8. Sync between computers, export and import

Two computers, A and B, the same account. `/console taintLog 2` on both. New files in this version: restart the game fully once.

1. **T1. Fresh login on B after A wrote.** On A, set up bindings, a ring and a touch button, wait 10 s, log out. On B (no settings for the addon, or after moving its SavedVariables aside), log in: within a couple of seconds chat says "Synced from Mac · …: bindings, …". The cells show in Bindings and on the crossbar, the ring and touch button are there, and the Macros window has no extra `FCT:` copies (one `FCT:Bags`, not `FCT:Bags 2`). With `/fct debug on`, a slow login logs "sync: waiting for the macro list" until the list arrives, and A's copy on the server is unchanged afterwards (log in on A again: nothing of B's defaults came back).
2. **T2.** Drag `FCT:Sync 1` from the Macros window onto a bar and press it: nothing happens, nothing is said. Remove it again.
3. **T3.** A first write of 6 or more macros at once (a big setup), then log in on B: everything arrives. Make 3 quick changes on A about 30 s apart, then log in on B: the last one arrived.
4. **T4.** Change a ring on A and log out within 5 s. Log in on B: say whether the change arrived (then a logout write works) or only after A's next login.
5. **T5. Both changed.** On B, `/fct sync off`, change a tweak (say the light bar) and log out. On A, change the same tweak to another value and log out. On B, log in and `/fct sync on`: A's newer change wins, one chat line says "Tweaks changed on both computers…", and Settings → **Undo last sync** brings B's value back.
6. **T6. Damaged.** Delete `FCT:Sync 2` in the Macros window, `/reload`: one chat line "written again", and the macro is back. Edit a sync macro's text by hand, `/reload`: the window's state line says the macros were changed, then they're written again and it's Up to date. On a computer that never synced (settings file moved aside) with a damaged set: it stays "changed or incomplete" and writes nothing until **Sync now**. Your own macro named `FCT:Sync 3` with other text is never touched.
7. **T7. Full.** Fill your account macros to 119, then add rings or bindings until sync needs one more macro: the state line asks you to free some, no sync macro was changed, chat says it once. Delete two macros and press **Sync now**: Up to date.
8. **T8. Off.** On B, Settings → untick **Sync between machines**. Change something on B: A doesn't get it. Tick it again: it merges without asking.
9. **T9. Import box and taint.** Settings → **Import…**, click the box and paste with Cmd+V. While the box has focus: `/dump GamepadSharedUtility.InputBindingManager:IsOnlyCoreBindingSetActive()` is true, and the on-screen keyboard doesn't open on it. Close the window: Back, Jump and Interact work, and `taint.log` has no ForeverControllerTweaks line.
10. **T10. Export.** **Export…**: only **Select all** and **Close** (no Print to chat). Cmd+C copies the selected text (paste it into a text editor); click elsewhere, **Select all**, Cmd+C again. **Import…** on the other computer and paste: the preview matches. The export has no character name in it. Paste a broken text (cut it in half, or edit a letter): "This isn't a Controller Tweaks export", no Lua error.
11. **T11. First sync with your own setup.** On a computer with its own bindings, log in after the other wrote: the dialog over the Settings tab ("found settings from another computer"). B and the X don't close it. **Use synced** takes the other copy; Undo brings yours back. On another try, **Keep mine** keeps yours, the other computer gets it at its next login, and **Undo last sync** here takes the other copy after all. A computer whose tweaks or keyboard settings differ from a new install also asks (not only one with bindings or rings).
12. **T12. Combat.** Change something, then start a fight within 5 s: nothing is written in the fight, the state line says "Changes waiting", and it goes out after the fight. `taint.log` clean. Also check: `/fct release` deletes the sync macros (and your own `FCT:Sync` macro stays).
13. **T13. Hidden slots freed across computers.** One character, sync on on both. On A, put a spell on a face cell's base layer (it takes a hidden slot) and note "Slots x / 36" in the Touch tab. Wait 10 s, then remove that binding on A and put another spell on a different cell. Log out. Log in on B (where that spell was never bound): within a few seconds the spell's old hidden slot is free again (`/fct selftest` and "Slots x / 36" don't count it, keyboard bar 6-8 shows it empty with the Gamepad UI off). A binding of that character on another controller, or a touch button with that spell, keeps its slot instead. With sync off on B (`/fct sync off`, then `/reload`), nothing is freed. A spell you put on bars 6-8 yourself is never cleared. Also: the same spell on two cells (or a cell and a touch button) uses one slot; clear one of them and the other still casts.
    - **Release note, known edge:** if you put by hand the exact action the addon once placed in that same slot, it may be cleared once no binding needs it.
14. **T14. The switch in Settings.** Settings tab → **Sync between machines**: untick it, chat says "Sync is off on this computer." and the state line says off. With the tab open, `/fct sync on` ticks it at once. On the other computer the setting hasn't changed (it never syncs). Tweaks → Controller has no Sync row, and Triangle → More has no Sync & backup.

## O. 1.5.1

### O1. Profiles with two controllers

Two controllers (say a DualSense and a GameSir or Xbox pad), one computer. `/console taintLog 2`. New files in this version: restart the game fully once.

1. **Update from 1.5.0.** Log in with the controller you used before: no question, and Bindings and the crossbar are exactly as before. Settings tab → Profile: **This controller** shows a profile named after the controller; Controllers lists every controller you used, each on its own profile. `/fct status` names the profile.
2. **New controller: the question.** Connect the second controller (or switch to it). It plays at once with the first controller's bindings, and a few seconds later the Settings tab opens with "New controller: <name>": **Use <profile>**, **Copy <profile>…**, **New empty**. Not during a fight, a loading screen, the setup guide (for a controller the addon doesn't know) or What's new: it comes after those. The X doesn't close it.
3. **Use.** Press **Circle** (that's Use): bind a spell on a free cell with this controller, switch to the other one: the same spell is there. Change a modifier (Bindings → More → a preset) on one: the other follows. The glyphs still show each controller's own symbols.
4. **Copy.** Settings → **Copy profile**: a profile named "<name> 2" for this controller, with the same bindings. Change a binding: the other controller keeps its own.
5. **New empty.** Settings → **New profile**: this controller is on the game's own layout with no bindings; switch with **This controller** left / right and everything comes back, out of combat only (in a fight it waits, then switches).
6. **Rename.** Settings → **Name**, Cross, type with the on-screen keyboard (or a keyboard), Enter: the stepper and the Controllers list show the new name. Escape while typing puts the old one back. A second profile named like an existing one gets " 2".
7. **Delete.** Settings → **Delete profile** asks first; Cancel keeps it. Delete: the controller moves to the first profile left (its bindings and layout now), the deleted profile's bindings are gone for every character, and Delete is off when only one profile is left.
8. **The question again.** Connect a third controller: the stepper (D-pad up) picks which profile Use and Copy act on; **Copy…** makes a profile named after the controller with every character's bindings; **New empty** starts empty.
9. **Commands.** `/fct profile` lists them, this controller's marked; `/fct profile <name>` switches; an unknown name says so.
10. Throughout: `taint.log` has no ForeverControllerTweaks line, and Back, Jump and Interact work after closing the Settings tab.

### O2. Profiles across computers

Two computers, A and B, both on 1.5.1, sync on.

1. **Picks sync.** On A, answer the question for the GameSir with **Use** (the DualSense's profile). Log in on B with the GameSir: no question, it plays on that profile with the same bindings.
2. **Profiles sync.** On A, **Copy profile**, rename it, bind something. Log in on B: the profile is there with its name and bindings.
3. **Delete syncs.** On B, delete that profile. Log in on A: it's gone there too, and a controller that used it is on the first profile left.
4. **Mixed versions.** With A on 1.5.1 and B still on 1.5.0, log in on B after A wrote: chat says sync is paused because another computer has a newer Controller Tweaks, and A's copy on the server is unchanged (log in on A: nothing of B's came back). Update B: it merges without a question.
5. **Export and import.** Settings → **Export…**: the text names the profile, not the character. **Import…** it on the other computer: the preview lists "Profile layout" and "Bindings in this profile"; Import goes into that computer's current profile and keeps its name. An export made with 1.5.0 still imports.

## P. 1.5.2

### P1. A new character starts empty

Back up `WTF/Account/<ACCOUNT>/SavedVariables/ForeverControllerTweaks.lua` first. `/console taintLog 2`.

1. **Update.** Log in on the character whose bindings leaked to a new character. Within a few seconds (once its spellbook is loaded) its bindings, touch buttons and rings are the newest ones you had. After `/reload`, the SavedVariables file has its record under `["Player-…"]` with a `name`, and no `["<Name>-…"]` record of that first name any more.
2. **A new character with the same first name** (best: log in with it first after the update, a different class): Bindings shows no actions of yours, the touch bars have no buttons, the Rings tab has no rings, and the crossbar is the game's own. The old records are still in the file, untouched.
3. **Back on the first character:** everything is still there.
4. **Many logins.** Log in and out 5 times, with `/reload` in between: no new `Name-…` record ever appears in the file. Say whether an old record of a character that shares its spells with another one (a low-level twin of the same class) was claimed by the wrong one.

### P2. Rings per character

1. On the character whose old settings opened them, the Rings tab lists those rings (and any ring no button opened). On another older character: the rings its buttons open are there, the others aren't.
2. Make a ring on one character: the other doesn't have it. Delete a ring: only this character's buttons that opened it are cleared.
3. **Arrow on ring buttons** off on one character: it's off on the others too.

### P3. Touch buttons per profile

1. After the update every profile has the touch buttons you had.
2. Settings → **New profile**: the touch bars keep their size and place, with no buttons. Put a button there, switch back (**This controller** left / right): the first profile's buttons are back.
3. **Copy profile:** the copy has the same buttons. Change one: the other profile keeps its own. **Delete profile:** its buttons are gone.
4. Hidden slots: a touch button's spell in one profile keeps its slot while you play on the other profile ("Slots x / 36" counts it once).

### P4. Camera zoom

1. Picker → **Misc** → **Zoom in** on a D-pad cell, **Zoom out** on another. A press: one step. Hold: the camera keeps moving until you let go. Hold it while a fight starts: it stops. In combat: they still work. On a touch button: a tap is one step.
2. `/console taintLog 2`, use both in and out of combat, `/reload`: `taint.log` has no ForeverControllerTweaks line, and no "blocked" line in chat. **Say whether** `CameraZoomIn` or `MoveViewInStart` was blocked in combat (both are expected to be free to call).
3. Tweaks → **Camera → Camera zoom**: before you touch it, it shows where the camera is now. D-pad right: the camera moves out at once; it never goes past the game's limit (the slider stops there). `/reload` or log in again: the camera goes back to that distance once, a second after the world loads (after the fight if you're in one).

### P5. Sync between 1.5.2 and 1.5.1

1. Two computers on 1.5.2: rings (per character), touch buttons (per profile) and Camera zoom sync, every character under its `Player-…` ID. Old name-keyed records are never synced.
2. One computer on 1.5.1, the other on 1.5.2: after the 1.5.2 one wrote, the 1.5.1 one says sync is paused because another computer has a newer Controller Tweaks, and writes nothing.
3. Export on 1.5.1, import on 1.5.2: the rings go to this character, the touch buttons to this controller's profile.

## Reporting results

In a pull request or issue, list the parts you ran and the controllers you used, and say whether `taint.log` was clean. Attach screenshots of anything that looks wrong, with character names and chat cropped out.
