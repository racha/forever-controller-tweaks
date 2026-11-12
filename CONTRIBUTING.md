# Contributing to Forever Controller Tweaks

Thanks for helping. Bug reports, controller reports and pull requests are all welcome.

## Reporting a bug

Open an issue with:

1. What you did, what you expected and what happened.
2. The lines `/fct selftest` prints: your controller, its vendor and product ID, and the addon's state.
3. Any Lua error. Turn on errors with `/console scriptErrors 1`. If the game says something was blocked, also send the lines that name ForeverControllerTweaks from `Logs/taint.log` after `/console taintLog 2` and a `/reload`.

Please crop out character names and chat from screenshots.

## Layout

```
ForeverControllerTweaks/  the addon (this folder is the release zip)
  Core.lua                namespace, saved settings, events, queue, commands
  Device.lua              controller detection, controller type, learn, controller setup
  Layout.lua              pure layout model: roles, presets, the controller config it builds
  Remap.lua               writes the controller config (C_GamePad.SetConfig / ApplyConfigs)
  SlotView.lua            a native-looking crossbar slot drawn on the addon's own frame
  Face.lua                secure router: any action on any face or D-pad button, per bar
  Glyphs.lua              glyph overlay on the crossbar, mirrors of moved actions
  Actions.lua             action catalogue, spell rank groups, FCT: macros, hidden slots
  Touch.lua               on-screen touch bars
  Panel/                  the settings windows (Bindings, Modifiers, Touch, picker, guide, setup)
  Art/                    the addon's own textures
  tests/                  plain-Lua specs with WoW API stubs
docs/                     user guide, controllers, testing
site/                     GitHub Pages site
```

## Running the checks

You need Lua 5.1 (the game's version). Lua 5.4 works too. The specs avoid anything that differs between the two.

```bash
find ForeverControllerTweaks -name '*.lua' -exec luac -p {} +
for spec in ForeverControllerTweaks/tests/*_spec.lua; do lua "$spec" || echo "FAILED: $spec"; done
```

A spec prints nothing, or a short summary, when it passes, and stops with an assertion error when it fails. CI runs the same commands on every push and pull request.

Then test in game. [docs/TESTING.md](docs/TESTING.md) lists what to check.

## Taint rules

WoW blocks protected actions (casting, targeting, moving bindings) when addon code has touched Blizzard's interface in the wrong way. That's "taint". A single tainted call can break a player's Game Menu or action bars, so these rules are strict.

**The addon never:**

- calls or drives Blizzard's menus and dropdowns (`Menu`, `MenuUtil`, dropdown buttons), `StaticPopup_*`, `ShowUIPanel` / `HideUIPanel`, `UISpecialFrames`, the gamepad focus system (`FrameControlsManager`, `SmartNavigation_*`), `InputBindingManager`, or other addons' Settings pages;
- closes or hides Blizzard windows (Options included: every close path ends in `HideUIPanel`);
- writes CVars;
- writes Lua fields or tables on Blizzard objects, or hooks their scripts to change behaviour. Reading is fine.

**The only Blizzard writes allowed** are `SetAlpha` calls, each saved first and given back:

- on the crossbar's glyph textures, shoulder textures and class-action prompts, which go under the addon's own glyphs;
- on a crossbar slot's own regions while a mirror of a moved action stands on it, and on its macro name while it holds an `FCT:` macro;
- while the settings window is open: the Options window (when the settings were opened from it), an open tooltip and the gamepad focus arrow.

**The one Settings registration allowed** is the addon's own Options → AddOns page (`Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnCategory` in `Panel/Panel.lua`). It holds native button rows only, is registered once at login out of combat, and its buttons open the settings on the next frame.

**The addon builds its own instead.** Its windows, dialogs, pickers, focus cursor, minimap button and touch bars are its own frames. They use the game's art by atlas name, and its templates only where the template's code touches nothing but its own textures.

**Out of combat only:** `C_GamePad.SetConfig` / `ApplyConfigs` / `DeleteConfig`, override bindings outside restricted snippets, secure `SetAttribute`, `RegisterStateDriver`, `CreateMacro` / `EditMacro` / `DeleteMacro` and `PlaceAction`. Queue anything that needs these until combat ends. The one exception: the combat-start event handler can still write the controller config, because the lockdown starts right after it.

**Never touch what isn't ours.** That means controller configs without the addon's tag, macros not in the addon's registry (even ones named `FCT:…`), action slots the addon didn't fill, and other addons' bindings.

## Pull request checklist

- [ ] `luac -p` passes on every Lua file.
- [ ] Every `ForeverControllerTweaks/tests/*_spec.lua` passes. New logic in `Layout.lua`, `Device.lua`, `Remap.lua`, `Actions.lua`, `Face.lua`, `Glyphs.lua` or `Touch.lua` comes with a spec case.
- [ ] Lua 5.1 syntax only (no `goto`, `//`, `<const>`, `table.unpack` without a fallback).
- [ ] No forbidden call from the taint rules: `git grep -nE 'OpenMenu|SetupMenu|DropdownButton|StaticPopup_|ShowUIPanel|HideUIPanel|UISpecialFrames|SmartNavigation_|FrameControlsManager|SetCVar|Settings\.Register|/run |/script '` finds nothing new (the Options page registration in `Panel/Panel.lua` is the known exception).
- [ ] Tested in game with `/console taintLog 2`. `Logs/taint.log` has no line naming ForeverControllerTweaks, and no "blocked" message appeared.
- [ ] Every new window text is in the `UI.L` table (`Panel/Shared.lua`).
- [ ] New files are listed in `ForeverControllerTweaks.toc`.
- [ ] User-facing changes are in `CHANGELOG.md`, under a new version heading.
- [ ] No code or art copied from addons with an "All rights reserved" licence, or from Blizzard. MIT code is fine with credit.

## Releasing (maintainers)

1. In `CHANGELOG.md`, give the new version's heading its date: `## 1.1.0 — 2026-12-01`. The Release workflow refuses `unreleased` or `YYYY-MM-DD`.
2. Push a tag `v1.1.0`. The Release workflow builds the zip with the BigWigs packager, creates the GitHub release and uploads the zip to CurseForge. The version in the TOC comes from the tag.
