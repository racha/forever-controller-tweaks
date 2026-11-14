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
- **Options → AddOns → Forever Controller Tweaks**: **Open Settings**, or **Run setup guide**. Options goes invisible underneath the settings and comes back when you close them.
- **Key Bindings → AddOns → Forever Controller Tweaks**, to put it on a key of your choice.
- `/fct` or `/controllertweaks`.

The settings open on the **Bindings** tab, and only out of combat. If combat starts while they're open, they close and offer to resume when combat ends.

In every window:

- **D-pad:** move the focus. Hold a direction to repeat. The sticks don't move the focus.
- **Cross:** select.
- **Circle:** back or close.
- **L1 / R1:** switch tabs: Bindings, Touch, Keyboard, Rings (the modules' tabs show only while that module is on).
- **Triangle:** **More**, the same menu on every screen: presets, undo, controller type and setup, Learn, keyboard settings (with the Keyboard module), minimap icon and reset.

The footer always lists the buttons you can use, and tooltips explain the focused item.

## Modules

Forever Controller Tweaks comes as the main addon plus three modules, all in the one download. In the game's **AddOns** list the modules sit under **Forever Controller Tweaks**:

| Module | What it adds |
|---|---|
| **Forever Controller Tweaks: Touch** | The touch bars and the **Touch** tab. |
| **Forever Controller Tweaks: Keyboard** | The on-screen keyboard, its suggestions, the **Keyboard** tab and the keyboard entries in More and Options. |
| **Forever Controller Tweaks: Rings** | Action rings, the **Rings** tab, `/fct rings` and **Open ring** in the action picker. |

The main addon (bindings, modifiers, glyphs, controller setup) works on its own. To turn a module off, untick it in the AddOns list (or on the character screen's **AddOns** button) and `/reload`. Its tab, menu entries and commands go away; its settings stay saved and come back when you turn it on again. A module needs the main addon, so turning the main addon off turns them all off.

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

- **On / Off** and **Show** in the header. Show can be **Always**, **Gamepad UI** (while it's on), **In combat** or **Never**.
- The middle shows your screen with both bars at their real size and place.
- The edge columns list each bar's buttons, with four cells per button: one per bar (top, left, right, bottom), like the Bindings rows. A tap uses the action for the bar your modifiers have open. An empty cell hides its button on that bar. **Cross** opens the action picker, **Square** clears a cell.
- Under the preview, switch between **Left bar** and **Right bar**, then D-pad left / right change that side's buttons per bar (1–12), button size, spacing, distance from the edge, up / down, opacity, **Shape** (Circle or Square) and **Empty buttons** (Hide or Show).

Touch buttons look and behave like native crossbar slots. They're saved per character, and they work in combat.

## Keyboard

An on-screen keyboard for chat and text boxes, while the Gamepad UI is on. It opens when a text box gets the focus: with **Open → With the controller** only when you're using the controller, or **Always**.

- **Typing:** the letters sit in clusters of four around the disc. Point a stick at a cluster and press the face button for the letter. **L1** is Shift, **L2** Symbols. The hub has Space, Send, Erase and Close, each on a face button.
- **Suggestions** show in the tab beside the disc. **D-pad up / down** choose, **R1** inserts. A word goes in with a space, so pressing R1 again takes the next word.
  - An empty chat box shows quick phrases for where you are and what's happening: 263 lines for 25 situations, such as a ready check, a resurrect, a dungeon, a city or your guild.
  - Lines aimed at you in chat get replies, on the right channel: "inv?", "LF healer", "ready?" and 125 other phrases are recognised.
  - The quest you follow adds its progress, at most two lines: "Need 5 more Wolf Pelts", "Done with the quest, turning in".
  - While you type: word completion, a correction for a typo, the next word (it learns how you write), and shorthands such as lf, brb and omw.
  - Other boxes get their own list: item names in bag search, names in mail "To" and /who, nothing in number boxes.
- Nothing is ever sent for you, and nothing leaves your PC. Only your own sent messages are learned from.
- **Keyboard tab:** On / Off, when it opens, **Layout** (Ring or Compact), **Scale**, **Word suggestions** on or off, **Position** (Auto places it between the text box and the screen centre, clear of the chat and your bars; Centre; or Custom with offsets), every button, and **Reset keyboard to defaults**.
- A few boxes the game blocks addons from typing into (the Options search, the Group Finder's boxes, spellbook search) are left to a real keyboard; the keyboard says so instead of opening. Slash commands other than channel switches (`/s`, `/p`, `/g`, `/w` …) need a real keyboard.

## Rings

Radial menus of actions you build yourself. Open the **Rings** tab, or `/fct rings`.

- **New ring** adds one, up to 12. **Rename**, **Icon** (a grid of every macro icon) and **Delete** work on the selected ring.
- **Slots:** 4 to 12. **Cross on a slot** opens the action picker: spells (with Highest Rank), items, toys, mounts, macros, game actions and other addons' bindings.
- **Stick:** which stick aims, per ring. **Right**, **Left**, or **Dynamic**: a ring opened from a D-pad button aims with the right stick, one opened from a face button with the left.
- **Using a ring:** put **Open ring** on any face, D-pad or touch cell in Bindings or Touch. Hold the button, aim with the stick, release to use the lit slot. Release with the stick centred to cancel. The other stick keeps moving or looking, and the aiming stick is held back after release until it's centred. Works in combat.
- **On a touch button:** a tap opens the ring, a tap on a slot uses it, a tap outside closes it.
- Slots show cooldowns, charges, range and whether they're usable. Rings are shared by all your characters and use no hidden action slots.

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
