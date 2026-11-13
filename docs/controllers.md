# Controllers

Forever Controller Tweaks works with any controller WoW Forever can see. Known controllers work right away. For others, you pick the controller type once, or teach the game every button.

## Support

| Controller | Recognised by | Glyphs | Status |
|---|---|---|---|
| DualSense (PS5) | Sony vendor ID | PlayStation shapes | Tested |
| DualShock 4 (PS4) | Sony vendor ID | PlayStation shapes | Supported, not yet tested |
| DualSense Edge | Sony vendor ID | PlayStation shapes | Supported. Paddles not yet tested |
| Xbox Series / Xbox One | Microsoft vendor ID | Xbox letters | Tested |
| Xbox Elite | Microsoft vendor ID | Xbox letters | Supported. Paddles not yet tested, see below |
| Switch Pro | Nintendo vendor ID | Nintendo (B at the bottom) | Supported, not yet tested |
| GameSir X5 Lite over Steam Link | the controller type you pick (Xbox suggested) | Xbox letters | Tested |
| Other pads on Steam Input (Steam Link, Big Picture) | the game's button style, or the type you pick | follows it | Supported |
| Steam Deck | the game's button style | follows the game | Supported, not yet tested |
| Anything else | the type you pick, or controller setup | your choice | Supported |

"Tested" means the full in-game checklist ([TESTING.md](TESTING.md)) passed on that controller.

## How a controller is recognised

- **Vendor first.** Sony, Microsoft and Nintendo each make one family of pads, so their vendor ID decides the drawing, the glyphs and the raw button numbers.
- **Then the game's button style.** Steam's virtual controller can stand in for any pad, so the addon uses the button style the game reports for it.
- **Then you.** If neither is certain, the addon asks which kind of controller it is (below) instead of guessing.
- **Several pads.** When Steam mirrors a physical pad, or two pads are connected, the addon follows the one you're pressing.
- **One layout per controller.** Each vendor/product pair keeps its own layout and bindings. A Steam virtual pad and the physical pad behind it are separate. **Not now** in the first-start guide is remembered per controller too.

## Controller type cards

An unrecognised controller gets four cards when you first log in with it:

| Card | Buttons |
|---|---|
| PlayStation | Cross, Circle, Square, Triangle; L1 and R1, L2 and R2 |
| Xbox | A, B, X, Y; LB and RB, LT and RT |
| Switch | B, A, Y, X; L and R, ZL and ZR |
| Custom | Press each button once (controller setup) |

On Steam Link, **Xbox** is marked **Suggested**: Steam's virtual controller usually behaves like an Xbox pad. A controller that reports its own style gets that card suggested instead.

Change it later in **More → Controller type**, or with `/fct family xbox`, `playstation`, `switch` or `reset`.

## Controller setup ("press each button")

For a controller the cards don't cover, or one whose buttons come out wrong:

- `/fct detect`, **More → Detect controller buttons**, or the **Custom** card;
- press each control once, about a minute in all;
- choose the glyph style.

The addon then writes a complete controller config for that pad through the game's own controller config. After that, the game reads every button correctly. **Reset detection** removes it again.

Controller setup needs a **keyboard or mouse** for Skip, Back, Save and Cancel, because it records every controller button you press: Space skips, Backspace goes back, Enter saves and Esc cancels.

## Back paddles

- **DualSense Edge:** the back buttons arrive as raw buttons 16–19 and can take any role.
- **Xbox Elite:** depending on the driver, the paddles may arrive as controller buttons or as keyboard keys. Only controller buttons can take a role, because the game's modifiers listen only to the pad. If they arrive as keys, Learn controller won't detect them. Map the paddles to other buttons in the Xbox Accessories app or Steam Input instead.
- **Steam Deck:** the back grips (L4/L5/R4/R5) are mapped by Steam Input. Map them to pad buttons there, then use them in the addon.

Paddle support is untested on real hardware. Reports are very welcome.

## Steam Link and Steam Input

1. Add WoW Forever to Steam as a non-Steam game, and start it through Steam.
2. Connect the controller to Steam Link (or the Steam client).
3. Log in. If the addon asks which controller it is, pick **Xbox** (suggested) unless you know better.
4. `/fct selftest` shows the device name, vendor, product and button style.

Keep Steam Input's layout simple, a plain gamepad layout. The addon does the remapping in game.

**Touch bars** are made for Steam Link on a phone or tablet: a tap on screen arrives as a mouse click. Turn them on in the **Touch** tab and put your most-used spells there.

## Reporting a controller

Open an [issue](https://github.com/racha/forever-controller-tweaks/issues) with:

- the controller's name, and how it's connected (USB, Bluetooth, Steam Link);
- the lines `/fct selftest` prints;
- which controller type or setup you used, and anything that still felt wrong.

The vendor and product IDs from the self-test let the addon recognise that controller in a later version.
