# Changelog

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
