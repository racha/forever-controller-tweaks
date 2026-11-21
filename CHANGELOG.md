# Changelog

## 1.5.3 — 2026-11-21

### Fixed: error with a pet
- Opening the action picker (choosing an action for a button) on a character with a pet, such as a Warlock with an Imp, showed a Lua error and the picker stayed closed. The pet's spells now list normally.

### Fixed: Learn all never showed on the trainer
- With the Gamepad UI on, the game hides the trainer's own Train button, and **Learn all** (Tweaks → Trainer: Learn all) only showed while that button did. It now shows whenever the trainer window is open.

## 1.5.2 — 2026-11-21

### Fixed: a new character got another character's bindings
- WoW: Forever characters have a first and a second name, and the game tells addons only the first. 1.5.1 saved settings under that first name, so every character with the same first name shared them: a new character could start with another one's bindings, touch buttons and rings.
- Settings are now saved per character by its unique game ID. After the update, the old settings go back to the character they belong to: the one that knows every spell in them takes them, newest first. Settings no character can be sure of are kept as they are, untouched. A new character starts empty: no bindings, no touch buttons, no rings.

### Changed: rings are per character
- Each character has its own rings. After the update, each character's old settings keep the rings their buttons open, and rings no button opens go along with all of them. A new character starts without rings, even if it is the first you log in with after the update.
- The Rings tab, the picker and `/fct rings` show this character's rings. Deleting a ring clears only this character's buttons that open it. **Arrow on ring buttons** stays one setting for all characters.

### Changed: touch buttons are per profile
- What each touch button does is now saved per profile, like bindings: a new profile starts with empty touch buttons, **Copy profile** copies them, and **Delete profile** deletes them. The touch bars' size, place, shape and On / Show stay one setting per character.
- After the update every profile you have keeps the touch buttons you had.

### New: zoom the camera
- **Zoom in** and **Zoom out** in the picker's **Misc** category: a press moves the camera one step, holding keeps it moving until you let go. They work in combat too. On a touch button or ring slot a tap is one step.
- **Tweaks → Camera → Camera zoom:** where the camera sits, in yards, up to the game's own limit. Moving it zooms at once, and the camera goes back there when you log in. Untouched, the addon never moves your camera.

### Sync
- Sync is written in a new format. A computer still on 1.5.1 pauses sync and says to update; it never writes over the newer copy. Update the addon on every computer you sync.
- Rings sync per character and touch buttons per profile. The first time two computers meet after the update, a character keeps every ring either computer gave it. An export from 1.5.1 still imports: its rings go to this character, its touch buttons to this controller's profile.

## 1.5.1 — 2026-11-21

### New: profiles, share bindings between controllers
- Your layout (which buttons are modifiers, where Jump and Interact sit) and every character's bindings now live in a **profile**. Controllers on the same profile share all of it: bind a spell on your DualSense and it is on your GameSir too. Glyphs and button setup still follow each physical controller.
- **Nothing changes for you after the update:** each controller you already used becomes its own profile, named after it, with its layout and bindings as they were. Share one when you choose to.
- **A new controller asks once:** **Use** a profile you have (shared, the same bindings), **Copy** one into a new profile to change on its own, or start **New empty** (the game's layout, no bindings). With more than one profile, a stepper picks which one Use and Copy act on. Until you answer, the new controller plays on the profile you used last; **Circle** answers Use. The question waits for the end of a fight, a loading screen, the controller setup and the setup guide.
- Your very first controller gets a **Default** profile without asking.
- `/fct profile` lists your profiles; `/fct profile <name>` switches this controller to one.

### New: Settings tab
- A sixth side tab after Tweaks, in the same look:
  - **Profile:** the profile this controller uses (left/right switches it, out of combat), its **Name** (type a new one), **New profile**, **Copy profile** and **Delete profile**. Delete asks first, takes every character's bindings in that profile with it, and moves its controllers to the first profile left. The last profile can't be deleted.
  - **Controllers:** every controller this computer knows and the profile it plays on.
  - **Sync between machines:** the switch, when it last synced and from where, what is on the server, **Sync now** and **Undo last sync**.
  - **Backup:** **Export…** and **Import…**.

### Changed: Sync & backup moved to Settings
- **Triangle → More → Sync & backup** and **Tweaks → Controller → Sync between machines** are gone: the switch, the status, Sync now, Undo, Export and Import are all in the Settings tab. `/fct sync`, `/fct export` and `/fct import` work as before.
- **Copy bindings from** is gone too: Use or Copy a profile instead.
- Profiles sync between your computers with everything else, and so does which profile each controller uses. Deleting a profile on one computer deletes it on the others.
- An export holds this controller's profile (its name, layout and this character's bindings); an import goes into this controller's profile. Exports from 1.5.0 still import.
- Sync from this version is written in a new format. A computer still on 1.5.0 pauses sync and says to update; it never writes over the newer copy. Update the addon on every computer you sync.

## 1.5.0 — 2026-11-21

### New: What's new
- After an update, a window shows once with what changed since the version you last saw: this list, newest first. It never opens in a fight or over another window, and a new install doesn't show it.
- **Never show again** at its top right turns it off for good (it's never ticked for you). Type `/fct whatsnew` to see this version's notes and turn it back on.

### New: a ring remembers your last pick
- **Middle**, a new setting per ring in the Rings tab: **Cancel** (the default, as before) or **Use last**. With Use last, letting go of a Hold ring in the middle, or pressing **Cross** with nothing aimed, uses the slot you used last. Handy for totem and buff rings.
- The buttons that open the ring (crossbar, Bindings, touch buttons) show that slot's icon, and so does the ring's middle while nothing is aimed.
- Each character remembers its own last pick, across reloads. Change or empty that slot and it's forgotten.
- Switch it from any button that opens the ring too: **Triangle** on the cell in Bindings (or on a touch button) shows **Middle: Cancel** / **Middle: Use last**. It's the ring's own setting, shared by every button that opens it.
- A Toggle ring still opens on its button and closes on it again; **Circle** still cancels.

### New: an arrow on ring buttons
- Every button that opens a ring has the game's small flyout arrow at its top edge, on the crossbar, in Bindings and on touch buttons, so you can tell them apart. Healer mode buttons keep their green cross instead.
- The arrow hides while that ring is open, as the game's own flyout arrows do.
- On by default. Turn it off with **Arrow on ring buttons** at the foot of the ring list in the Rings tab.

### New: Healer mode remembers your last target
- In **Bindings**, on a button in Healer mode, **Triangle** shows **Middle: Cancel** under the Healer mode row. Pick it for **Middle: Last target**: letting go in the middle then casts on the place you last healed with that button, like Party 2.
- While you hold the ring with the stick in the middle, that place lights up and shows its tooltip. If that unit can't be helped now (gone, hostile), nothing is cast.
- It remembers the place, not the person, per button and per character. Off by default.

### New: L3 and R3 in Bindings
- **L3** and **R3** (pressing a stick) have their own rows in Bindings, with a cell per bar, like a back paddle: put anything from the picker on L3 alone, on **L2 + R3** and so on. Rings opened from a stick press aim with the other stick when set to Dynamic.
- A stick press is taken over only while one of its bars holds an action. Clear every bar and it's the game's again: **L3** auto-runs, **R3** pings. While one bar is used, the empty bars of that stick do nothing.
- Until then its cells show what the game does with it, **Auto-run** or **Ping**, with the game's own icon, like the face buttons' Jump and Interact.

### New: sort your bags with a stick press
- While your bags are open, **L3** sorts them. With the bags closed it works as usual (Auto-run). Not with a shoulder or trigger held.
- The bags' controller footer shows it: an **L3 Sort** prompt joined to the end of Select · Collapse · Manage Bag · Close.
- **Tweaks → Bags & vendors → Sort bags key:** L3 (the default), R3 or Off. This is the one tweak that starts on, so the Tweaks tab now says most are off until you turn them on.

### New: your settings on every computer
- Play on a Mac and a handheld? Your bindings, rings, touch bars, controller setup, tweaks and keyboard settings (quick messages included) now follow you. The addon keeps a copy in a few account macros, **FCT:Sync 1**, **FCT:Sync 2**…, which the game stores for your account, and every computer you log in on uses the newest copy. On by default.
- Each part goes on its own: change your rings on one computer and your tweaks on the other, and both arrive. When the same part changed on both, the newer one wins, chat says so, and **Undo last sync** brings yours back.
- The first time on a computer that already has its own setup, it asks once: **Use synced** or **Keep mine**. Either way the other copy is kept for **Undo last sync**. A computer that hasn't read the synced copy yet never writes over it.
- What stays on each computer: the keyboard's learned words, which slot a ring used last, Healer mode's last target, and the addon's own bookkeeping.
- Bindings are kept per controller. A controller with no bindings yet offers **Copy bindings from** your other controller.
- **Triangle → More → Sync & backup** on any tab shows when it last synced and from where, how many macros it uses and how many are free, and turns it off for this computer (the macros stay for the others). The same switch is in **Tweaks → Controller → Sync between machines**. `/fct sync` shows the same in chat; `/fct sync now`, `on`, `off` and `undo` do what they say.
- The sync macros do nothing if pressed. Don't edit them in the Macros window; if one is changed or deleted, the addon writes them again. It never deletes a macro of yours, even one named FCT:Sync, and it never writes half a copy: when your account macros are full it says how many to free. `/fct release` deletes them too.

### New: export and import
- **Sync & backup → Export…** (or `/fct export`) shows your settings as text, already selected: Ctrl+C (Cmd+C on a Mac) copies it. It holds this character's bindings for this controller, touch bars, rings, tweaks, keyboard settings, options and the controller layout, and no character names, so you can share it.
- **Import…** (or `/fct import`): paste with Ctrl+V (Cmd+V). It lists what would change, part by part; untick what you want to keep. Import asks once, and **Undo last sync** puts your old settings back. Pasting needs a keyboard.

### Fixes
- **No more piles of FCT: macros:** the addon could lose track of one of its own macros (playing on a second computer, its settings reset, or a check at login that ran before the macro list had loaded) and then made "FCT:Bags 2", "FCT:Bags 3"… beside it, for game actions and other addons' buttons alike, filling the hidden action slots until touch buttons couldn't be added. It now recognises its own macros by name and text and reuses them, and a hidden slot that already holds the action a button wants (placed from your other computer) is reused instead of taking another. Once per login it also tidies what earlier versions left: one copy of each is kept, your buttons point at it, the extra copies are deleted and the hidden slots they held are freed. **/fct cleanup** does it on demand and says what it did. Your own macros are never touched, even one named FCT:.
- **Hidden action slots are shared between your computers and freed when no binding uses them.** The addon now keeps a list of the hidden slots (keyboard bars 6-8) it placed on any of your computers, in the sync macros. A computer reuses a slot the other one placed for the same action, and frees one that no binding or touch button of that character uses any more, on any controller. Slots holding your own actions are never touched. Two buttons with the same action now share one hidden slot.
- **Touch buttons when every hidden slot is taken:** adding an action no longer fails. It works right away as a macro, without a live cooldown or charges until a hidden slot frees up (its tooltip says so), then it gets one by itself.
- **Free up slots** in the Touch tab: when your own actions sit on keyboard bars 6-8 (the hidden slots touch buttons and moved actions use), a button next to the slot counter lists them and, after you confirm, clears them from those bars. The spells, items and macros themselves stay.
- **Sort bags button:** it could disappear behind the combined bags' title bar in the Gamepad UI. It now sits at the right end of the title bar and stays there.
- **Crossbar stuck after a held ring:** with a modifier moved to another button (for example the right bar on L1), the crossbar could stay on that bar after a held ring or a heal, until you pressed the modifier again. It now always goes back.
- **Ring buttons showed an item count:** a ring on a crossbar slot that held food or another stack showed that item's count on the ring's icon. The count is hidden now.
- **Aiming a heal with the left stick:** after a held ring closes, the stick that aimed it stays held back while you cast or channel, so a heal aimed with the left stick isn't broken by walking. It's let go as soon as the stick is back in the middle, and a second after the cast ends at the latest.

## 1.4.0 — 2026-11-17

### New: Healer mode
Any button that holds a heal can open a ring of your group: aim at someone and let go to cast on them.

- **On per button:** focus a cell in Bindings (or a touch button in the Touch tab), press **Triangle** and pick **Healer mode: On**. Spells, spell groups and items can use it. A green cross marks the button in the windows and on your crossbar.
- **The ring:** the game's small round picker on the button you hold, with 7 places in fixed spots: You, Party 1 to 4, Target and Focus. Let go on someone to cast there, in the middle to cast nothing. Dead allies can be picked for a resurrection; a hostile target can't.
- **Each place** shows the portrait, a health ring in the class colour, the role, incoming heals, shields, heal absorbs, a red pulse under 30% health, and a debuff you can dispel. The person you aim at gets the game's own tooltip.
- Works on face buttons, the D-pad, paddles, crossbar slots and touch buttons, in combat too. No settings: it always shows while held and aims with the stick for that button.

## 1.3.0 — 2026-11-15

### New: the Tweaks tab
A fifth settings tab with small conveniences for every character. **Each one is off until you turn it on**, and they work only while the Gamepad UI is on.

- **Bags & vendors**
  - **Sort bags button:** a Sort button on your bags' title bar. With the controller, use Clean Up in the bag menu or the picker's **Sort bags** action.
  - **Sell junk:** sells your grey items when you talk to a merchant. One chat line lists what sold and for how much.
  - **Repair:** repairs your gear at a merchant who repairs. **Use guild funds first** pays from the guild bank when the guild allows it.
  - **Buy a full stack:** a Stack button on stackable merchant items, and a picker action that buys a stack of the item under the cursor. It never spends 150 gold or more in one press, and says when the item is sold out.
- **Quests & NPCs**
  - **Skip one-option talk:** when an NPC offers only one thing, it's picked for you: a single quest, or a vendor, trainer, flight map or bank. Never a teleport, an event start, a story skip or an option that costs money.
  - **Trainer: Learn all:** a Learn all button for every skill you can afford.
  - **Mail: Open all:** an Open all button on the mailbox. It skips cash-on-delivery mail and stops when your bags are full.
- **Rumble:** the controller rumbles on events, in eight groups, each with its own pattern (or Off), and one **Strength** for all. See below.
- **Controller**
  - **Low battery warning:** one chat line when the controller's battery runs low.
  - **Battery on the minimap:** a round button on the minimap's ring, next to the others, with the controller's charge. Hidden for pads that don't report one.
  - **Rare nearby alert:** a line on screen and a rumble when a rare is near. Once per rare, never in a fight.
  - **Light bar:** Game default, Class colour or Custom (10 colours), plus **Combat flash** (red while you're in combat). For pads with a light bar; Steam may take it over.
- **Loot & gear**
  - **Fast loot:** takes all loot at once. Bind-on-pickup items still ask; with full bags only coins are taken.
  - **Pass on unusable rolls:** passes on armour or weapons your class can never use. When unsure, you roll.
  - **Upgrade arrows:** a green arrow on gear in your bags, the loot window and loot rolls that has a higher item level than what you wear there.
  - **Wear quest rewards:** after a quest, an upgrade reward gets a card for 10 seconds: hold the top face button 1 to 3 seconds to wear it.
- **Group & social**
  - **Accept friend & guild invites:** joins a group when a friend, Battle.net friend or guild member invites you. Never a role check, a quest session invite, or an invite that would drop your dungeon or PvP queue.
  - **Decline duels:** turns down every duel request.
  - **Accept resurrect and summon:** out of combat. A resurrection only without resurrection sickness. A summon only from a friend or guild member, and never while you're inside an instance.
  - **Whisper alert:** a card with who whispered you and how the message starts.

### Rumble
- The groups and their starting patterns: **Group** (ready check, invite, summon, resurrect: Double tap), **Whisper** (Tap), **Trade & duel** (Tap), **Danger** (death, stun or fear, aggro, interrupted cast: Long buzz), **Enemies** (an enemy player nearby: Double tap), **Rare nearby** (Heartbeat), **Level ups** (level up, achievement: Ramp up) and **Procs** (a spell lights up, your target dies, you land a critical strike (solo): Off).
- Patterns: Tap, Double tap, Triple tap, Long buzz, Heartbeat, Ramp up, Fade out, or Off. Cross on a group's row plays its pattern; Cross on Strength plays a Double tap.
- Only events you still have to answer rumble: an invite a tweak accepted doesn't.
- Busy events wait before they rumble again: whispers, invites and trades 3 seconds, procs 2, critical strikes 1, aggro 3, enemy players 10.
- The light motor never runs below half power, so every pattern can be felt.

### New picker actions
- **Combat:** **Cancel** (stops a cast, a ground target and clears your target), **Best healing potion**, **Best mana potion**, **Best grenade**. They work in combat.
- **Movement:** **Look behind (hold)**: the camera turns round while you hold the button.
- **Windows:** **Peek map (hold)**: the map shows while you hold the button.
- **Targeting:** **Mark next**: the next raid mark on your target, in kill order (skull, cross, square…), in combat too.
- **Misc:** **Sort bags**, **Buy a full stack**, **Eat & drink** (your best food, and drink if you use mana), **Quest item** (the item of the quest you follow, else the nearest one), **Track nearest quest** (again for the next nearest), **Ready check**, **Pull countdown (5 s)** and **Minimap zoom**.
- The two hold actions work on face, D-pad and paddle buttons. On a touch button or ring slot a tap toggles them.
- The potion, grenade and food actions find items by their English names, so they need an English game client.

### Rings
- **The native radial look:** rings now look like the game's own radial menu, with just the wheel: no title and no band. The Rings tab shows the same wheel.
- **Let go of the stick to use the slot.** Letting go of the button and the stick at the same moment uses it too.
- **Show, per ring: Toggle or Hold.**
  - **Toggle** (the default): a press opens the ring, and it stays until you use a slot, press its button again or press Circle.
  - **Hold:** the ring shows while you hold the button. Let go to use the slot you aim at; with nothing aimed it just closes.
- New rings aim with the **Right** stick.
- Fixed: a ring could get stuck on a diagonal, or stay open with nothing used.
- A held ring opened with the stick already pushed ignores that slot until the stick is centred again or moves off it.
- A ring released with nothing picked stays open (Toggle), so you can still aim.
- Rings now have 4 to 8 slots, the most the game's radial art has. A ring saved with more keeps its first 8.
- **Style, per ring: Full** (the radial wheel) **or Compact** (like the game's radial flyout, the aura and stance picker). A Compact ring opens on the crossbar button that holds it, with that button's icon and its modifier glyphs in the middle.

### Keyboard
- **Chat goes out through the addon's own secure button.** The game's chat box is never written to. After a send the chat box stays open and empty; one more Circle closes it.
- **Chat Style no longer matters:** Send works with Classic and IM.
- **In combat** only party, raid, instance, guild and whispers can be sent. Other lines stay in the box with a note until combat ends.
- Words are learned only from chat you send.
- **Simpler Keyboard tab:** On, Open, Layout, Scale and Word suggestions. The buttons can no longer be rebound, and the keyboard always places itself.
- **Quick messages** is now a page with two columns: the situations on the left, their lines on the right. Built-in lines can be hidden one by one (Square), and **Restore** brings them back.
- In the quick message editor, the suggestion list shows the fill-ins such as `{target}` with what each gives right now.
- Fixed: Compact showed empty keys instead of each set's letters.

### Settings
- Native sliders, dropdowns and checkboxes on every tab, one value per row: up and down move between rows, left and right change the focused value, Cross toggles a checkbox.
- Tooltips wrap at the game's own width and stay beside their row.
- On the Tweaks tab, a dropdown or slider at its end passes left and right on, so you can move between its columns. **Triangle** opens **More** there too.

### Fixes
- A macro on a remapped D-pad or face button works again (the game had been dropping it silently).
- No more glyph error with secret icons, for example Inspect's raid marker in Midnight.
- The party and raid frames' group-targeting prompt shows your remapped button.
- Bags: the Sort button sits on the combined bags' title bar, clear of the search box, and our buttons never block bag navigation.
- Sell junk's chat line lists the items that sold.
- Upgrade arrows now show (no gear passed the check before).
- A failed controller config write now backs off (1 s, 5 s, 30 s) instead of retrying ten times a second.
- Layout switches wait until the stick is let go.
- Less polling while nothing changes.
- `/fct help` lists every command.
- The setup guide closed with its X button counts as **Not now**, so it doesn't come back on every controller event.
- With the Touch module turned off, its message says it's turned off instead of "not in this build".
- Removed the Options → AddOns page: searching in Options made the game block an action and blame this addon. Open the settings with L2 + R2 + Create/View, the minimap button or `/fct`.

### No longer true from earlier versions
- 1.0: "Every button can be rebound" and the keyboard's centre or custom position. The keyboard's buttons are fixed and it always places itself.
- 1.0 and the README: "release with the stick centred to cancel". A centred release keeps a Toggle ring open, and a Hold ring just closes.
- 1.2.1-beta.1: "Send in chat needs Chat Style IM". Any chat style works now.
- 1.2.1-beta.2: letting go of a ring's button with the stick centred no longer always keeps it open. That now depends on the ring's **Show** setting.
- 1.0: "Options → AddOns → Forever Controller Tweaks" (Open Settings, Run setup guide). That page is gone; `/fct setup` runs the setup guide.

## 1.2.1-beta.2 — 2026-11-14

### Rings
- **Let go of the stick to use a slot**, like the game's own radial menu: press the ring's button, flick the stick to a slot, let the stick go. Works in combat.
- The ring stays open when you let go of its button with the stick centred. **A** uses the lit slot; **B**, a stick press or the ring's button again closes it without using anything. Letting go of the button while aiming still uses the slot.
- While a held ring is open, the addon turns on the game's stick-as-buttons setting (`GamePadStickAxisButtons`) and puts your own value back when it closes (after combat if a fight is on, or at the next login after a `/reload`).
- The ring's **Rename** box saves with the on-screen keyboard's Send and cancels with Close.

### Keyboard
- **Your own quick messages:** Keyboard tab → **Quick messages**. Pick a situation (or **Always**), add, edit, delete and reorder up to 20 lines, typed with the on-screen keyboard. They come first in that situation's suggestions, fill-ins such as `{target}` work, and **Show in suggestions** can hide the built-in lines. Reset keyboard to defaults keeps them.

## 1.2.1-beta.1 — 2026-11-14

### Fixes
- Removed **Open chat**: opening chat from an addon broke the Gamepad UI ("blocked from an action" error). Tap the chat box or use the game's own chat key instead.
- A button that still holds Open chat from 1.2.0 now does nothing and no longer errors. Pick a new action for it.
- Keyboard: fixed "ForeverControllerTweaks_Keyboard has been blocked" (`SetPreferredGamepadInteractTarget`) after using bag search and closing it. The keyboard no longer presses a box's Enter or Escape itself.
- Keyboard: **B** after Send or Close leaves the chat box or bag search through the game's own Back, so the box closes too. Close (Y) keeps the box and its text.
- Keyboard: Send in chat needs Chat Style **IM** (Options → Social). With Classic it says so; close the keyboard and press A to send.
- Keyboard: tapping a text box on screen (Steam Link) opens the keyboard while your touch bars are on.
- Keyboard: chat can no longer end up on the "needs a real keyboard" list.

### Added
- **Toggle FPS** action in the picker's Misc category: shows or hides the game's framerate counter. Works on face, D-pad and paddle buttons, touch buttons and ring slots.
- **Scrolling suggestions:** the list goes on past the first screen, up to 40 rows. Scroll with the D-pad or the mouse wheel; arrows show when there's more.
- **Real answers:** when someone asks "what lvl?", "what spec?", "where r u?", "tank or heal?", "how far?" or "ilvl?", the top suggestion is your actual answer: "18 Restoration Shaman", "Thunder Bluff, near 39, 55", "2/3 Kuz's Skull", "Item level 24".
- **Whole-line completion:** type 3 letters and get full lines, your own sent lines first, then phrases for where you are. One typo per word is forgiven ("anyoen" still finds "anyone").
- **Reactions:** short-lived lines for what just happened: level up ("Ding 19!"), an achievement, a boss kill ("gg") or wipe ("Wipe, run back"), a rare or better drop, and a buff another player cast on you ("Thanks for the Fortitude!", once per player and buff every 5 minutes).

## 1.2.0-beta.1 — 2026-11-14

### Modules
- Touch bars, the on-screen keyboard and action rings are now separate modules: **Forever Controller Tweaks: Touch**, **: Keyboard** and **: Rings**. They're in the same download and listed under Forever Controller Tweaks in the AddOns list, on by default.
- Turn off the ones you don't use in the AddOns list, then `/reload`. Their tab, More and Options entries and commands go away; their settings stay saved for when you turn them back on.
- The main addon works on its own. A button holding **Open ring** while Rings is off does nothing, and shows greyed with a note.
- Tabs keep their order (Bindings, Touch, Keyboard, Rings), and the L1/R1 hints name the tab next door.
- Installing by hand: copy all four folders (`ForeverControllerTweaks` and the three `ForeverControllerTweaks_*` folders). Your settings, rings, keyboard words and touch bars carry over unchanged.

### Added
- **Open chat** action for any button: in the picker's Windows category, for face, D-pad and paddle cells, touch buttons and ring slots. It opens the chat box like Enter on a keyboard, and the on-screen keyboard follows if its module is on.

### Keyboard
- Channel switches work again: `/s`, `/y`, `/p`, `/raid`, `/i`, `/g`, `/o`, `/w Name`, `/r` and `/1`–`/10`. Other slash commands still need a real keyboard.
- The keyboard's channel keys switch the channel at once and leave your typed text in place.
- Sending a message closes the keyboard; it opens again the next time you open chat.
- Suggestions too long for the list show in full in a tooltip when focused or hovered.

## 1.1.1-beta.1 — 2026-11-14

### Back paddles as action buttons
- A back paddle (Xbox Elite, DualSense Edge) without a role is now an action button, with its own action on each bar like a face button: for example Jump on the paddle alone and a heal on RT + paddle.
- Anything from the action picker works there: spells (ranks and Highest Rank), items, toys, mounts, equipment sets, macros, Jump, Interact, Back, Inspect, game actions, other addons' bindings and **Open ring**.
- Set a paddle's role to **None** to use it for actions; give it a role to make it a modifier again. Its actions stay saved while it has a role.
- Paddles with a role work exactly as before.
- Paddles are now named **Back paddle 1–4**.

## 1.1.0-beta.1 — 2026-11-13

Two big additions, an on-screen keyboard and action rings, plus touch bar modifier pages and a cleaner settings window. Still a beta: please report anything odd with `/fct selftest`.

### On-screen keyboard (new)
- A radial keyboard in WoW Forever's style opens on any text box while the Gamepad UI is on: chat, whispers, bag search, mail, macros, the auction house and more. Choose whether it opens only when you use the controller, or always.
- Both sticks type: each stick picks a cluster of four letters, the face buttons pick the letter. L1 is Shift, L2 is Symbols, and the hub has Space, Send, Erase and Close. Every button can be rebound.
- It places itself on the line from the text box toward the screen centre, clear of the chat window, the crossbar, your unit frame and the touch bars. Or pin it to the centre, or to a custom offset.
- **Smart suggestions**, all offline in the game:
  - 263 hand-written lines across 25 situations (ready check, resurrect, summon, invite, trade, duel, loot roll, dungeon, raid, battleground, city, guild and more), with fill-ins such as {zone}, {quest}, {target}, {class}, {role} and {level}.
  - Replies to chat aimed at you: 25 intent rules recognise 125 phrases ("inv?", "LF healer", "ready?", "res pls"…), and the reply goes back on the right channel. "I can heal" only shows if you can.
  - Quest progress for the quest you follow: "Need 5 more Wolf Pelts", "Done with {quest}, turning in". At most two quest lines.
  - Next-word prediction like a phone keyboard: after "Hello " it offers "everyone", "there", "all". It starts with built-in word pairs and learns how you write. R1 inserts a word and a space, so repeated R1 presses build a sentence.
  - Shorthands expand: lf, lfm, brb, omw, wts, oom, ty…
  - Each kind of box gets its own list: item names in bag search, names in mail "To" and /who, nothing in number boxes, word suggestions only in mail and macro text.
- Nothing is ever sent for you, and nothing leaves your PC. Only your own sent messages are learned from; other players' lines are kept for three minutes at most and never saved.
- Boxes the game blocks addons from typing into (the Options search, the Group Finder's boxes, spellbook search) are left to the real keyboard, with a one-line note instead of an error. Slash commands in chat (anything starting with `/`) are left to the real keyboard too.

### Action rings (new)
- Make your own radial menus: up to 12 rings of 4–12 slots, each with a name and an icon from the game's full macro icon set.
- Fill the slots from the same action list as the bindings: spells (with Highest Rank), items, toys, mounts, macros, game actions and other addons' bindings.
- Put "Open ring" on any face, D-pad or touch button, on any bar. Hold the button, aim with the stick, release to use; release with the stick centred to cancel. Works in combat.
- Choose the aiming stick per ring: **Right**, **Left**, or **Dynamic** (the stick of the hand that isn't on the button). The other stick keeps moving or looking, and the aiming stick is held back after release until it's centred, so you don't walk off.
- Slots show cooldowns, charges, range and usability. Touch rings open with a tap and fire with a tap.
- Rings don't use any hidden action slots.

### Bindings and modifiers in one screen
- The **Modifiers** tab is merged into **Bindings**: L1, L2, R1, R2 and the paddles are rows at the top of each side. Press A to give a button a role; picking a role another button has swaps the two.
- Presets (**Game default**, **Left = bars, Right = targeting**) are first in Triangle → More, and the header names the active one.
- The guided "set it up yourself" step runs on the Bindings screen.
- Tabs are now **Bindings**, **Touch**, **Keyboard** and **Rings**.

### Touch bars
- Modifier pages: each touch button has an action per bar (top, left, right, bottom), following your modifiers. An empty page hides its button instead of falling back.
- Settings per side: count, size, spacing, distance from the edge, height, opacity, **Circle** or **Square** buttons, and **Hide** or **Show** empty buttons.

### Look and feel
- Every screen has Triangle = **More**, with one shared menu.
- Calm, textured window background in WoW Forever's stone style, with translucent content boxes on every tab.
- New controller drawing in the logo's style. Only the focused row's button lights, never a button you're physically pressing.
- Controller type cards show each family's own layout and glyphs; the "Choose your layout" screen is redrawn to match.

### Fixes
- The "no controller found" line no longer sticks when a pad wasn't readable at login, and `/fct selftest` now lists what every controller reports.

## 1.0.0-beta.1 — 2026-11-12

First public beta, for WoW Forever 1.60.1 (Interface 16001). Everything works, but not many people have played it yet, so please report anything odd.

### Modifiers and targeting
- Give the left bar, right bar, friendly targeting and hostile targeting to any of L1, R1, L2, R2 or the back paddles P1–P4. Picking a role another button already has swaps the two.
- Presets: **Game default** and **Left = bars, Right = targeting**, plus a guided "set it up yourself" mode that asks for one button per role.
- Works through the game's own controller config, so every native bar, glyph and targeting mode keeps working.
- Game windows (bags, talents, map) get the game's own L1/R1 tabs back while they're open, out of combat.
- Combat-safe: the settings window closes when combat starts, and your layout stays in place for the whole fight. The controller config never switches while a button or trigger is held.
- Logging out, `/reload`, disabling the addon or turning off the Gamepad UI leaves a clean, default controller config. A config left by a logout in combat is cleaned up at the next login.
- If another addon already owns the controller config, Forever Controller Tweaks keeps a copy and restores it.

### Bindings
- The settings open on the **Bindings** tab: the controller drawn in the middle, one row per button at the edges, with that button's action on the top, left, right and bottom bar. The focused row draws a gold line to its button.
- Any action on any face or D-pad button, on any bar: spells, pet spells, items, toys, mounts, equipment sets, your macros, game actions, and Jump, Interact, Back and Inspect. Interact keeps hold-to-loot, and Jump keeps swim up.
- Moved actions behave like native slots: cooldowns, range, mana, charges, proc glow, tooltips, the press look and mouse clicks.
- Crossbar pages 1–3, switched with L2/R2. A note shows when a stance or pet bar replaces a bar on a page.
- Action picker: L1/R1 switch categories, L2/R2 page through long lists, Square clears a slot and Triangle undoes the clear. Entries that can't go on a button are greyed out with the reason.
- Spells with ranks are grouped, with a ranks page. **Highest Rank** moves up by itself when you learn a new rank.
- **AddOns** category: any key binding another addon registers (for example WellMet) can go on a controller button.
- Game actions (Bags, Map, Target nearest enemy, Extra action and more) are `FCT:` macros, tracked per character across the account. Macros you made yourself are never touched.
- Moved actions are stored in empty slots of keyboard action bars 6–8 (slots 145–180), which the Gamepad UI never shows, and freed when you clear the button.

### Touch bars
- Two bars of tap buttons on the left and right screen edges, for Steam Link on a phone or tablet. Off by default.
- The **Touch** tab sets 1–12 buttons per bar, their size, spacing, distance from the edge, height and opacity, with a live preview, and when they show: always, with the Gamepad UI, in combat, or never.
- Touch buttons look and behave like native crossbar slots.

### Glyphs
- Bar hints, class prompts, the on-screen legend and the targeting markers show the buttons you press. With both targeting roles on one side, the marker splits into a friendly and a hostile half.
- Moved actions show their icon on their new button, pressed in like a native slot.
- Xbox letters, PlayStation shapes and Nintendo glyphs follow the active controller and switch live.
- A one-time notice explains that the world's Interact prompts keep the game's default button, and how to hide them.

### Controllers
- DualSense, DualShock 4, Xbox, Switch Pro and Steam Input virtual pads are recognised by vendor or by the game's button style.
- An unrecognised pad gets controller type cards: PlayStation, Xbox, Switch or Custom. On Steam Link, Xbox is suggested.
- Controller setup (`/fct detect`): a guided "press each button" wizard that teaches the game every button of an unknown controller, then lets you pick its glyph style. A rejected press names the step that already uses it. Reset detection undoes it.
- Several pads, or Steam mirroring a physical pad: the addon follows the pad you're pressing.
- Each controller keeps its own layout. **Not now** in the first-start guide is remembered per controller.

### Settings windows
- Three tabs, **Bindings**, **Modifiers** and **Touch**, in WoW Forever's own window look, switched with L1/R1.
- Driven entirely with the D-pad, with a focus cursor, tooltips and footer hints.
- First-start guide: welcome, choose your layout, try it, face actions, done.
- Open them on the controller (hold L2 + R2, press Create, View or Minus), from the addon's minimap button, the minimap AddOns menu, Options → AddOns → Forever Controller Tweaks (Open Settings, Run setup guide), a key binding or `/fct` (`/controllertweaks`).
- Opened from Options, the Options window goes invisible underneath and comes back when you close the settings.
- Windows scale down to fit small or 4:3 screens and large UI scales.
- `/fct selftest` collects details for bug reports. `/fct release` clears the addon's hidden slots and `FCT:` macros before you uninstall.
