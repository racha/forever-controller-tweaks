-- Forever Controller Tweaks panel: pieces shared by the Bindings, Touch and onboarding windows.
-- Taint rule: nothing here drives Blizzard's Menu, StaticPopup, FrameControlsManager, SmartNavigation,
-- InputBindingManager or GamepadMode, and no Blizzard callback registry is written. Visual templates whose code is
-- pure (SettingsFrameTemplate's NineSlice, flat background and close button, InsetFrameTemplate,
-- SharedButtonSmallTemplate) are inherited; everything else is the same native art in the addon's own frames. The
-- controller drawing, its lines and the rings are the addon's own art. Positions are UI units from a window's top
-- left.
local _, ns = ...
local UI = {}
ns.UI = UI

local ART = "Interface\\AddOns\\ForeverControllerTweaks\\Art\\"
UI.ART = ART

UI.L = {
	BINDINGS_TITLE = "Controller Tweaks · Bindings",
	CUSTOM_TITLE = "Controller Tweaks · Set it up yourself",
	WELCOME_TITLE = "Welcome to Forever Controller Tweaks",
	CHOOSE_TITLE = "Controller Tweaks · Choose your layout",
	TRY_TITLE = "Controller Tweaks · Try it",
	FACE_TITLE = "Controller Tweaks · Face actions",
	DONE_TITLE = "Controller Tweaks · All set",
	LAYOUT_ON = "Controller Tweaks layout on",
	LAYOUT_NATIVE = "Game default layout",
	SETUP_GUIDE = "Setup guide",
	LEARN = "Learn controller",
	RESET = "Reset",
	CANCEL = "Cancel",
	SKIP = "Skip",
	SELECT = "Select",
	CLOSE = "Close",
	OK = "OK",
	DONT_SHOW_AGAIN = "Don't show again",
	INTERACT_MOVED = "Interact is now on %s.",
	INTERACT_GONE = "Interact is no longer on a face button.",
	INTERACT_PROMPTS = "%s The interact prompts over NPCs, herbs, ore and chests will still show %s: the game draws them from its own binding, which addons can't change.",
	INTERACT_HIDE = "To hide those prompts: Options > Accessibility > Interact Key Icons > None.",
	BACK = "Back",
	CONTINUE = "Continue",
	NOT_NOW = "Not now",
	BINDINGS = "Bindings",
	CLEAR_SLOT = "Clear slot",
	TOUCH_MISSING = "Touch bars are not in this build yet.",
	TOUCH = "Touch",
	TOUCH_TAB = "Touch bars",
	TOUCH_TITLE = "Controller Tweaks · Touch bars",
	TOUCH_HINT = "Buttons on the screen edges to tap on a touch screen (Steam Link).",
	TOUCH_ON = "On",
	TOUCH_OFF = "Off",
	TOUCH_ONOFF_TIP = "Turns both bars on or off.",
	TOUCH_SHOW = { always = "Always", gamepad = "Gamepad UI", combat = "In combat", never = "Never" },
	TOUCH_SHOW_TIP = "When the bars are on screen.",
	TOUCH_SHOW_LABEL = "Show",
	TOUCH_SLOTS = "Slots %d / %d",
	TOUCH_FULL = "All %d touch slots are in use: clear a button first.",
	TOUCH_LAYERS_LATER = "Modifier layers on touch buttons need a newer Touch build.",
	TOUCH_SUB_LAYER = "%s · button %d · %s bar",
	TOUCH_SIDE_TIP = "Which bar the settings below change.",
	TAB_BINDINGS = "Bindings",
	LEARN_BUTTON = "button %d",
	LEARN_AXIS = "axis %d",
	STEP_LESS = "Decrease",
	STEP_MORE = "Increase",
	UNNAMED_ACTION = "Action",
	TOUCH_SIDE = { left = "Left bar", right = "Right bar" },
	TOUCH_SUB = "%s · button %d",
	TOUCH_EMPTY = "Not set",
	TOUCH_SETTINGS = { count = "Buttons per bar", size = "Button size", gap = "Spacing", inset = "From the edge", offsetY = "Up / down", alpha = "Opacity", shape = "Shape", showEmpty = "Empty buttons" },
	TOUCH_CHOICES = { shape = { circle = "Circle", square = "Square" }, showEmpty = { [false] = "Hide", [true] = "Show" } },
	TOUCH_NO_CHARACTER = "Touch bars: no character yet, try again in a moment.",
	STEPPER_TIP = "D-pad left and right change it.",
	CHOICE_TIP = "D-pad left and right pick one.",
	NO_SLOT = "This button has no crossbar slot on this page.",
	RANKS_TIP = "%d ranks. Press to choose one.",
	OPEN_BINDINGS = "Open Bindings",
	HOLD_IDLE = "Hold a shoulder, trigger or paddle: what it opens lights up here",
	HOLD_BAR = "%s held · the %s bar is open",
	HOLD_TARGETING = "%s held · %s targeting",
	HOLD_SHORTCUTS = "%s held · SHORTCUTS",
	COMBAT = "Controller Tweaks opens out of combat only",
	NO_PAD = "no controller found; connect one and try again",
	EMPTY = "Empty",
	NONE = "None",
	FACE_SLOT = "First-page face button",
	CROSSBAR_SLOT = "Crossbar slot",
	PLACE_HELD = "Place the action you hold",
	CHOOSE_ACTION = "Choose an action",
	FACE_ACTION_NAMES = { interact = "Interact", inspect = "Inspect", back = "Back", jump = "Jump" },
	OVERRIDE_BARS = { GamepadStanceBarOverride = "Stance", GamepadPossessBarOverride = "Pet" },
	GAME_DEFAULT_SUFFIX = " · game default",
	NOT_BOUND = "Not bound",
	BAR_SUB = "%s bar",
	FACE_SUB = "%s bar · face action",
	GUIDE_HEADING = "Step %d of 4 · Press the button you want for %s",
	GUIDE_HINT = "If that button already has a role, the two swap automatically.",
	GUIDE_TARGET = { leftmod = "the LEFT bar", rightmod = "the RIGHT bar", friendly = "FRIENDLY targeting", hostile = "HOSTILE targeting" },
	GUIDE_WILL = { leftmod = "Will open the LEFT bar", rightmod = "Will open the RIGHT bar", friendly = "Will hold FRIENDLY targeting", hostile = "Will hold HOSTILE targeting" },
	GUIDE_WAITING = "Waits for its turn",
	GUIDE_NOT_SET = "Not set yet",
	ROLE_TIP = "Picking a role another button holds swaps the two.",
	CHANGE_ROLE = "Change role",
	PRESET_NATIVE = "Game default",
	PRESET_SPLIT = "Left = bars, Right = targeting",
	PRESET_CUSTOM = "Custom",
	ROLES_TITLE = "%s: role",
	ROLE_SWAPS = "swaps with %s",
	ROLE_TAKES = "takes it from %s",
	ROLE_TO_PADDLE = "moves to a free paddle",
	ROLE_NEEDS_BUTTON = "every role needs a button",
	ROLE_SWAPPED = "%s is now %s; %s is now %s.",
	PADDLE_SLOT = "Back paddle · the same on every page",
	PADDLE_SUB = "%s · %s bar",
	PADDLE_ROLE = "Role (in More)",
	PADDLE_ROLE_TIP = "Give this paddle a role, or keep None to run actions with it.",
	PADDLE_FOR_ACTIONS = "use it for actions",
	PADDLE_FOR_ACTIONS_TIP = "No role: the paddle runs its own action on each bar, like a face button.",
	PADDLE_ROLE_TEXT = "Give %s the %s role?",
	PADDLE_ROLE_SUB = "Its actions stay saved and come back when you set its role to None.",
	MORE = "More",
	GUIDE_CONFIRM = "Detected · press again to confirm",
	PRESET_TIP = "Sets every role at once.",
	BUTTON_TIPS = { "Runs the first-start guide again.", "Teaches Controller Tweaks which raw input each shoulder, trigger and paddle sends.", "Puts back the game's default roles and face actions." },
	DETECTED = "%s detected",
	WELCOME_LINE1 = "Forever Controller Tweaks lets you choose which shoulder, trigger and paddle buttons open the crossbar bars and targeting.",
	WELCOME_LINE2 = "You can also move Jump, Interact, Back and Inspect to other face buttons.",
	WELCOME_NOTE = "Not now keeps the game's own layout and won't ask again. You can open Controller Tweaks any time with /fct or %s.",
	CHOOSE_LINE = "Pick a starting point. You can change everything later.",
	CARD_NATIVE_LINE = "%s/%s open the bars, %s/%s target.",
	CARD_SPLIT_LINE = "The left side opens bars, the right side targets.",
	CARD_CUSTOM = "Set it up myself",
	CARD_CUSTOM_LINE = "Choose each button in the next step, one role at a time.",
	CARD_CUSTOM_NOTE = "Auto-swap: picking a button that already has a role swaps the two.",
	TRY_HEADING = "Hold each button to check it",
	TRY_IDLE = "What it opens lights up.",
	TRY_HOLDING = "What it opens lights up. Holding %s now:",
	FACE_HEADING = "Want to change Jump, Interact, Back or Inspect?",
	FACE_LINE = "Optional. These four sit on the first page of the crossbar. Press a slot to move a face action there or to put any spell, item or game action on it; change them later in Bindings too.",
	FACE_ITEM_TIP = "%s, first-page face button",
	SET_BY_ADDON = " · set by Controller Tweaks",
	MOVED_BY_ADDON = " · moved by Controller Tweaks",
	DONE_HEADING = "Your layout: %s",
	DONE_CHANGE = "Change it any time",
	DONE_LINES = { "Bindings: which button opens which bar (the shoulder and trigger rows),", "and what each button does on each bar." },
	COMPARTMENT_TIP = "Open Bindings",
	MINIMAP_SHORTCUT = "On the controller: %s.",
	MINIMAP_SHOW = "Show minimap icon",
	MINIMAP_HIDE = "Hide minimap icon",
	MINIMAP_TIP = "The Controller Tweaks button on the minimap ring; drag it to move it.",
	CONTROLLER_TYPE = "Controller type",
	CONTROLLER_TYPE_TIP = "Tell Controller Tweaks which layout this controller has, or teach it every button.",
	FAMILY_TITLE = "Which controller is this?",
	FAMILY_HEADING = "We couldn't recognise this controller. Which layout is it?",
	FAMILY_CARDS = { playstation = "PlayStation", xbox = "Xbox", switch = "Switch", custom = "Custom" },
	FAMILY_LINES = { playstation = "Sticks side by side, a large touchpad on top.", xbox = "Offset sticks, a round guide button on top.", switch = "Offset sticks, small + and - buttons.", custom = "Press each button once and Controller Tweaks learns them." },
	FAMILY_NAMES = "%s  %s   ·   %s  %s",
	FAMILY_MISSING = "Controller type can't be saved in this build yet.",
	SUGGESTED = "Suggested",
	FAMILY_SUGGESTED = { xbox = "Steam Link controllers usually work as Xbox.", playstation = "This controller says it works as PlayStation.", switch = "This controller says it works as Switch." },
	OPEN_WAYS = "Open Controller Tweaks: %s; Options > AddOns > Forever Controller Tweaks; the AddOns menu on the minimap; Key Bindings > AddOns > Forever Controller Tweaks; or /fct.",
	TOGGLE_HOLD = "hold %s, then press %s",
	HELP_MORE = " /fct bindings, /fct setup, /fct detect; /fct release before uninstalling.",
	CLEAR_TIP = "Empties this crossbar slot.",
	SHOWN_ACTION = "%s bar · %s",
	DETECT_TITLE = "Controller Tweaks · Controller setup",
	DETECT_STEPS = "Steps",
	DETECT_COUNT = "%d set · %d skipped · %d in all",
	DETECT_SKIPPED_ROW = "%s · skipped",
	DETECT_COUNTER = "Step %d of %d · %s",
	DETECT_CALIBRATING_COUNTER = "Calibrating",
	DETECT_CALIBRATING = "Let go of the controller",
	DETECT_CALIBRATE_BAR = "Calibrating · %.1f s",
	DETECT_WAITING = "Waiting for a press…",
	DETECT_TRIGGER = "Pull it past the line.",
	DETECT_STICK = "Push it all the way, then let go.",
	DETECT_OPTIONAL = "Many controllers have no back buttons. Skip if yours doesn't.",
	DETECT_CAPTURED = "%s · next: %s",
	DETECT_BUTTON = "Button %d",
	DETECT_AXIS = "Axis %d",
	DETECT_REJECTED = "Already used for %s. Press a different button.",
	DETECT_SKIP_OPTIONAL = "Skip: no back buttons",
	DETECT_SAVE = "Save",
	DETECT_FINISH_HEADING = "Which button labels should Controller Tweaks show?",
	DETECT_STYLES = { Letters = { "Xbox letters", "A, B, X, Y" }, Shapes = { "PlayStation shapes", "Cross, Circle, Square, Triangle" }, Reverse = { "Nintendo", "B, A, Y, X (B at the bottom)" } },
	DETECT_SKIPPED_TITLE = "Skipped",
	DETECT_NONE_SKIPPED = "Nothing skipped.",
	DETECT_SKIPPED_NOTE = "Skipped controls keep the game's default. Everything else is set: %d controls.",
	DETECT_DONE_HEADING = "Your controller is set up",
	DETECT_DONE_LINES = "The game now reads every button you pressed. Next, choose which buttons open the bars and targeting.",
	DETECT_DEVICE_LINE = "%s · %s",
	DETECT_BUTTON_LABEL = "Detect controller buttons",
	DETECT_BUTTON_TIP = "Teaches the game every button of this controller, one press at a time.",
	DETECT_RESET = "Reset detection",
	DETECT_RESET_TEXT = "Forget this controller's detected buttons? The game's default mapping comes back.",
	DETECT_RESET_SUB = "Your layout and crossbar actions stay.",
	DETECT_NOTHING_TO_RESET = "detect: nothing to reset for this controller",
	DETECT_LABELS = {
		faceBottom = "Bottom face button (A / Cross)", faceRight = "Right face button (B / Circle)", faceLeft = "Left face button (X / Square)",
		faceTop = "Top face button (Y / Triangle)", dpadUp = "D-pad up", dpadDown = "D-pad down", dpadLeft = "D-pad left", dpadRight = "D-pad right",
		lb = "Left bumper", rb = "Right bumper", lt = "Left trigger", rt = "Right trigger", l3 = "Press the left stick", r3 = "Press the right stick",
		start = "Menu / Start / Options", select = "View / Select / Share or touchpad", home = "Home / Guide (optional)",
		share = "Share / Create / Capture (optional)", p1 = "Back button 1 (optional)", p2 = "Back button 2 (optional)",
		p3 = "Back button 3 (optional)", p4 = "Back button 4 (optional)", lstickX = "Push the left stick right",
		lstickY = "Push the left stick down", rstickX = "Push the right stick right", rstickY = "Push the right stick down",
	},
	DETECT_KEYBOARD = "Setting up buttons needs a keyboard or mouse: Space skips a button, Enter saves, Esc cancels. Continue?",
	RESUME_DETECT = "Combat stopped controller setup. Start it again?",
	NO_PAD_NOTICE = "No controller found. Connect one, then open Controller Tweaks again.",
	KEY_ENTER = "Enter",
	KEY_SPACE = "Space",
	KEY_BACKSPACE = "Backspace",
	KEY_ESCAPE = "Esc",
	NOTICE_TITLE = "Forever Controller Tweaks",
	RESTORE_DEFAULT = "Restore default action",
	UNDO_RESTORE = "Undo: restore %s",
	KEYBOARD = "On-screen keyboard",
	KEYBOARD_OPEN = "Keyboard settings",
	KEYBOARD_TIP = "Type in chat and text boxes with the controller: on or off, when it opens, its size and its buttons.",
	UNDO_TIP = "Puts back what you just cleared.",
	TOUCH_RESET = "Reset touch layout",
	TOUCH_RESET_TIP = "Puts both bars' size, place, shape and other settings back to the defaults. Their actions stay.",
	TOUCH_RESET_TEXT = "Reset both touch bars' settings to the defaults?",
	INFO = "Info",
	CATEGORY = "Category",
	PAGE = "Page",
	PAGE_OF = "Page %d of %d",
	PAGE_TIP = "Crossbar pages. The face buttons' first-page actions are the same on every page.",
	PAGE_PREVIOUS = "Previous page",
	PAGE_NEXT = "Next page",
	OVERRIDE_NOTE = "%s bar replaces the %s bar on this page while it is up",
	RESUME = "Resume",
	RESUME_GUIDE = "Combat closed the Controller Tweaks setup guide. Resume where you left it?",
	RESUME_CUSTOM = "Combat closed \"Set it up yourself\". Resume where you left it?",
	SETTINGS_TITLE = "Forever Controller Tweaks",
	SETTINGS_OPEN_LABEL = "Bindings",
	SETTINGS_OPEN = "Open Settings",
	SETTINGS_OPEN_TIP = "Opens Bindings: buttons, roles and presets. On the controller: %s.",
	SETTINGS_SETUP_LABEL = "Setup guide",
	SETTINGS_SETUP = "Run setup guide",
	SETTINGS_SETUP_TIP = "Walks you through choosing a layout for this controller again.",
	SETTINGS_FAILED = "Options page not added: %s",
	NOTICE_TEXT = "Forever Controller Tweaks works with the Gamepad UI. Turn on Options > Gamepad (Beta) > Enable Gamepad UI (Beta).",
	RESET_TEXT = "Reset Controller Tweaks for this controller? Buttons go back to the game’s default roles and face actions.",
	RESET_SUB = "Your crossbar actions stay where they are.",
	LEARN_TEXT = "Press the button you want as %s",
	LEARN_WAIT = "Hold it until Controller Tweaks confirms",
	LEARN_DETECTED = "Detected: raw %s",
	LEARN_STEP = "%s · step %d of %d",
	LEARN_NONE = "Nothing detected; %s keeps its input",
}

local L = UI.L

-- Role words and lines, controller names and glyph-set lines: UI text too, merged into UI.ROLE / UI.FAMILY below.
L.ROLES = {
	top = { word = "TOP", plain = "No button: TOP bar" },
	leftmod = { word = "LEFT", name = "Left bar", plain = "Opens the LEFT bar", hint = "Hold: LEFT bar", card = "LEFT BAR" },
	rightmod = { word = "RIGHT", name = "Right bar", plain = "Opens the RIGHT bar", hint = "Hold: RIGHT bar", card = "RIGHT BAR" },
	bottom = { word = "BOTTOM", plain = "Both together: BOTTOM bar" },
	friendly = { word = "FRIENDLY", name = "Friendly targeting", plain = "Hold: FRIENDLY targeting", hint = "Hold: FRIENDLY targeting", card = "FRIENDLY" },
	hostile = { word = "HOSTILE", name = "Hostile targeting", plain = "Hold: HOSTILE targeting", hint = "Hold: HOSTILE targeting", card = "HOSTILE" },
	shortcuts = { word = "SHORTCUTS", plain = "Both together: SHORTCUTS" },
	none = { name = "None", hint = "Keeps its own button", word = "" },
}

L.FAMILY = {
	playstation = {
		short = "DualSense", set = "PlayStation buttons (Shapes glyph set)",
		names = { L1 = "L1", R1 = "R1", L2 = "L2", R2 = "R2", L3 = "L3", R3 = "R3", SEL = "Touchpad", START = "Options", FB = "Cross", FR = "Circle", FL = "Square", FT = "Triangle", SOCIAL = "Create", SYSTEM = "PS button" },
	},
	xbox = {
		short = "Xbox controller", set = "Xbox buttons (Letters glyph set)",
		names = { L1 = "LB", R1 = "RB", L2 = "LT", R2 = "RT", L3 = "LS", R3 = "RS", SEL = "View", START = "Menu", FB = "A", FR = "B", FL = "X", FT = "Y", SOCIAL = "Share", SYSTEM = "Xbox button" },
	},
	switch = {
		short = "Switch Pro Controller", set = "Nintendo buttons (Reverse glyph set: B is the bottom button)",
		names = { L1 = "L", R1 = "R", L2 = "ZL", R2 = "ZR", L3 = "LS", R3 = "RS", SEL = "Minus", START = "Plus", FB = "B", FR = "A", FL = "Y", FT = "X", SOCIAL = "Capture", SYSTEM = "Home" },
	},
}

L.BUTTON_NAMES = { DU = "D-pad Up", DL = "D-pad Left", DR = "D-pad Right", DD = "D-pad Down", P1 = "Back paddle 1", P2 = "Back paddle 2", P3 = "Back paddle 3", P4 = "Back paddle 4" }
L.GENERIC_SHORT = "Controller"

-- Colour + word per role; the colours are the client's GlobalColor entries, with fixed fallbacks.
UI.ROLE = {
	top = { color = "GRAY_FONT_COLOR", rgb = { 128, 128, 128 } },
	leftmod = { color = "BLUE_FONT_COLOR", rgb = { 0, 191, 243 } },
	rightmod = { color = "FACTION_ORANGE_COLOR", rgb = { 191, 69, 0 } },
	bottom = { color = "LIGHTERBLUE_FONT_COLOR", rgb = { 196, 221, 252 } },
	friendly = { color = "DIM_GREEN_FONT_COLOR", rgb = { 64, 192, 64 } },
	hostile = { color = "RED_FONT_COLOR", rgb = { 255, 32, 32 } },
	shortcuts = { color = "YELLOW_FONT_COLOR", rgb = { 255, 255, 0 } },
	none = {},
}
for role, text in pairs(L.ROLES) do Mixin(UI.ROLE[role], text) end
UI.KEY_ROLES = { "top", "leftmod", "rightmod", "bottom", "friendly", "hostile", "shortcuts" }
UI.PICK_ROLES = { "leftmod", "rightmod", "friendly", "hostile", "none" }

function UI.RoleRGB(role)
	local info = UI.ROLE[role]
	local color = info and info.color and _G[info.color]
	if color and color.GetRGB then return color:GetRGB() end

	local rgb = info and info.rgb
	if not rgb then return 0.5, 0.5, 0.5 end
	return rgb[1] / 255, rgb[2] / 255, rgb[3] / 255
end

-- The addon's button codes -> native keys. While one of our windows is open Remap applies native, so these are physical.
UI.KEY = {
	L1 = "PADLSHOULDER", R1 = "PADRSHOULDER", L2 = "PADLTRIGGER", R2 = "PADRTRIGGER",
	P1 = "PADPADDLE1", P2 = "PADPADDLE2", P3 = "PADPADDLE3", P4 = "PADPADDLE4",
	DU = "PADDUP", DD = "PADDDOWN", DL = "PADDLEFT", DR = "PADDRIGHT",
	FB = "PAD1", FR = "PAD2", FL = "PAD3", FT = "PAD4",
	L3 = "PADLSTICK", R3 = "PADRSTICK", SEL = "PADBACK", START = "PADFORWARD", SOCIAL = "PADSOCIAL", SYSTEM = "PADSYSTEM",
}
UI.CODE = {}
for code, key in pairs(UI.KEY) do UI.CODE[key] = code end
UI.FACE_CODE = { bottom = "FB", right = "FR", left = "FL", top = "FT" }
UI.CODE_POS = { FB = "bottom", FR = "right", FL = "left", FT = "top" }

UI.FAMILY = {
	playstation = {
		art = "playstation", pads = { P1 = true, P2 = true },
	},
	xbox = {
		art = "xbox", pads = { P1 = true, P2 = true, P3 = true, P4 = true },
	},
	switch = {
		art = "switch", pads = {},
	},
}
for family, text in pairs(L.FAMILY) do Mixin(UI.FAMILY[family], text) end
UI.FAMILY.generic = UI.FAMILY.xbox

local OTHER_NAMES = L.BUTTON_NAMES

-- Where each button sits on the drawing (viewBox 400x300) and the d-pad centre, per family. Face buttons sit 23 from
-- their well's centre, so the larger face glyphs fill the 34-radius well like a real pad's cluster.
UI.DIA = {
	playstation = { dpad = { 126, 134 }, pos = { L2 = { 125, 38 }, R2 = { 275, 38 }, L1 = { 118, 66 }, R1 = { 282, 66 }, DU = { 126, 121 }, DD = { 126, 147 }, DL = { 113, 134 }, DR = { 139, 134 }, FT = { 274, 111 }, FB = { 274, 157 }, FL = { 251, 134 }, FR = { 297, 134 }, L3 = { 160, 194 }, R3 = { 240, 194 }, SEL = { 200, 100 }, START = { 258, 84 }, SOCIAL = { 146, 84 }, SYSTEM = { 200, 152 }, P1 = { 292, 286 }, P2 = { 108, 286 } } },
	xbox = { dpad = { 166, 180 }, pos = { L2 = { 125, 40 }, R2 = { 275, 40 }, L1 = { 118, 68 }, R1 = { 282, 68 }, DU = { 166, 167 }, DD = { 166, 193 }, DL = { 153, 180 }, DR = { 179, 180 }, FT = { 276, 107 }, FB = { 276, 153 }, FL = { 253, 130 }, FR = { 299, 130 }, L3 = { 128, 130 }, R3 = { 236, 180 }, SEL = { 178, 126 }, START = { 222, 126 }, SOCIAL = { 200, 144 }, SYSTEM = { 200, 100 }, P1 = { 296, 278 }, P2 = { 104, 278 }, P3 = { 318, 256 }, P4 = { 82, 256 } } },
	switch = { dpad = { 170, 180 }, pos = { L2 = { 127, 42 }, R2 = { 273, 42 }, L1 = { 120, 70 }, R1 = { 280, 70 }, DU = { 170, 167 }, DD = { 170, 193 }, DL = { 157, 180 }, DR = { 183, 180 }, FT = { 270, 105 }, FB = { 270, 151 }, FL = { 247, 128 }, FR = { 293, 128 }, L3 = { 132, 128 }, R3 = { 230, 180 }, SEL = { 176, 104 }, START = { 224, 104 }, SOCIAL = { 184, 132 }, SYSTEM = { 216, 132 } } },
}
-- The addon's generic pad (controller setup's drawing), for pads outside the known vendors.
UI.DIA.generic = { dpad = { 124, 142 }, stick = 24, pos = { L2 = { 130, 46 }, R2 = { 270, 46 }, L1 = { 129, 68 }, R1 = { 271, 68 }, DU = { 124, 128 }, DD = { 124, 156 }, DL = { 110, 142 }, DR = { 138, 142 }, FT = { 276, 119 }, FB = { 276, 165 }, FL = { 253, 142 }, FR = { 299, 142 }, L3 = { 162, 198 }, R3 = { 238, 198 }, SEL = { 177, 110 }, START = { 223, 110 }, SOCIAL = { 200, 152 }, SYSTEM = { 200, 130 }, P1 = { 303, 267 }, P2 = { 97, 267 }, P3 = { 328, 244 }, P4 = { 72, 244 } } }

-- The detected device, its family key (generic falls back to the Xbox names and drawing) and the family data.
function UI.Device()
	local device = ns.Device.Current()
	local family = device and UI.FAMILY[device.family] and device.family or "xbox"
	if family == "generic" then family = "xbox" end
	return device, family, UI.FAMILY[family]
end

-- Drawing for the current pad: the family's own art for known vendors, the addon's generic pad otherwise (unknown
-- pads, also after controller setup; their glyphs follow the chosen label style).
function UI.Art()
	local device, family, info = UI.Device()
	local vendor = device and device.key and device.key:sub(1, 4)
	if not (vendor and ns.Layout.FAMILIES[vendor]) then return "generic", UI.DIA.generic end
	return info.art, UI.DIA[family]
end

-- The label style the player chose in controller setup, if any.
function UI.LabelStyle()
	local device = ns.Device.Current()
	return device and device.detect and device.detect.labelStyle
end

function UI.Name(code)
	local _, _, info = UI.Device()
	return info.names[code] or OTHER_NAMES[code] or code
end

-- Paddles the family has and this device has a raw source for, left (P2, P4) and right (P1, P3) apart.
function UI.Paddles()
	local device, _, info = UI.Device()
	local left, right = {}, {}
	if not (device and device.hasPaddles) then return left, right end

	for _, phys in ipairs({ "P2", "P4" }) do if info.pads[phys] and device.raw[phys] then left[#left + 1] = phys end end
	for _, phys in ipairs({ "P1", "P3" }) do if info.pads[phys] and device.raw[phys] then right[#right + 1] = phys end end
	return left, right
end

-- Physical buttons that open what a key-panel row stands for, under roles.
function UI.Combo(role, roles)
	local function holder(wanted)
		for _, phys in ipairs(ns.Layout.PHYSICAL) do
			if roles[phys] == wanted then return phys end
		end
	end
	if role == "top" then return {} end
	if role == "bottom" then return { holder("leftmod"), holder("rightmod") } end
	if role == "shortcuts" then return { holder("friendly"), holder("hostile") } end
	return { holder(role) }
end

-- Every way to open the addon, for onboarding's Done screen and /fct help.
-- The pad shortcut: { key = the button to press, hold = physical buttons to hold first }. options.toggleHold is
-- The addon's own option: a saved toggleKey still on the old default (Create alone) moves to holding L2 + R2; a
-- custom toggleKey keeps working alone (false).
local TOGGLE_DEFAULT_KEY, TOGGLE_DEFAULT_HOLD = "PADSOCIAL", { "L2", "R2" }
local TOGGLE_PRESSES = { PADSOCIAL = true, PADBACK = true }

-- Read on every pad press: built once per toggleKey / toggleHold value.
local toggleCache

function UI.Toggle()
	local options = ns.db and ns.db.options or {}
	local cache = toggleCache
	if cache and cache.forKey == options.toggleKey and cache.forHold == options.toggleHold and options.toggleHold ~= nil then return cache.toggle end
	local key = options.toggleKey or TOGGLE_DEFAULT_KEY
	if options.toggleHold == nil and ns.db then options.toggleHold = key == TOGGLE_DEFAULT_KEY and ns.Layout.Copy(TOGGLE_DEFAULT_HOLD) or false end
	local hold = options.toggleHold or {}
	-- The chord takes Create or View/Back as its press (some Xbox pads have no Share button); a key alone is just that key.
	local toggle = { key = key, hold = hold, keys = key == TOGGLE_DEFAULT_KEY and hold[1] and TOGGLE_PRESSES or { [key] = true } }
	toggleCache = { forKey = options.toggleKey, forHold = options.toggleHold, toggle = toggle }
	return toggle
end

-- One button as text: its glyph from the active glyph set (unless plain) and the family's name for it.
local function buttonText(key, name, size, plain)
	local atlas = not plain and UI.GlyphAtlas(key, "Normal")
	return atlas and (CreateAtlasMarkup(atlas, size or 18, size or 18) .. " " .. name) or name
end

-- A face or shoulder code as its glyph and name, e.g. "<Square> Square".
function UI.ButtonText(code, size) return buttonText(UI.KEY[code] or code, UI.Name(code), size) end

-- The shortcut as text, "hold L2 + R2, then press Create" with real glyphs; a plain key is just that button.
function UI.ToggleKeyText(size, plain)
	local toggle = UI.Toggle()
	local _, family = UI.Device()
	-- The chord's press as the active pad shows it: Create on PlayStation, View (Xbox) or Minus (Switch) elsewhere.
	local key = toggle.keys.PADBACK and family ~= "playstation" and "PADBACK" or toggle.key
	local press = buttonText(key, UI.CODE[key] and UI.Name(UI.CODE[key]) or key, size, plain)
	if #toggle.hold == 0 then return press end

	local holds = {}
	for i, phys in ipairs(toggle.hold) do holds[i] = buttonText(UI.KEY[phys], UI.Name(phys), size, plain) end
	return string.format(L.TOGGLE_HOLD, table.concat(holds, " + "), press)
end

function UI.OpenWays() return string.format(L.OPEN_WAYS, UI.ToggleKeyText()) end

-- The side tabs every settings window shares; Touch, Keyboard and Rings add theirs after Bindings.
UI.TABS = {
	{ "Interface\\Icons\\INV_Misc_Book_09", L.TAB_BINDINGS, function() UI.Bindings.Open() end },
}

function UI.PresetLabel(name)
	if name == "native" then return L.PRESET_NATIVE end
	if name == "split" then return L.PRESET_SPLIT end
	return L.PRESET_CUSTOM
end

local function at(region, parent, x, y, point) region:SetPoint(point or "TOPLEFT", parent, "TOPLEFT", x, -y) end
UI.At = at

function UI.Text(parent, font, x, y, text, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	if x then at(fs, parent, x, y) end
	if width then
		fs:SetWidth(width)
		fs:SetJustifyH("LEFT")
	end
	fs:SetText(text or "")
	return fs
end

-- Centred text across [x, x + width].
function UI.CenterText(parent, font, x, y, width, text)
	local fs = UI.Text(parent, font, x, y, text)
	fs:SetWidth(width)
	fs:SetJustifyH("CENTER")
	return fs
end

-- An inset panel; its own dark fill is kept translucent so the window's body texture shows through.
local INSET_FILL_ALPHA = 0.55

function UI.InsetFill(inset)
	if inset.Bg then inset.Bg:SetAlpha(INSET_FILL_ALPHA) end
	return inset
end

function UI.Inset(parent, x, y, w, h)
	local inset = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
	inset:SetSize(w, h)
	at(inset, parent, x, y)
	return UI.InsetFill(inset)
end

-- The small 4-unit colour bar of a role (a plain colour texture over a 1-unit black outline).
function UI.Marker(parent, width)
	local outline = parent:CreateTexture(nil, "ARTWORK")
	outline:SetColorTexture(0, 0, 0, 0.85)
	outline:SetSize(width + 2, 6)
	local bar = parent:CreateTexture(nil, "ARTWORK", nil, 1)
	bar:SetPoint("CENTER", outline)
	bar:SetSize(width, 4)
	function outline:SetRole(role)
		local shown = role and UI.ROLE[role] and UI.ROLE[role].color
		self:SetShown(shown)
		bar:SetShown(shown)
		if shown then bar:SetColorTexture(UI.RoleRGB(role)) end
	end
	return outline
end

-- A button glyph drawn with the active native glyph set's atlas (read through InputIconTextureSetUtility, a pure
-- lookup; the InputIconTexture template itself registers with InputDeviceIconSetManager, so it is not used). Paddles
-- have no atlas: "P1" in GameFontNormal over gamepad-footer-slot-frameneutral. Windows repaint
-- glyphs on every refresh, which covers a device or glyph-set change.
local GlyphMixin = {}
-- The newer 76x75 prompt atlases carry padding; InputIconTexture widens them by 5 units per side the same way.
local LARGE_PROMPT_W, LARGE_PROMPT_H = 76, 75

-- InputIconTextureState's values; the table is local to InputIconTexture.lua, so there is no global to read.
local ICON_STATE = { Normal = 1, Active = 4, Disabled = 5 }
local glyphs = setmetatable({}, { __mode = "k" })
UI.glyphs = glyphs

-- A detected pad's face glyphs follow the label style the player chose (the game's set is Generic for it).
local STYLE_FACE_INDEX = { PAD1 = 1, PAD2 = 2, PAD3 = 3, PAD4 = 4 }

local function glyphAtlas(key, state)
	local style, faces = UI.LabelStyle and UI.LabelStyle(), UI.Detect and UI.Detect.STYLE_FACES
	if style and faces and faces[style] and STYLE_FACE_INDEX[key] then return faces[style][STYLE_FACE_INDEX[key]] end
	local util = InputIconTextureSetUtility
	if not (util and key) then return end
	local ok, textures = pcall(util.GetActiveInputIconButtonTextures, key)
	if not (ok and textures) then return end
	return textures[ICON_STATE[state]] or textures[ICON_STATE.Normal]
end

UI.GlyphAtlas = glyphAtlas

function GlyphMixin:Paint()
	local state = self.disabled and "Disabled" or self.lit and "Active" or "Normal"
	local atlas = not self.paddle and glyphAtlas(self.key, state)
	self.atlas = atlas
	local icon = self.icon
	icon:ClearAllPoints()
	if not atlas then return icon:Hide() end

	icon:SetAtlas(atlas)
	local info = C_Texture.GetAtlasInfo(atlas)
	local pad = info and info.width == LARGE_PROMPT_W and info.height == LARGE_PROMPT_H and 5 or 0
	icon:SetPoint("TOPLEFT", -pad, pad)
	icon:SetPoint("BOTTOMRIGHT", pad, -pad)
	icon:Show()
end

function GlyphMixin:SetCode(code)
	self.code, self.key = code, code and (UI.KEY[code] or code)
	self.paddle = code and code:match("^P%d$")
	self.tab:SetShown(self.paddle)
	if self.paddle then self.tab.text:SetText(code) end
	self:Paint()
end

function GlyphMixin:SetLit(lit)
	self.lit = lit
	self.tab.border:SetAtlas(lit and "gamepad-footer-slot-framefocused" or "gamepad-footer-slot-frameneutral")
	self:Paint()
end

function GlyphMixin:SetDisabled(disabled)
	self.disabled = disabled
	self:Paint()
end

function UI.Glyph(parent, size, code)
	local glyph = Mixin(CreateFrame("Frame", nil, parent), GlyphMixin)
	glyphs[glyph] = true
	glyph:SetSize(size, size)
	glyph.icon = glyph:CreateTexture(nil, "ARTWORK")
	local tab = CreateFrame("Frame", nil, glyph)
	tab:SetAllPoints()
	tab.border = tab:CreateTexture(nil, "ARTWORK")
	tab.border:SetAllPoints()
	tab.border:SetAtlas("gamepad-footer-slot-frameneutral")
	tab.text = tab:CreateFontString(nil, "OVERLAY", size < 18 and "GameFontNormalSmall" or "GameFontNormal")
	tab.text:SetPoint("CENTER")
	glyph.tab = tab
	glyph:SetCode(code)
	return glyph
end

-- Glyphs joined by gamepad-symbols-plus, laid out from x on a row; returns the width used.
function UI.GlyphRow(parent, pool, codes, size, x, centerY)
	local used, plusIndex = x, 0
	pool.glyphs, pool.plus = pool.glyphs or {}, pool.plus or {}
	for _, glyph in ipairs(pool.glyphs) do glyph:Hide() end
	for _, plus in ipairs(pool.plus) do plus:Hide() end

	for i, code in ipairs(codes) do
		if i > 1 then
			plusIndex = plusIndex + 1
			local plus = pool.plus[plusIndex] or parent:CreateTexture(nil, "ARTWORK")
			pool.plus[plusIndex] = plus
			plus:SetAtlas("gamepad-symbols-plus")
			plus:SetSize(8, 8)
			plus:ClearAllPoints()
			plus:SetPoint("LEFT", parent, "TOPLEFT", used + 1, -centerY)
			plus:Show()
			used = used + 13
		end
		local glyph = pool.glyphs[i] or UI.Glyph(parent, size)
		pool.glyphs[i] = glyph
		glyph:SetCode(code)
		glyph:ClearAllPoints()
		glyph:SetPoint("LEFT", parent, "TOPLEFT", used, -centerY)
		glyph:Show()
		used = used + size + 3
	end
	return used - x
end

-- Leader line from a row to its control on the drawing: Line regions on the drawing, above its body and below the
-- d-pad arms and glyphs, so each line ends under its own control. line.tga is a strip whose alpha falls off across
-- the width; with pixel snapping off it antialiases. points are window coordinates.
local ConnectorMixin = {}

function ConnectorMixin:Set(points, r, g, b, alpha, width)
	local window, lines = self.window, self.lines
	for i = 1, #points - 1 do
		local line = lines[i]
		if not line then
			line = self.drawing:CreateLine(nil, "ARTWORK", nil, 2)
			line:SetTexture(ART .. "line.tga")
			if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(false) end
			if line.SetTexelSnappingBias then line:SetTexelSnappingBias(0) end
			lines[i] = line
		end
		local from, to = points[i], points[i + 1]
		line:SetStartPoint("TOPLEFT", window, from[1], -from[2])
		line:SetEndPoint("TOPLEFT", window, to[1], -to[2])
		line:SetThickness(width)
		line:SetVertexColor(r, g, b, alpha)
		line:Show()
	end
	for i = #points, #lines do lines[i]:Hide() end
end

function ConnectorMixin:Hide() for _, line in ipairs(self.lines) do line:Hide() end end

function UI.Connector(window, drawing) return Mixin({ window = window, drawing = drawing, lines = {} }, ConnectorMixin) end

-- The addon's own controller drawing with the native glyphs on it. card = the flat onboarding version.
local DrawingMixin = {}

-- Frame sizes: the glyph's image size minus the 5-unit atlas padding InputIconTexture adds on each side; face
-- buttons are 22, in a real pad's proportion to the d-pad.
local GLYPH_SIZE = { L1 = 24, R1 = 24, L2 = 24, R2 = 24, FT = 22, FL = 22, FR = 22, FB = 22, L3 = 20, R3 = 20, SEL = 18, START = 12, SOCIAL = 14, SYSTEM = 16, P1 = 18, P2 = 18, P3 = 18, P4 = 18 }
local BIG_CODES = { "L2", "R2", "L1", "R1", "FT", "FL", "FR", "FB", "L3", "R3", "SEL", "START" }
-- The drawing's controls, as the art draws them (the logo's style): a trigger 66 x 32 above its position, a shoulder
-- 62 x 12 around it (both lit by a shape fill), round face buttons of radius 11, stick pads of radius 22 (the
-- family's dia.stick when larger) with an inner ring at 0.6 of it. Their boxes are the leader lines' targets and the
-- curves' obstacles; a stick's is its inner ring, so a line may cross a pad's rim but never its centre.
local FILL_SHAPE = { L2 = "trigger", R2 = "trigger", L1 = "shoulder", R1 = "shoulder" }
local FILL_BOX = { trigger = { -33, -18, 66, 32 }, shoulder = { -31, -6, 62, 12 } }
local FACE_R, STICK_R, STICK_RING = 11, 22, 0.6
local ROUND = { FT = "face", FL = "face", FR = "face", FB = "face", L3 = "stick", R3 = "stick" }
local GOLD = { 1, 210 / 255, 0, 1 }
local MOD_CODES = { L1 = true, R1 = true, L2 = true, R2 = true, P1 = true, P2 = true, P3 = true, P4 = true }
UI.MOD_CODES = MOD_CODES

function DrawingMixin:Place(ox, oy, scale)
	local art, dia = UI.Art()
	self.ox, self.oy, self.scale, self.dia = ox, oy, scale, dia
	self:ClearAllPoints()
	at(self, self:GetParent(), ox, oy)
	self:SetSize(400 * scale, 300 * scale)
	self.body:SetTexture(ART .. art .. (self.card and "-card.tga" or "-controller.tga"))

	if not self.card then
		local dx, dy = unpack(self.dia.dpad)
		local boxes = { DU = { dx - 8, dy - 22, "v" }, DD = { dx - 8, dy + 6, "v" }, DL = { dx - 22, dy - 8, "h" }, DR = { dx + 6, dy - 8, "h" }, DC = { dx - 8, dy - 8 } }
		self.boxes = {}
		for code, box in pairs(boxes) do
			local x, y = ox + box[1] * scale, oy + box[2] * scale
			self.boxes[code] = { x, y, x + 16 * scale, y + 16 * scale }
			local arm = self.arms[code]
			if arm then
				arm.dir = box[3]
				arm:ClearAllPoints()
				arm:SetPoint("TOPLEFT", self, "TOPLEFT", box[1] * scale, -box[2] * scale)
				arm:SetSize(16 * scale, 16 * scale)
			end
		end
	end
	self:LayoutGlyphs()
end

-- A route from a row (its glyph's edge sx at height y, window coordinates) to the control: horizontal from the row,
-- then 45 degrees, then a straight lead into one side of the control (never the side facing its own cluster). A row
-- level with the control goes straight in. Cost: passing under an active control rules a route out, under a dimmed
-- one or close by is penalised, then the outward side and the shortest route win.
local PORTS = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }
local OUTWARD = { DU = { 0, -1 }, DD = { 0, 1 }, DL = { -1, 0 }, DR = { 1, 0 }, FT = { 0, -1 }, FB = { 0, 1 }, FL = { -1, 0 }, FR = { 1, 0 } }
local LEADS, STUB, CLEAR, NEAR = { 10, 22, 36 }, 14, 3, 9

-- Liang-Barsky: does the segment cross the box grown by margin on every side? (No tables: it runs for every segment
-- and box on each focus move.)
local function clip(p, q, t0, t1)
	if p == 0 then return q >= 0 and t0, t1 end
	local t = q / p
	if p < 0 then t0 = math.max(t0, t) else t1 = math.min(t1, t) end
	return t0 <= t1 and t0, t1
end

local function crosses(box, x1, y1, x2, y2, margin)
	local dx, dy, t0, t1 = x2 - x1, y2 - y1, 0, 1
	t0, t1 = clip(-dx, x1 - box[1] + margin, t0, t1)
	if not t0 then return false end
	t0, t1 = clip(dx, box[3] + margin - x1, t0, t1)
	if not t0 then return false end
	t0, t1 = clip(-dy, y1 - box[2] + margin, t0, t1)
	if not t0 then return false end
	t0 = clip(dy, box[4] + margin - y1, t0, t1)
	return not not t0
end

function DrawingMixin:Dimmed(code)
	local region = self.glyphs[code] or self.arms and (self.arms[code] or self.arms.DU)
	return region and (region:GetAlpha() or 1) < 1
end

-- tail: the last segments, which reach the control's own edge, are not checked against it.
function DrawingMixin:RouteCost(code, points, tail)
	local cost = #points * 25
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		cost = cost + math.abs(b[1] - a[1]) + math.abs(b[2] - a[2])
		for other, box in pairs(self.boxes) do
			if other ~= code or i < #points - (tail or 1) then
				if crosses(box, a[1], a[2], b[1], b[2], CLEAR) then cost = cost + (self:Dimmed(other) and 400 or 10000)
				elseif crosses(box, a[1], a[2], b[1], b[2], NEAR) then cost = cost + 120 end
			end
		end
	end
	return cost
end

function DrawingMixin:Route(code, sx, y)
	local target = self.boxes and self.boxes[code]
	if not target then return end

	local cx, cy = (target[1] + target[3]) / 2, (target[2] + target[4]) / 2
	local side, out = cx > sx and 1 or -1, OUTWARD[code]
	local best, bestCost
	for _, port in ipairs(PORTS) do
		local px, py = port[1], port[2]
		if not (out and px == -out[1] and py == -out[2]) then
			local tx = px > 0 and target[3] or px < 0 and target[1] or cx
			local ty = py > 0 and target[4] or py < 0 and target[2] or cy
			local level = py == 0 and y >= target[2] + CLEAR and y <= target[4] - CLEAR
			local leads = { unpack(LEADS) }
			if py ~= 0 and (y - ty) * py > LEADS[1] then leads[#leads + 1] = (y - ty) * py end
			for _, lead in ipairs(leads) do
				local qx, qy, endY = tx + px * lead, ty + py * lead, ty
				if level or math.abs(qy - y) < 2 then
					qy = y
					if py == 0 then endY = y end
				end
				local ex = qx - side * math.abs(qy - y)
				if (ex - (sx + side * STUB)) * side < 0 then ex = sx + side * STUB end
				local points = { { sx, y } }
				for _, point in ipairs({ { ex, y }, { qx, qy }, { tx, endY } }) do
					local last = points[#points]
					if math.abs(point[1] - last[1]) + math.abs(point[2] - last[2]) > 0.5 then points[#points + 1] = point end
				end
				local cost = self:RouteCost(code, points) + ((out and not (px == out[1] and py == out[2])) and 60 or 0)
				if not bestCost or cost < bestCost then best, bestCost = points, cost end
			end
		end
	end
	return best
end

-- The focused row's curve: a cubic Bezier from (sx, y) that leaves level and meets one side of the control straight
-- on, sampled into short segments for the shared line helper. Sides and costs as in Route.
local CURVE_STEPS = 24
-- { how far the curve runs level from the row (share of the horizontal gap), how far it reaches out of the control's
-- side (share of the distance) }: tried in turn, the cheapest wins.
local CURVE_SHAPES = { { 0.5, 0.33 }, { 0.3, 0.2 }, { 0.7, 0.2 }, { 0.3, 0.5 }, { 0.7, 0.5 }, { 0.9, 0.12 } }

local function bezier(p0, p1, p2, p3)
	local points = {}
	for i = 0, CURVE_STEPS do
		local t = i / CURVE_STEPS
		local u = 1 - t
		local a, b, c, d = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
		points[#points + 1] = { a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1], a * p0[2] + b * p1[2] + c * p2[2] + d * p3[2] }
	end
	return points
end

function DrawingMixin:Curve(code, sx, y)
	local target = self.boxes and self.boxes[code]
	if not target then return end

	local cx, cy = (target[1] + target[3]) / 2, (target[2] + target[4]) / 2
	local side, out = cx > sx and 1 or -1, OUTWARD[code]
	local best, bestCost
	for _, port in ipairs(PORTS) do
		local px, py = port[1], port[2]
		if not (out and px == -out[1] and py == -out[2]) then
			local tx = px > 0 and target[3] or px < 0 and target[1] or cx
			local ty = py > 0 and target[4] or py < 0 and target[2] or cy
			local span = math.abs(tx - sx) + math.abs(ty - y)
			for _, shape in ipairs(CURVE_SHAPES) do
				local reach = math.max(16, math.min(140, span * shape[2]))
				local points = bezier({ sx, y }, { sx + side * math.abs(tx - sx) * shape[1], y }, { tx + px * reach, ty + py * reach }, { tx, ty })
				local cost = self:RouteCost(code, points, 3) + ((out and not (px == out[1] and py == out[2])) and 60 or 0)
				if not bestCost or cost < bestCost then best, bestCost = points, cost end
			end
		end
	end
	return best
end

function DrawingMixin:LayoutGlyphs()
	local left, right = UI.Paddles()
	local codes = {}
	for _, code in ipairs(self.codes or BIG_CODES) do codes[#codes + 1] = code end
	for _, list in ipairs({ left, right }) do
		for _, phys in ipairs(list) do codes[#codes + 1] = phys end
	end

	for code, glyph in pairs(self.glyphs) do
		glyph:Hide()
		if self.boxes then self.boxes[code] = nil end
	end
	local factor = self.card and 18 / 24 or self.scale / 1.15
	for _, code in ipairs(codes) do
		local pos = self.dia.pos[code]
		if pos then
			local size = (self.card and 18 or GLYPH_SIZE[code]) * (self.card and 1 or factor)
			local glyph = self.glyphs[code] or UI.Glyph(self, size)
			self.glyphs[code] = glyph
			glyph:SetSize(size, size)
			glyph:SetCode(code)
			glyph:ClearAllPoints()
			glyph:SetPoint("CENTER", self, "TOPLEFT", pos[1] * self.scale, -pos[2] * self.scale)
			glyph:Show()
			if self.boxes then
				local s = self.scale
				local x, y, half = self.ox + pos[1] * s, self.oy + pos[2] * s, size / 2
				local round, shape = ROUND[code], FILL_SHAPE[code]
				if round then half = math.max(half, (round == "face" and FACE_R or (self.dia.stick or STICK_R) * STICK_RING) * s) end
				if shape then
					local box = FILL_BOX[shape]
					local left, top = self.ox + (pos[1] + box[1]) * s, self.oy + (pos[2] + box[2]) * s
					self.boxes[code] = { left, top, left + box[3] * s, top + box[4] * s }
				else
					self.boxes[code] = { x - half, y - half, x + half, y + half }
				end
				-- The focused control's fill: a native-gold disc behind the glyph, as strong as the d-pad's gold arm.
				glyph.hot = glyph.hot or glyph:CreateTexture(nil, "BACKGROUND")
				glyph.hot:SetTexture(ART .. "disc.tga")
				glyph.hot:SetVertexColor(1, 210 / 255, 0)
				glyph.hot:SetSize(size * 1.4, size * 1.4)
				glyph.hot:SetPoint("CENTER")
			end
		end
	end
end

-- A trigger or shoulder fill in color ({ r, g, b, a }, nil hides it), laid on the control by its position.
function DrawingMixin:Fill(code, color)
	local kind = FILL_SHAPE[code]
	if not kind then return end
	self.fills = self.fills or {}
	local fill = self.fills[code]
	if not fill then
		fill = self:CreateTexture(nil, "ARTWORK", nil, 1)
		fill:SetTexture(ART .. "ctl-" .. kind .. "-fill.tga")
		fill:SetTexCoord(UI.MaskCoords(kind))
		self.fills[code] = fill
	end
	local pos = self.dia.pos[code]
	fill:SetShown(pos ~= nil and color ~= nil)
	if not (pos and color) then return end

	local box, s = FILL_BOX[kind], self.scale
	fill:ClearAllPoints()
	fill:SetPoint("TOPLEFT", self, "TOPLEFT", (pos[1] + box[1] - 2) * s, -(pos[2] + box[2] - 2) * s)
	fill:SetSize((box[3] + 4) * s, (box[4] + 4) * s)
	fill:SetVertexColor(unpack(color))
end

-- Role colours on the triggers and shoulders (the layout cards). colorOf(code) -> { r, g, b, a } or nil.
function DrawingMixin:Fills(colorOf)
	self.roleFills = true
	for code in pairs(FILL_SHAPE) do self:Fill(code, colorOf(code)) end
end

-- active(code) -> full strength (else 30 %); glow[code] -> the focused control, filled gold: a trigger or shoulder in
-- its own shape (unless the layout cards fill them with role colours), a button by a gold disc behind its glyph, and
-- hot, the d-pad arm, gold over the plus (the other arms are the art's plus itself).
function DrawingMixin:Style(active, glow, hot)
	for code, glyph in pairs(self.glyphs) do
		local lit = glow and glow[code] or false
		glyph:SetAlpha((not active or active(code)) and 1 or 0.3)
		glyph:SetLit(lit)
		local shaped = FILL_SHAPE[code] and not self.roleFills
		if glyph.hot then glyph.hot:SetShown(lit and not shaped) end
		if shaped then self:Fill(code, lit and GOLD or nil) end
	end
	for code, arm in pairs(self.arms or {}) do
		arm:SetTexture(ART .. "dpad-arm-" .. (arm.dir or "v") .. "-hot.tga")
		arm:SetShown(hot == code)
	end
end

-- Control masks (ctl-<kind>-fill / -line.tga): canvas size (pixels) and viewBox (the shape plus 2 units of padding a
-- side), centred with "meet"; the texcoords crop to the viewBox so each mask scales uniformly.
local MASK = { shoulder = { 256, 64, 66, 16 }, pill = { 128, 64, 22, 12 }, dpadv = { 64, 64, 18, 20 }, dpadh = { 64, 64, 20, 18 }, tab = { 128, 64, 26, 14 }, trigger = { 128, 64, 72, 36 } }

function UI.MaskCoords(kind)
	local cw, ch, vw, vh = unpack(MASK[kind])
	local scale = math.min(cw / vw, ch / vh)
	local w, h = vw * scale, vh * scale
	local x, y = (cw - w) / 2, (ch - h) / 2
	return x / cw, (x + w) / cw, y / ch, (y + h) / ch
end

-- Route, Curve and their costs work on any frame with boxes (window coordinates) and glyphs: Touch's screen preview.
UI.DrawingMixin = DrawingMixin

function UI.Drawing(parent, card, codes)
	local drawing = Mixin(CreateFrame("Frame", nil, parent), DrawingMixin)
	drawing.card, drawing.codes, drawing.glyphs = card, codes, {}
	drawing.body = drawing:CreateTexture(nil, "ARTWORK")
	drawing.body:SetAllPoints()
	drawing.body:SetTexCoord(0, 2 / 3, 0, 1)
	if not card then
		drawing.arms = {}
		for _, code in ipairs({ "DU", "DD", "DL", "DR" }) do drawing.arms[code] = drawing:CreateTexture(nil, "ARTWORK", nil, 3) end
	end
	return drawing
end

-- One "which button opens what" row: colour bar, glyph combo, plain words; lit = QuestTitleHighlight + GameFontNormal.
local KeyRowMixin = {}

function KeyRowMixin:Set(role, roles, lit)
	local codes = UI.Combo(role, roles)
	self.marker:SetRole(role)
	local used = 17 + UI.GlyphRow(self, self, codes, 18, 17, 11)
	self.text:ClearAllPoints()
	self.text:SetPoint("LEFT", self, "TOPLEFT", used + 4, -11)
	self.text:SetFontObject(lit and "GameFontNormal" or self.font)
	self.text:SetText(UI.ROLE[role].plain)
	self:SetWidth(used + 4 + self.text:GetStringWidth())
	self.highlight:SetShown(lit)
end

function UI.KeyRow(parent, font)
	local row = Mixin(CreateFrame("Frame", nil, parent), KeyRowMixin)
	row:SetHeight(22)
	row.font = font or "GameFontHighlightSmall"
	row.highlight = row:CreateTexture(nil, "BACKGROUND")
	row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	row.highlight:SetBlendMode("ADD")
	row.highlight:SetPoint("TOPLEFT", -6, 3)
	row.highlight:SetPoint("BOTTOMRIGHT", 6, -3)
	row.marker = UI.Marker(row, 14)
	row.marker:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.text = row:CreateFontString(nil, "OVERLAY", row.font)
	return row
end

-- Live hold test: which modifier buttons are held now (mapped state; native is applied while a window is open).
function UI.HeldButtons()
	local ok, state = pcall(C_GamePad.GetDeviceMappedState, C_GamePad.GetActiveDeviceID and C_GamePad.GetActiveDeviceID())
	local buttons = ok and type(state) == "table" and state.buttons
	local held = {}
	if not buttons then return held end

	for _, phys in ipairs(ns.Layout.PHYSICAL) do
		local index = C_GamePad.ButtonBindingToIndex(UI.KEY[phys])
		if index and buttons[index + 1] then held[#held + 1] = phys end
	end
	return held
end

-- What the held buttons open under roles: the key-panel role to light and the status line.
function UI.HoldResult(held, roles)
	if #held == 0 then return end

	local has, names = {}, {}
	for _, phys in ipairs(held) do
		if roles[phys] then has[roles[phys]] = true end
		names[#names + 1] = UI.Name(phys)
	end
	local who = table.concat(names, " + ")
	local ROLE = UI.ROLE
	if has.leftmod and has.rightmod then return "bottom", string.format(UI.L.HOLD_BAR, who, ROLE.bottom.word) end
	if has.leftmod then return "leftmod", string.format(UI.L.HOLD_BAR, who, ROLE.leftmod.word) end
	if has.rightmod then return "rightmod", string.format(UI.L.HOLD_BAR, who, ROLE.rightmod.word) end
	if has.friendly and has.hostile then return "shortcuts", string.format(UI.L.HOLD_SHORTCUTS, who) end
	if has.friendly then return "friendly", string.format(UI.L.HOLD_TARGETING, who, ROLE.friendly.word) end
	if has.hostile then return "hostile", string.format(UI.L.HOLD_TARGETING, who, ROLE.hostile.word) end
end

-- The native slot mask (ActionBarButton.xml CircleMask / SquareMask): clamped, so no icon corner draws outside the
-- slot's shape. inset: the slot border's width (3 on a 42-44 unit slot).
function UI.SlotMask(frame, texture, circle, inset)
	local mask = frame:CreateMaskTexture()
	mask:SetAtlas(circle and "CircleMask" or "SquareMask", false, nil, nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetPoint("TOPLEFT", inset, -inset)
	mask:SetPoint("BOTTOMRIGHT", -inset, inset)
	texture:AddMaskTexture(mask)
	return mask
end

-- Every overlay (picker list and catcher, action picker, dialog, tooltip, focus cursor) sits in its window's strata,
-- one level above everything the window and its other open overlays draw. The level comes from the real frame tree
-- on every open: child levels are not bounded by a fixed offset. None of our frames is toplevel, so the engine never
-- re-raises a window over its overlays afterwards.
local MAX_LEVEL = 10000

-- Fixed steps above the window's own tree (its overlays left out), two apart so an overlay's children stay under the
-- next one: re-raising on every focus move never climbs.
local OVERLAY_RANK = { catcher = 2, picker = 4, dialog = 6, tooltip = 8, cursor = 10 }

local function treeTop(frame, skip)
	if skip[frame] then return 0 end
	local top = frame:GetFrameLevel()
	for _, child in ipairs({ frame:GetChildren() }) do top = math.max(top, treeTop(child, skip)) end
	return top
end

-- kind: "catcher", "picker", "dialog", "tooltip" or "cursor".
function UI.RaiseAbove(frame, window, kind)
	local overlays = window.overlays or {}
	window.overlays = overlays
	overlays[frame] = true
	frame:SetFrameStrata(window:GetFrameStrata())
	frame:SetFrameLevel(math.min(treeTop(window, overlays) + OVERLAY_RANK[kind], MAX_LEVEL))
end

-- SmartNavigation's pointer art: gamepad-largecursor-white x 0.8, GAMEPAD_SMARTNAV_CURSOR_COLOR, bobbing 4 units.
function UI.Cursor(parent)
	local cursor = CreateFrame("Frame", nil, parent)
	cursor:SetSize(33.6, 56)
	local texture = cursor:CreateTexture(nil, "OVERLAY")
	texture:SetAllPoints()
	texture:SetAtlas("gamepad-largecursor-white")
	local color = GAMEPAD_SMARTNAV_CURSOR_COLOR
	if color and color.GetRGB then texture:SetVertexColor(color:GetRGB()) else texture:SetVertexColor(1, 230 / 255, 0) end

	local bob = texture:CreateAnimationGroup()
	bob:SetLooping("REPEAT")
	local out = bob:CreateAnimation("Translation")
	out:SetOffset(4, 0)
	out:SetDuration(1)
	out:SetSmoothing("IN_OUT")
	out:SetOrder(1)
	local back = bob:CreateAnimation("Translation")
	back:SetOffset(-4, 0)
	back:SetDuration(1)
	back:SetSmoothing("IN_OUT")
	back:SetOrder(2)

	function cursor:Attach(region, x)
		self:ClearAllPoints()
		if not region then return self:Hide() end
		self:SetPoint("LEFT", region, "LEFT", (x or 0) - 22, 0)
		-- Re-raised on every move: above whatever modal the focused region belongs to.
		UI.RaiseAbove(self, parent, "cursor")
		self:Show()
		if not bob:IsPlaying() then bob:Play() end
	end
	cursor:Hide()
	return cursor
end

-- The gamepad focus outline of a native frame: FrameGlowMixin's atlas, offsets, frame level and half scale, coloured
-- and faded the way FrameGlowMixin does from GamepadFocusStateColor / GamepadFocusStateOpacity (read only, on show).
-- Built here because FrameGlowTemplate registers with CVarCallbackRegistry.
local GLOW_COLOR = { [1] = { 1, 0.9, 0.4 }, [2] = { 0, 0, 0 }, [3] = { 0.3, 0.5, 1 } }

function UI.Glow(frame, relative, atlas, x, y, x1, y1)
	local glow = CreateFrame("Frame", nil, frame)
	glow:SetPoint("TOPLEFT", relative, "TOPLEFT", x, y)
	glow:SetPoint("BOTTOMRIGHT", relative, "BOTTOMRIGHT", x1, y1)
	glow:SetFrameLevel(frame:GetFrameLevel() + 5)
	local texture = glow:CreateTexture(nil, "BACKGROUND")
	texture:SetAtlas(atlas)
	texture:SetScale(0.5)
	texture:SetAllPoints()
	glow:SetScript("OnShow", function(self)
		local color = GLOW_COLOR[tonumber(GetCVar("GamepadFocusStateColor") or "")]
		if color then texture:SetVertexColor(unpack(color)) else texture:SetVertexColor(1, 1, 1) end
		self:SetAlpha(tonumber(GetCVar("GamepadFocusStateOpacity") or "") or 1)
	end)
	glow:Hide()
	return glow
end

-- The native footer, drawn by the addon: a separate box under the window's bottom-right corner (the Quest Log's
-- RIGHT alignment, offset 0,0), gamepad-footer-slot-bg + -frameneutral, 24-unit glyphs with GameFontNormal labels,
-- 10 padding, 15 between prompts, sorted the way PromptedBindingFooter sorts keys. Blizzard's footer and
-- prompt templates bind through InputBindingManager and register glyph callbacks, so neither is used. Clicking a
-- prompt does what its button does.
local PROMPT_ORDER = { PAD1 = 1, PAD3 = 2, PAD4 = 3, PADDUP = 4, PADLSHOULDER = 5, PADRSHOULDER = 6, PADLTRIGGER = 7, PADRTRIGGER = 8, PAD2 = 9 }

function UI.Footer(window)
	local footer = CreateFrame("Frame", nil, window)
	footer:SetPoint("TOPRIGHT", window, "BOTTOMRIGHT", 0, 0)
	footer:SetSize(44, 44)
	footer:SetFrameLevel(window:GetFrameLevel() + 10)
	local slot = footer:CreateTexture(nil, "BACKGROUND")
	slot:SetAtlas("gamepad-footer-slot-bg")
	slot:SetAllPoints()
	local border = footer:CreateTexture(nil, "BORDER")
	border:SetAtlas("gamepad-footer-slot-frameneutral")
	border:SetAllPoints()
	footer.prompts = {}

	function footer:Set(list)
		local sorted = {}
		for _, entry in ipairs(list) do sorted[#sorted + 1] = entry end
		table.sort(sorted, function(a, b) return (PROMPT_ORDER[a[1]] or 7) < (PROMPT_ORDER[b[1]] or 7) end)
		for _, prompt in ipairs(self.prompts) do prompt:Hide() end

		local x = 10
		for i, entry in ipairs(sorted) do
			local prompt = self.prompts[i]
			if not prompt then
				prompt = CreateFrame("Button", nil, self)
				prompt:SetHeight(24)
				prompt.glyph = UI.Glyph(prompt, 24)
				prompt.glyph:SetPoint("LEFT")
				prompt.label = prompt:CreateFontString(nil, "OVERLAY", "GameFontNormal")
				prompt.label:SetPoint("LEFT", prompt.glyph, "RIGHT", 4, 0)
				prompt:SetScript("OnClick", function(button) window:Pad(button.key) end)
				self.prompts[i] = prompt
			end
			prompt.key = entry[1]
			prompt.glyph:SetCode(entry[1])
			prompt.label:SetText(entry[2])
			prompt:SetWidth(28 + prompt.label:GetStringWidth())
			prompt:ClearAllPoints()
			prompt:SetPoint("TOPLEFT", self, "TOPLEFT", x, -10)
			prompt:Show()
			x = x + prompt:GetWidth() + 15
		end
		self:SetWidth(x - 15 + 10)
		self:SetShown(#sorted > 0)
	end
	return footer
end

-- A plain button in StaticPopupButtonTemplate's art (UI-DialogBox-Button-*), without its TextSizeManager mixin.
local DIALOG_COORDS = { 0, 1, 0, 0.71875 }
local function dialogButton(parent)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(128, 21)
	for _, spec in ipairs({ { "SetNormalTexture", "Up" }, { "SetPushedTexture", "Down" }, { "SetDisabledTexture", "Disabled" }, { "SetHighlightTexture", "Highlight" } }) do
		button[spec[1]](button, "Interface\\Buttons\\UI-DialogBox-Button-" .. spec[2])
	end
	for _, texture in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(), button:GetDisabledTexture(), button:GetHighlightTexture() }) do
		texture:SetTexCoord(unpack(DIALOG_COORDS))
	end
	button:GetHighlightTexture():SetBlendMode("ADD")
	button:SetNormalFontObject("GameFontNormal")
	button:SetHighlightFontObject("GameFontHighlight")
	button:SetDisabledFontObject("GameFontDisable")
	return button
end

-- A confirm box in StaticPopup's art (UI-DialogBox-Background-Dark under the GameDialogBackgroundTop border, the
-- dialog focus glow), built by the addon: StaticPopup_Show pushes Blizzard's popup binding set and the popup
-- templates bind through GamepadMode. Pad: A presses the focused button, B the second (or spec.back), D-pad
-- left/right moves.
local dialog
local DialogMixin = {}

function DialogMixin:Open(owner, spec)
	self.owner, self.spec, self.index = owner, spec, 1
	self.Text:SetText(spec.text)
	self.SubText:SetText(spec.sub or "")
	self.Button1:SetText(spec.buttons[1])
	self.Button2:SetText(spec.buttons[2] or "")
	self.Button2:SetShown(spec.buttons[2] ~= nil)
	self.Button1:ClearAllPoints()
	if spec.buttons[2] then self.Button1:SetPoint("BOTTOMRIGHT", self, "BOTTOM", -6.5, 16) else self.Button1:SetPoint("BOTTOM", self, "BOTTOM", 0, 16) end
	self:ClearAllPoints()
	self:SetScale(owner:GetScale())
	self:SetPoint("TOP", owner, "TOPLEFT", owner:GetWidth() / 2, -210)
	self:SetHeight(math.max(120, 16 + self.Text:GetStringHeight() + 6 + self.SubText:GetStringHeight() + 16 + 21 + 16))
	UI.RaiseAbove(self, owner, "dialog")
	self:Show()
	owner:SetPrompts({ { "PAD1", UI.L.SELECT }, { "PAD2", UI.L.BACK } })
	self:Point()
end

-- The pad-focused button keeps its highlight lit, like a hovered one, beside the cursor.
function DialogMixin:Point()
	for i = 1, 2 do
		local button = self["Button" .. i]
		if i == self.index then button:LockHighlight() else button:UnlockHighlight() end
	end
	self.owner.cursor:Attach(self["Button" .. self.index], 0)
end

function DialogMixin:SetSub(text) self.SubText:SetText(text or "") end

function DialogMixin:Close()
	if not self:IsShown() then return end
	local owner = self.owner
	self:Hide()
	if owner and owner:IsShown() then owner:Refresh() end
end

function DialogMixin:Press(index)
	local spec = self.spec
	self:Close()
	local fn = spec and spec["on" .. index]
	if fn then fn() end
end

function DialogMixin:OnPad(key)
	local two = self.Button2:IsShown()
	if key == "PADDLEFT" or key == "PADDRIGHT" then
		self.index = two and key == "PADDRIGHT" and 2 or 1
		return self:Point()
	end
	if key == "PAD1" then return self:Press(self.index) end
	if key == "PAD2" then return self:Press(self.spec.back or two and 2 or 1) end
end

function UI.Dialog()
	if dialog then return dialog end

	dialog = Mixin(CreateFrame("Frame", "ForeverControllerTweaksDialog", UIParent), DialogMixin)
	dialog:SetSize(320, 120)
	dialog:EnableMouse(true)
	dialog:Hide()
	local bottom = dialog:CreateTexture(nil, "BACKGROUND", nil, -7)
	bottom:SetAtlas("UI-DialogBox-Background-Dark")
	bottom:SetPoint("TOPLEFT", 7, -7)
	bottom:SetPoint("BOTTOMRIGHT", -7, 7)
	local top = dialog:CreateTexture(nil, "BACKGROUND", nil, -4)
	top:SetAtlas(GameDialogBackgroundTop or "UI-DiamondDialogBox-Border")
	top:SetAllPoints()
	dialog.glow = UI.Glow(dialog, dialog, "gamepad-uiframediamondmetal-focus-large", -6, 6, 6, -6)
	dialog:SetScript("OnShow", function(self) self.glow:Show() end)
	dialog:SetScript("OnHide", function(self) self.glow:Hide() end)

	dialog.Text = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	dialog.Text:SetWidth(280)
	dialog.Text:SetSpacing(2)
	dialog.Text:SetPoint("TOP", 0, -16)
	dialog.SubText = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	dialog.SubText:SetWidth(280)
	dialog.SubText:SetPoint("TOP", dialog.Text, "BOTTOM", 0, -6)
	dialog.Button1 = dialogButton(dialog)
	dialog.Button1:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -6.5, 16)
	dialog.Button2 = dialogButton(dialog)
	dialog.Button2:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 6.5, 16)
	for index = 1, 2 do
		local button = dialog["Button" .. index]
		button:SetScript("OnClick", function() dialog:Press(index) end)
		button:SetScript("OnEnter", function()
			dialog.index = index
			dialog:Point()
		end)
	end
	return dialog
end

function UI.DialogShown() return dialog and dialog:IsShown() end

-- The addon's own tooltip in GameTooltip's art (TooltipDefaultLayout NineSlice, TOOLTIP_DEFAULT_BACKGROUND_COLOR):
-- a NORMAL_FONT_COLOR title, white lines, then the focused row's button actions as glyph + GREEN_FONT_COLOR text,
-- the way the gamepad Quest Log tooltip lists them. GameTooltip itself is shared with Blizzard's secure action
-- buttons, so the addon leaves it alone. spec = { title, lines = { text, ... }, actions = { { key, label }, ... },
-- side = "right" | "left" | "below" }.
local tooltip
local TIP_PAD, TIP_GAP, ACTION_GLYPH = 10, 2, 18

local function tooltipFrame()
	if tooltip then return tooltip end

	tooltip = CreateFrame("Frame", nil, UIParent)
	tooltip:SetClampedToScreen(true)
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then NineSliceUtil.ApplyLayoutByName(tooltip, "TooltipDefaultLayout") end
	local color = TOOLTIP_DEFAULT_BACKGROUND_COLOR
	if tooltip.Center and color and color.GetRGB then tooltip.Center:SetVertexColor(color:GetRGB()) end
	tooltip.title = tooltip:CreateFontString(nil, "ARTWORK", "GameTooltipHeaderText")
	tooltip.lines, tooltip.actions = {}, {}
	return tooltip
end

local function tipLine(i)
	local line = tooltip.lines[i] or tooltip:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	tooltip.lines[i] = line
	return line
end

local function tipAction(i)
	local action = tooltip.actions[i]
	if action then return action end

	action = CreateFrame("Frame", nil, tooltip)
	action:SetHeight(ACTION_GLYPH)
	action.glyph = UI.Glyph(action, ACTION_GLYPH)
	action.glyph:SetPoint("LEFT")
	action.text = action:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	action.text:SetPoint("LEFT", action.glyph, "RIGHT", 6, 0)
	tooltip.actions[i] = action
	return action
end

function UI.Tooltip(owner, spec)
	local tip = tooltipFrame()
	tip.owner = owner
	for _, line in ipairs(tip.lines) do line:Hide() end
	for _, action in ipairs(tip.actions) do action:Hide() end

	local y, width = TIP_PAD, 0
	tip.title:SetText(spec.title or "")
	tip.title:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
	tip.title:ClearAllPoints()
	tip.title:SetPoint("TOPLEFT", TIP_PAD, -y)
	y, width = y + tip.title:GetStringHeight() + TIP_GAP, tip.title:GetStringWidth()
	for i, text in ipairs(spec.lines or {}) do
		local line = tipLine(i)
		line:SetText(text)
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", TIP_PAD, -y)
		line:Show()
		y, width = y + line:GetStringHeight() + TIP_GAP, math.max(width, line:GetStringWidth())
	end
	if spec.actions and #spec.actions > 0 then y = y + 8 end
	for i, entry in ipairs(spec.actions or {}) do
		local action = tipAction(i)
		action.glyph:SetCode(entry[1])
		action.text:SetText(entry[2])
		action.text:SetTextColor(GREEN_FONT_COLOR:GetRGB())
		action:SetWidth(ACTION_GLYPH + 6 + action.text:GetStringWidth())
		action:ClearAllPoints()
		action:SetPoint("TOPLEFT", TIP_PAD, -y)
		action:Show()
		y, width = y + ACTION_GLYPH + 6, math.max(width, action:GetWidth())
	end

	tip:SetSize(width + TIP_PAD * 2, y - TIP_GAP + TIP_PAD)
	tip:ClearAllPoints()
	if spec.side == "left" then tip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -8, 0)
	elseif spec.side == "below" then tip:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT", -6, -8)
	else tip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, 0) end
	tip:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
	-- Every tooltip of ours belongs to the open window; others (the minimap AddOns menu) stay in TOOLTIP.
	local window = UI.Current()
	if window and window:IsShown() then UI.RaiseAbove(tip, window, "tooltip") else tip:SetFrameStrata("TOOLTIP") end
	tip:Show()
end

function UI.HideTooltip(owner)
	if tooltip and (not owner or tooltip.owner == owner) then tooltip:Hide() end
end

-- Section header in the character window's art: UI-Character-Info-Title with centred GameFontHighlight.
function UI.SectionHeader(parent, x, y, width, text)
	local header = CreateFrame("Frame", nil, parent)
	header:SetSize(width, 40)
	UI.At(header, parent, x, y)
	local bg = header:CreateTexture(nil, "BACKGROUND")
	bg:SetAtlas("UI-Character-Info-Title")
	bg:SetAllPoints()
	header.text = header:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	header.text:SetPoint("CENTER", 0, 1)
	header.text:SetText(text)
	return header
end

-- The character window's vertical side tabs (LargeSideTabButtonTemplate's art: common-sidetab, -mask, -selected,
-- -hover; Camelot icon offset -4) on the window's right edge, with the L1 glyph above the column and R1 below
-- (GamepadTabIndicatorsTemplate's place and size; the end glyph shows its disabled state). specs = { { icon, name,
-- open }, ... }; index = this window's tab.
local TAB_ICON_X = -4

-- A segmented control in a window header (Touch's On/Off and Show, Keyboard's settings): native footer slot plates
-- side by side, the selected one lit with UI-QuestTitleHighlight and gold text. specs = { { id, label }, ... };
-- onPick(id) on a click or A. segments:Select(id) lights one.
local SEGMENT_H = 26

function UI.Segments(parent, specs, x, y, width, onPick)
	local segments = {}
	for i, spec in ipairs(specs) do
		local segment = CreateFrame("Button", nil, parent)
		segment:SetSize(width, SEGMENT_H)
		UI.At(segment, parent, x + (i - 1) * width, y)
		segment.bg = segment:CreateTexture(nil, "BACKGROUND")
		segment.bg:SetAtlas("gamepad-footer-slot-bg")
		segment.bg:SetAllPoints()
		segment.highlight = segment:CreateTexture(nil, "ARTWORK")
		segment.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		segment.highlight:SetBlendMode("ADD")
		segment.highlight:SetAllPoints()
		segment.label = segment:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		segment.label:SetPoint("CENTER")
		segment.label:SetText(spec[2])
		segment.id, segment.text = spec[1], spec[2]
		segment.click = function() onPick(spec[1]) end
		segment:SetScript("OnClick", segment.click)
		segments[i] = segment
	end
	function segments.Select(_, id)
		for _, segment in ipairs(segments) do
			local on = segment.id == id
			segment.highlight:SetShown(on)
			segment.label:SetFontObject(on and "GameFontNormal" or "GameFontDisable")
		end
	end
	return segments
end

function UI.SideTabs(window, specs, index)
	local info = C_Texture.GetAtlasInfo("common-sidetab")
	local width, height = info and info.width or 50, info and info.height - 5 or 45
	local column = CreateFrame("Frame", nil, window)
	column:SetSize(width, height * #specs)
	column:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, -30)
	column.tabs = {}
	for i, spec in ipairs(specs) do
		local tab = CreateFrame("Button", nil, column)
		tab:SetSize(width, height)
		tab:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -(i - 1) * height)
		local bg = tab:CreateTexture(nil, "BACKGROUND")
		bg:SetAtlas("common-sidetab", true)
		bg:SetPoint("CENTER")
		local icon = tab:CreateTexture(nil, "ARTWORK")
		icon:SetTexture(spec[1])
		icon:SetSize(32, 32)
		icon:SetPoint("CENTER", TAB_ICON_X, 0)
		local mask = tab:CreateMaskTexture()
		mask:SetAtlas("common-sidetab-mask", true)
		mask:SetPoint("CENTER")
		icon:AddMaskTexture(mask)
		local selected = tab:CreateTexture(nil, "OVERLAY")
		selected:SetAtlas("common-sidetab-selected", true)
		selected:SetPoint("CENTER")
		selected:SetShown(i == index)
		local hover = tab:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAtlas("common-sidetab-hover", true)
		hover:SetPoint("CENTER")
		tab:SetScript("OnClick", function() if i ~= index then spec[3]() end end)
		tab:SetScript("OnEnter", function() UI.Tooltip(tab, { title = spec[2], side = "right" }) end)
		tab:SetScript("OnLeave", function() UI.HideTooltip(tab) end)
		column.tabs[i] = tab
	end
	local previous = UI.Glyph(column, 26, "L1")
	previous:SetPoint("BOTTOM", column.tabs[1], "TOP", 0, 0)
	previous:SetDisabled(index == 1)
	local nextGlyph = UI.Glyph(column, 26, "R1")
	nextGlyph:SetPoint("TOP", column.tabs[#specs], "BOTTOM", 0, 0)
	nextGlyph:SetDisabled(index == #specs)
	column.previous, column.next, column.specs, column.index = previous, nextGlyph, specs, index

	-- Step to the neighbouring tab, no wrap (the native indicators stop at the ends).
	function column:Step(offset)
		local spec = self.specs[self.index + offset]
		if spec then spec[3]() end
	end
	return column
end
