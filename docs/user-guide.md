# Forever Controller Tweaks user guide

This guide uses PlayStation names: Cross, Circle, Square, Triangle, L1/R1 and L2/R2. On Xbox those are A, B, X, Y, LB/RB and LT/RT. On Switch they're B, A, Y, X, L/R and ZL/ZR. The addon goes by position, so the bottom face button is always "Cross" here.

## How the crossbar works

WoW Forever's crossbar has a top bar plus three bars you open by holding modifiers. You can also hold a button for targeting:

| You hold | Game default | Left = bars, Right = targeting |
|---|---|---|
| nothing | TOP bar | TOP bar |
| L2 | LEFT bar | LEFT bar |
| R2 | RIGHT bar | HOSTILE targeting |
| L2 + R2 | BOTTOM bar | — |
| L1 | FRIENDLY targeting | RIGHT bar |
| R1 | HOSTILE targeting | FRIENDLY targeting |
| L1 + R1 | SHORTCUTS | — |
| L1 + L2 | — | BOTTOM bar |
| R1 + R2 | — | SHORTCUTS |

The addon moves these four roles (**left bar, right bar, friendly targeting, hostile targeting**) between L1, R1, L2, R2 and the back paddles. Holding both bar buttons always gives the bottom bar, and holding both targeting buttons gives shortcuts.

Each bar has eight buttons: the four face buttons and the four D-pad directions. The crossbar has three pages of bars.

## First start

1. Turn on **Options → Gamepad → Enable Gamepad UI (Beta)**.
2. Log in with your controller connected. A short guide opens.
   - If the game doesn't recognise the controller, the guide first asks which kind it is. See [Controller type](#controller-type).
   - **Not now** keeps the game's layout. The guide won't ask again for that controller. `/fct setup` runs it any time.
3. **Choose your layout:**
   - **Game default:** nothing changes.
   - **Left = bars, Right = targeting:** the left side opens bars, and the right side targets.
   - **Set it up myself:** press the button you want for each role, one at a time.
4. **Try it:** hold each button and watch what it opens light up.
5. **Face actions** (optional): put Jump, Interact, Back or Inspect, or any other action, on a first-page face button, or skip this.
6. **All set.**

## Opening the settings

- **On the controller:** hold **L2 + R2** and press **Create** (PlayStation), **View** (Xbox) or **Minus** (Switch). L2 and R2 here are the physical triggers, whatever your layout gives them.
- The addon's **minimap button**. Drag it to move it, or hide it from **More** (Triangle).
- The minimap **AddOns** menu.
- **Key Bindings → AddOns → Forever Controller Tweaks**, to put it on a key of your choice.
- `/fct` or `/controllertweaks`.

The settings open on the **Bindings** tab, and only out of combat. If combat starts while they're open, they close and offer to resume when combat ends.

In every window:

- **D-pad:** move the focus. Hold a direction to repeat. The sticks don't move the focus.
- **Cross:** select.
- **Circle:** back or close.
- **L1 / R1:** switch tabs: Bindings, Touch, Keyboard, Rings and Tweaks (Touch, Keyboard and Rings show only while that module is on).
- **Triangle:** **More**, the same menu on every screen: presets, undo, controller type and setup, Learn, keyboard settings (with the Keyboard module), minimap icon and reset.

The footer always lists the buttons you can use, and tooltips explain the focused item.

**Settings controls.** The settings rows use the game's own controls, one value per row. **D-pad up / down** move between rows. On a **slider** or **dropdown**, **D-pad left / right** change the value; on a **checkbox**, **Cross** turns it on or off. On the Tweaks tab, left / right at the end of a dropdown or slider move on to the next column.

## Modules

Forever Controller Tweaks comes as the main addon plus three modules, all in the one download. In the game's **AddOns** list the modules sit under **Forever Controller Tweaks**:

| Module | What it adds |
|---|---|
| **Forever Controller Tweaks: Touch** | The touch bars and the **Touch** tab. |
| **Forever Controller Tweaks: Keyboard** | The on-screen keyboard, its suggestions, the **Keyboard** tab and the keyboard entries in More and Options. |
| **Forever Controller Tweaks: Rings** | Action rings, the **Rings** tab, `/fct rings` and **Open ring** in the action picker. |

The main addon (bindings, modifiers, glyphs, controller setup and the **Tweaks** tab) works on its own. To turn a module off, untick it in the AddOns list (or on the character screen's **AddOns** button) and `/reload`. Its tab, menu entries and commands go away; its settings stay saved and come back when you turn it on again. A module needs the main addon, so turning the main addon off turns them all off.

With **Rings** off, a button that holds **Open ring** does nothing. Its cell is greyed in Bindings and Touch, and its tooltip says the Rings module is off.

## Bindings

The controller is drawn in the middle, with one row per button at the window's edges, placed where that button sits on the pad. Each face and D-pad row shows the button's glyph and four cells, one per bar: top, left, right and bottom. At the top of each side are the bumper and trigger rows (and paddle rows, if your pad has paddles), where their roles are set. The focused row draws a gold line to its button on the drawing.

- **Pages:** the header shows **Page 1 of 3**. **L2 / R2** switch pages. If a stance or pet bar replaces a bar on that page, a note says so.
- **Cross on a face or D-pad cell** opens the action picker.
- **Square** clears a cell. **More → Undo** puts back the last clear.
- **Cross on a bumper or trigger row** opens its role list. See [Modifiers](#modifiers).
- A back paddle with no role gets four cells too. See [Back paddles](#back-paddles).
- On a cell that holds the game's own action, **Restore default action** puts it back after a change.

### Any action on any button

Every face and D-pad cell, on every bar, can hold:

- spells and pet spells, items, toys, mounts and equipment sets;
- your macros;
- game actions: Bags, Map, **Toggle FPS**, Target nearest enemy, Extra action and more;
- **Jump, Interact, Back and Inspect**. Interact keeps hold-to-loot, and Jump keeps swim up and stop;
- key bindings from other addons, from the **AddOns** category (for example WellMet);
- **Open ring** for any of your [action rings](#rings).

To clear your target with one press, put **Clear target** (Targeting category) on any face or D-pad button, back paddle, touch button or ring slot. Start keeps opening the menu wheel, as it always does.

A moved action looks and works like a native slot. It shows cooldowns, range, mana, charges, proc glow and its tooltip, and you can click it with the mouse.

In a vehicle, or while a pet or possess bar is up, the face buttons keep the game's own actions.

### Back paddles

On a pad with back paddles (Xbox Elite, DualSense Edge), each paddle is either a modifier or an action button.

- **Modifier:** give it a role (Left bar, Right bar, Friendly or Hostile targeting) like a bumper or trigger. It then shows as a role row.
- **Action button:** set its role to **None** (the role list says "use it for actions"). The row turns into four cells, one per bar, like a D-pad row. Each cell takes anything from the action picker, for example Jump on the paddle alone and a heal on **RT + paddle**.
- On a paddle's cell, **Triangle → More** has the paddle's role list first. Giving a role to a paddle that holds actions asks first. The actions stay saved and come back when you set the role to None again.
- A paddle's cells are the same on every crossbar page, since a paddle has no crossbar slot. A bar with an empty cell does nothing on that paddle. A shown targeting bar or stance bar doesn't change what a paddle does.
- In a vehicle, an override or possess bar, or a pet battle, the paddles do nothing, like the moved face actions.
- Paddle rows show only when the addon knows your pad has paddles: an Xbox Elite or DualSense Edge, or any pad whose paddles you taught it with **Detect controller buttons**.

### Action picker

- **L1 / R1** switch categories: Spells, Items, Mounts, Macros, Movement, Targeting, Combat, Windows, Misc, AddOns and Rings.
- **L2 / R2** page through long lists. Hold the D-pad to scroll faster.
- **Cross** assigns the action, **Triangle** shows its details, **Square** clears the cell, and **Circle** closes the picker.
- An entry that can't go on this cell is greyed out. Select it to read why.

**Spell ranks.** A spell with several ranks shows as one row. Cross opens its ranks page:

- **Highest Rank** always casts your best rank, and moves up by itself when you learn a new one;
- or pick one specific rank, for example a cheap low rank for healing.

Circle goes back to the list.

### Where actions are stored

- Actions on the game's own crossbar slots go straight into those slots, as if you had dragged them there.
- Actions moved onto other face or D-pad cells, and touch bar buttons, are stored in **empty** slots of keyboard action bars 6–8 (slots 145–180). The Gamepad UI never shows those bars. Only empty slots are used, and they're freed when you clear the cell. If you play with a keyboard and use those bars, you'll see them there.
- Game actions are small macros named `FCT:Bags`, `FCT:Map` and so on. The addon creates them in your account macros (or character macros when those are full) and deletes one only when no character uses it any more. Your own macros are never changed, even one you name `FCT:…`.
- Bindings are saved per character and per controller.

## Modifiers

Roles are set on the Bindings screen, in the bumper, trigger and paddle rows at the top of each side. Press D-pad up from the top face or D-pad row to reach them.

- **Cross on a row** opens the role list: Left bar, Right bar, Friendly targeting, Hostile targeting or None. If another button already has that role, the two swap, and a note under the drawing says so.
- **Presets** are first in **More**: **Game default** and **Left = bars, Right = targeting**. The header names the active one, or **Custom** for your own roles.
- **More** also has:
  - **Setup guide:** runs the first-start guide again. Its "set it up yourself" step runs on the Bindings screen.
  - **Controller type:** PlayStation, Xbox, Switch or Custom. See below.
  - **Detect controller buttons** and **Reset detection:** see [Controller setup](#controller-setup).
  - **Learn controller:** use it if a bumper or trigger does the wrong thing. Press each button when asked, and the addon learns which raw input it sends.
  - **Reset:** the game's default roles and face actions for this controller. Your crossbar actions stay.
  - **Show / Hide minimap icon.**

## Touch

Two bars of tap buttons on the left and right edges of the screen, for playing through Steam Link on a phone or tablet: a tap there is a click. They're **off** until you turn them on.

- **On / Off** and **Show** are the first rows under the preview. Show can be **Always**, **Gamepad UI** (while it's on), **In combat** or **Never**.
- The middle shows your screen with both bars at their real size and place.
- The edge columns list each bar's buttons, with four cells per button: one per bar (top, left, right, bottom), like the Bindings rows. A tap uses the action for the bar your modifiers have open. An empty cell hides its button on that bar. **Cross** opens the action picker, **Square** clears a cell.
- Under them, switch between **Left bar** and **Right bar**, then D-pad left / right change that side's buttons per bar (1–12), button size, spacing, distance from the edge, up / down, opacity, **Shape** (Circle or Square) and **Empty buttons** (Hide or Show).

Touch buttons look and behave like native crossbar slots. They're saved per character, and they work in combat.

## Keyboard

An on-screen keyboard for chat and text boxes, while the Gamepad UI is on. It opens when a text box gets the focus: with **Open → With the controller** only when you're using the controller, or **Always**.

- **Typing:** the letters sit in clusters of four around the disc. Point a stick at a cluster and press the face button for the letter. **L1** is Shift, **L2** Symbols. The hub has Space, Send, Erase and Close, each on a face button.
- **Suggestions** show in the tab beside the disc. **D-pad up / down** choose, **R1** inserts. A word goes in with a space, so pressing R1 again takes the next word.
  - An empty chat box shows quick phrases for where you are and what's happening: 137 built-in lines for 31 situations plus **Always**, such as a ready check, a resurrect, a dungeon, a city or your guild.
  - Lines aimed at you in chat get replies (76 of them), on the right channel. 31 rules recognise 165 phrases and words, such as "inv?", "LF healer" and "ready?".

  - The quest you follow adds its progress, at most two lines: "Need 5 more Wolf Pelts", "Done with the quest, turning in".
  - While you type: word completion, a correction for a typo, the next word (it learns how you write), and shorthands such as lf, brb and omw.
  - Other boxes get their own list: item names in bag search, names in mail "To" and /who, nothing in number boxes.
- **Your own quick messages:** **Quick messages** button at the top right of the Keyboard tab. The situations are on the left (**Always** shows everywhere, the number is how many lines of your own it has); **D-pad up / down** pick one, **right** goes to its lines: yours first (marked **Yours**), then the built-in ones, then **Add a line**, which you type with the keyboard; **Send** saves, **Close** cancels. On your line, **Cross** edits, **Square** deletes, **Triangle** picks it up to move. **Square** on a built-in line hides it; **Restore hidden built-in lines** brings them back. Up to 20 of your own per situation. The suggestion list beside the keyboard shows the fill-ins (such as `{target}`, your target's name) with what each gives right now; type `{` or a fill-in's first letters to narrow them, **R1** puts one in. Your lines come first in that situation's suggestions, and hidden built-in lines are left out. Reset keyboard to defaults keeps them.
- **Sending chat:** **Send** puts your line out through the addon's own secure button, so the game's chat box itself is never written to. The keyboard closes, and the chat box stays open and empty; one more **Circle** closes it. Any Chat Style (Classic or IM) works. A slash command other than a channel switch stays in the box with a note.
- **In combat** only party, raid, instance, guild and whispers can be sent. A say, yell or channel line stays in the box with a note, and you send it after the fight.
- Nothing is ever sent for you, and nothing leaves your PC. Words are learned only from chat you send.
- **Keyboard tab:** **On**, **Open** (With the controller or Always), **Layout** (Ring or Compact), **Scale** and **Word suggestions**, with a preview of the keyboard. **Reset keyboard to defaults** is in **More** (Triangle). The keyboard places itself between the text box and the screen centre, clear of the chat and your bars, and its buttons are fixed.
- A few boxes the game blocks addons from typing into (the Options search, the Group Finder's boxes, spellbook search) are left to a real keyboard; the keyboard says so instead of opening. Slash commands other than channel switches (`/s`, `/p`, `/g`, `/w` …) need a real keyboard.

## Rings

Radial menus of actions you build yourself. Open the **Rings** tab, or `/fct rings`.

- **New ring** adds one, up to 12. **Rename**, **Icon** (a grid of every macro icon) and **Delete** work on the selected ring.
- **Slots:** 4 to 8. **Cross on a slot** opens the action picker: spells (with Highest Rank), items, toys, mounts, macros, game actions and other addons' bindings.
- **Stick:** which stick aims, per ring. **Right** (the default for a new ring), **Left**, or **Dynamic**: a ring opened from a D-pad button aims with the right stick, one opened from a face button with the left.
- **Show:** how the ring stays up, per ring.
  - **Toggle** (the default): a press opens the ring, and it stays open until you use a slot, press its button again or press **Circle**.
  - **Hold:** the ring shows only while you hold its button.
- **Style:** how the ring looks, per ring. **Full** (the default) is the game's radial wheel, with each slot's name. **Compact** is the small round picker the game uses for flyouts (the aura and stance picker). It opens on the crossbar button you pressed, with the ring's icon and that bar's modifier buttons in the middle; the slot you aim at gets the highlight and an arrow points at it. From a touch button it opens in the middle of the screen. Both aim the same way.
- **Using a ring:** put **Open ring** on any face, D-pad or touch cell in Bindings or Touch. In **Full** the ring looks like the game's own radial menu. Flick the stick to a slot and let the stick go to use it. Letting go of the button and the stick at the same moment uses it too.
  - **Toggle:** **Cross** uses the lit slot. Letting go of the button while aiming uses the slot; with nothing aimed the ring stays open, so you can still aim. **Circle**, a stick press or the ring's button again closes it without using anything.
  - **Hold:** let go of the button to use the slot you aim at. With nothing aimed, the ring just closes.
  - If the stick was already pushed when the ring opened, that slot isn't used until you centre the stick or move it off that slot.
- While a ring is open the addon turns on the game's stick-as-buttons setting (`GamePadStickAxisButtons`) and puts your own value back when it closes. The other stick keeps moving or looking, and the aiming stick is held back after release until it's centred. Works in combat.
- **On a touch button:** a tap opens the ring, a tap on a slot uses it, a tap outside closes it.
- Slots show cooldowns, charges, range and whether they're usable. Rings are shared by all your characters and use no hidden action slots.
- `/fct ringlog` prints the last ring events. Add those lines to a ring bug report.

## Healer mode

Any button that holds a heal can open a ring of your group instead: aim at someone and let go to cast on them.

- **Turning it on:** in **Bindings** focus the cell and press **Triangle**: **Healer mode: Off** is the first row in More. Pick it to turn it on, and again to turn it off. In the **Touch** tab it works the same on a touch button. A green cross marks the button in Bindings, in Touch and on your crossbar.
- **What can use it:** spells, spell groups (Highest Rank) and items. Anything else shows the row in grey, with what the button holds.
- **A crossbar slot:** turning it on keeps the spell where it is. While Healer mode is on, the button opens the ring on every crossbar page. Turn it off and the slot casts on your target again.
- **Using it:** hold the button. A small round ring opens on it, with the spell in the middle and 7 places: **You** at the top, then **Party 1** to **Party 4**, **Target** and **Focus**, clockwise. In a raid the party places are your own subgroup. Aim with the right stick on a D-pad button or a paddle, the left stick on a face button. The person you aim at gets the gold border and the game's own tooltip. Let go to cast on them; let go in the middle and nothing is cast.
- **Who can be picked:** anyone there who can be helped, dead allies too (for a resurrection). An empty place, a hostile target or a missing focus can't be picked, and nothing is cast there.
- **Each place shows** the portrait, a health ring in the class colour, the role icon, and:
  - incoming heals as a teal stretch after the health;
  - a shield as a thin outer arc;
  - a heal absorb as a darker stretch at the end of the health;
  - a red pulse under 30% health;
  - a tinted glow and the type icon when they have a debuff you can dispel.
- **Touch:** a tap opens the ring, a tap on a place casts there.
- There are no settings: it always shows while held and always aims with the stick for that button. It works in combat; switching it on or off is out of combat. It needs the Rings module.

## Tweaks

Small conveniences, on the **Tweaks** tab (the last tab). **Each one is off until you turn it on**, they're saved for all your characters, and they work only while the Gamepad UI is on. The tab has four columns; hover or focus a row for its tooltip.

### Bags & vendors

- **Sort bags button:** a Sort button on your bags. With the controller, use **Clean Up** in the bag menu, or the picker's **Sort bags** action.
- **Sell junk:** sells your grey items when you talk to a merchant. One chat line lists what sold and for how much.
- **Repair:** repairs your gear at a merchant who repairs. **Use guild funds first** pays from the guild bank when the guild allows it, else from your own money.
- **Buy a full stack:** a **Stack** button on stackable merchant items (for touch and mouse). With the controller, put the picker's **Buy a full stack** action on a button and press it while the cursor is on the item. A stack that costs 150 gold or more is left to the game's own Multi-buy, which asks first. It says when the item is sold out, and buys only what your money covers.

### Quests & NPCs

- **Skip one-option talk:** when an NPC offers only one thing, it's picked for you: a single quest, or a vendor, trainer, flight map or bank. It never picks a teleport, an event start, a story skip, an option that costs money, or an ignored quest. Once per conversation.
- **Trainer: Learn all:** a **Learn all** button on the trainer for every skill you can afford.
- **Mail: Open all:** an **Open all** button on the mailbox. It skips cash-on-delivery mail and stops when your bags are full.

### Rumble

- **Rumble on events** turns it on. **Strength** sets how strong every rumble is (10% to 100%); Cross on it plays a Double tap.
- Each group has its own pattern: Tap, Double tap, Triple tap, Long buzz, Heartbeat, Ramp up, Fade out, or **Off**. **D-pad left / right** change it, **Cross** plays it.

| Group | Rumbles for | Starts as |
|---|---|---|
| Group | a ready check, a group invite, a summon, a resurrection offer | Double tap |
| Whisper | someone whispers you | Tap |
| Trade & duel | a trade or duel request | Tap |
| Danger | you die, get stunned or feared, gain aggro, or your cast is interrupted | Long buzz |
| Enemies | an enemy player's name plate shows (needs enemy name plates on) | Double tap |
| Rare nearby | a rare on the minimap or by its name plate | Heartbeat |
| Level ups | a level up or an achievement | Ramp up |
| Procs | a spell on your bars lights up, your target dies, or you land a critical strike (solo) | Off |

- Only events you still have to answer rumble: an invite or duel a tweak already answered doesn't.
- Busy events wait before they rumble again: whispers, invites and trades 3 seconds, enemy players 10.
- The game's own vibration setting isn't read, so turn Rumble on events off if you don't want it.

### Controller

- **Low battery warning:** one chat line when the controller's battery runs low.
- **Battery on the minimap:** a round button on the minimap's ring, next to the others, with the controller's charge. Hidden for pads that don't report one.
- **Rare nearby alert:** a line on screen and a rumble when a rare is near. Once per rare, never in a fight, on a flight or while dead.
- **Light bar:** **Game default**, **Class colour** or **Custom**, with **Colour** picking one of 10 colours. **Combat flash** turns the light red while you're in combat. For pads with a light bar, such as the DualSense; Steam may take the light over.

### Loot & gear

- **Fast loot:** takes all loot at once. Bind-on-pickup items still ask; with full bags only coins are taken.
- **Pass on unusable rolls:** passes on armour or weapons your class can never use. When it's unsure, you roll.
- **Upgrade arrows:** a green arrow on gear with a higher item level than what you wear there, in your bags, the loot window and loot rolls.
- **Wear quest rewards:** after a quest, an upgrade reward gets a card for 10 seconds. Hold the top face button (Triangle) for 1 to 3 seconds to wear it.

### Group & social

- **Accept friend & guild invites:** joins a group when a friend, Battle.net friend or guild member invites you. Never a role check, a quest session invite, or an invite that would drop your dungeon or PvP queue.
- **Decline duels:** turns down every duel request.
- **Accept resurrect and summon:** out of combat only. A resurrection is accepted unless it brings resurrection sickness. A summon is accepted only from a friend or guild member, and never while you're inside an instance.
- **Whisper alert:** a card with who whispered you and how the message starts.

### Picker actions

These are in the action picker for any face, D-pad or paddle cell, touch button or ring slot:

| Category | Action | What it does |
|---|---|---|
| Combat | **Cancel** | Stops a cast, a ground target, and clears your target |
| Combat | **Best healing potion**, **Best mana potion**, **Best grenade** | Uses the best one in your bags you can use; works in combat |
| Movement | **Look behind (hold)** | The camera turns round while you hold the button |
| Windows | **Peek map (hold)** | The map shows while you hold the button |
| Targeting | **Mark next** | The next raid mark on your target, in kill order (skull, cross, square…), in combat too; back to skull after combat |
| Misc | **Sort bags** | Sorts your bags |
| Misc | **Buy a full stack** | Buys a stack of the merchant item under the cursor |
| Misc | **Eat & drink** | Your best food, and your best drink if you use mana; out of combat |
| Misc | **Quest item** | The item of the quest you follow, else of the nearest quest that has one |
| Misc | **Track nearest quest** | Tracks the nearest quest; press again for the next nearest |
| Misc | **Ready check**, **Pull countdown (5 s)** | The game's ready check and a 5-second countdown |
| Misc | **Minimap zoom** | Zooms the minimap in step by step, then back out |

The two hold actions work while you hold the button. On a touch button or ring slot a tap turns them on and off. The potion, grenade and food actions find items by their English names, so they need an English game client.

## Glyphs

The addon redraws the button hints so they match your layout: the glyphs under each bar, the class prompts, the targeting markers and the on-screen legend. When both targeting roles are on one side, that side's marker splits in two, friendly on top and hostile below. A moved action shows its icon on its new button.

The glyph style follows your controller: Xbox letters, PlayStation shapes or Nintendo.

**Interact prompts in the world** (over NPCs, herbs, ore and chests) always show the game's default Interact button, even after you move Interact. The game draws them from its own locked binding, which addons can't change. The addon tells you once when you move Interact. To hide those prompts, set **Options → Accessibility → Interact Key Icons** to **None**.

## Controller type

If the game doesn't recognise your pad, the addon asks which kind it is, with four cards:

- **PlayStation:** Cross, Circle, Square, Triangle; L1 and R1, L2 and R2.
- **Xbox:** A, B, X, Y; LB and RB, LT and RT. Suggested for controllers on Steam Link.
- **Switch:** B, A, Y, X; L and R, ZL and ZR.
- **Custom:** press each button once. This starts controller setup.

Change it later in **More → Controller type**, or with `/fct family xbox` (`playstation`, `switch`, or `reset` to forget it).

## Controller setup

Use this for a controller the cards don't cover, or one whose buttons come out wrong. Open it with `/fct detect`, **More → Detect controller buttons**, or the **Custom** card.

1. **Let go of the controller** while it calibrates (about a second).
2. **Press each button** when asked: face buttons, D-pad, bumpers, triggers, stick clicks, Start, Select, and the optional Home, Share and back paddles. For the sticks, push them all the way, then let go.
3. **Choose the button labels:** Xbox letters, PlayStation shapes or Nintendo.
4. **Done.** Then choose your layout.

Because every controller press is being recorded, you control the setup itself with the keyboard or mouse. The addon asks before it starts.

| Key | Does |
|---|---|
| Space | Skip a button |
| Backspace | Go back one step |
| Enter | Save at the end |
| Esc | Cancel |

Pressing a button that's already used shows which step uses it. Press a different one. **Reset detection** forgets the setup, and the game's default mapping comes back.

## Turning it off

- **Game default layout:** More → Game default, or `/fct preset native`.
- **Uninstalling:** type `/fct release` first. It empties the addon's hidden slots on keyboard bars 6–8 and deletes its `FCT:` macros. Then disable or delete the addon (and its three module folders) and restart. The controller config is cleaned up on logout, so the game is fully native.

## Troubleshooting

| Problem | Try |
|---|---|
| The addon says the Gamepad UI is off | Options → Gamepad → Enable Gamepad UI (Beta) |
| The controller isn't recognised | Pick its type from the cards, or `/fct detect` |
| A bumper or trigger does the wrong thing | More → Learn controller |
| The shortcut doesn't open the settings | Use `/fct` or the minimap button, then check the controller type |
| A game action does nothing | Check your macro list (Esc → Macros) for free slots |
| A moved action does nothing | Check keyboard bars 6–8 have free slots (slots 145–180) |
| Something was blocked | `/fct selftest`, then report it with `Logs/taint.log` (see CONTRIBUTING) |
| Everything is wrong | `/fct reset`, or disable the addon and restart |

For bug reports, run `/fct selftest` and include the lines it prints.
