-- groq-flow Hammerspoon config — copy into ~/.hammerspoon/init.lua
-- (merge with your existing config if you already have one).
--
-- Role in the setup chain:
--   Caps Lock --(Karabiner remaps to F18)--> Hammerspoon --> groq-flow.sh
--
-- Hammerspoon is the host that holds Microphone + Accessibility permissions,
-- so the `sox` (record) and `osascript` (type) it spawns run in a granted
-- context. A key launched directly by Karabiner's shell_command runs from a
-- background daemon that macOS will NOT grant the microphone to — hence this
-- F18 hop through Hammerspoon.

require("hs.ipc") -- enables the `hs` command-line tool used to toggle the meter

-- EDIT THIS to wherever your script lives (e.g. ~/.local/bin/groq-flow).
local GROQFLOW = os.getenv("HOME") .. "/.local/bin/groq-flow"

-- ---- Recording indicator: small animated red level-meter, bottom-center ----
-- Toggled by groq-flow.sh via `hs -c "groqflowIndicator(true|false)"`.
groqflowCanvas = nil
groqflowTimer = nil

local GF_BARS, GF_BARW, GF_GAP, GF_MAXH, GF_MINH = 5, 5, 4, 24, 5
local GF_PAD = 36 -- px above the bottom of the usable screen

-- Human color name → RGB for the meter bars (set via the indicator-color config).
local GF_COLORS = {
  red    = { 1.00, 0.23, 0.19 },
  orange = { 1.00, 0.58, 0.00 },
  yellow = { 1.00, 0.80, 0.00 },
  green  = { 0.20, 0.80, 0.35 },
  blue   = { 0.20, 0.52, 1.00 },
  purple = { 0.70, 0.30, 0.95 },
  pink   = { 1.00, 0.35, 0.70 },
  white  = { 0.95, 0.95, 0.95 },
}

function groqflowIndicator(on, color)
  if groqflowTimer then groqflowTimer:stop(); groqflowTimer = nil end
  if groqflowCanvas then groqflowCanvas:delete(); groqflowCanvas = nil end
  if not on then return end

  local rgb = GF_COLORS[color] or GF_COLORS.red
  local fill = { red = rgb[1], green = rgb[2], blue = rgb[3], alpha = 0.95 }

  local f = hs.screen.mainScreen():frame()
  local w = GF_BARS * GF_BARW + (GF_BARS - 1) * GF_GAP
  local x = f.x + (f.w - w) / 2
  local y = f.y + f.h - GF_MAXH - GF_PAD

  groqflowCanvas = hs.canvas.new({ x = x, y = y, w = w, h = GF_MAXH })
  for i = 1, GF_BARS do
    groqflowCanvas[i] = {
      type = "rectangle",
      action = "fill",
      fillColor = fill,
      roundedRectRadii = { xRadius = 2.5, yRadius = 2.5 },
      frame = { x = (i - 1) * (GF_BARW + GF_GAP), y = GF_MAXH - GF_MINH, w = GF_BARW, h = GF_MINH },
    }
  end
  groqflowCanvas:level(hs.canvas.windowLevels.overlay)
  groqflowCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  groqflowCanvas:show()

  groqflowTimer = hs.timer.doEvery(0.1, function()
    if not groqflowCanvas then return end
    for i = 1, GF_BARS do
      local bh = GF_MINH + math.random() * (GF_MAXH - GF_MINH)
      groqflowCanvas[i].frame = { x = (i - 1) * (GF_BARW + GF_GAP), y = GF_MAXH - bh, w = GF_BARW, h = bh }
    end
  end)
end

-- ---- Hotkeys ---------------------------------------------------------------
local function runGroqflow()
  hs.task.new(GROQFLOW, nil):start()
end

hs.hotkey.bind({}, "f18", runGroqflow)          -- Caps Lock (via Karabiner → F18)
hs.hotkey.bind({ "cmd", "alt" }, "D", runGroqflow) -- backup chord

hs.alert.show("groq-flow config loaded")
