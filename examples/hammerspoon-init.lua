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

require("hs.ipc") -- enables the `hs` command-line tool used to toggle the indicator

-- EDIT THIS to wherever your script lives (e.g. ~/.local/bin/groq-flow).
local GROQ_FLOW = os.getenv("HOME") .. "/.local/bin/groq-flow"

-- ---- Recording indicator ---------------------------------------------------
-- Toggled by groq-flow.sh via:
--   hs -c "groqFlowIndicator(true, '<color>', '<style>')"
-- Styles: "meter" (animated level bars) and "orb" (pulsing 3D Grok orb).
groqFlowCanvas = nil
groqFlowTimer = nil

-- Human color name → RGB for the indicator (set via the indicator-color config).
local GF_COLORS = {
  red    = { 0.933, 0.310, 0.208 }, -- Grok bolt #EE4F35 (sampled from the logo)
  orange = { 1.00, 0.58, 0.00 },
  yellow = { 1.00, 0.80, 0.00 },
  green  = { 0.20, 0.80, 0.35 },
  blue   = { 0.20, 0.52, 1.00 },
  purple = { 0.70, 0.30, 0.95 },
  pink   = { 1.00, 0.35, 0.70 },
  white  = { 0.95, 0.95, 0.95 },
}

local GF_BARS, GF_BARW, GF_GAP, GF_MAXH, GF_MINH = 5, 5, 4, 24, 5
local GF_PAD = 36 -- px above the bottom of the usable screen

local function gfLighter(rgb, f) -- blend toward white
  return { red = rgb[1] + (1 - rgb[1]) * f, green = rgb[2] + (1 - rgb[2]) * f, blue = rgb[3] + (1 - rgb[3]) * f, alpha = 1 }
end
local function gfDarker(rgb, f) -- scale toward black
  return { red = rgb[1] * f, green = rgb[2] * f, blue = rgb[3] * f, alpha = 1 }
end
local function gfPos(w, h) -- bottom-center placement on the main screen
  local f = hs.screen.mainScreen():frame()
  return f.x + (f.w - w) / 2, f.y + f.h - h - GF_PAD
end

-- Stylized lightning bolt outline (normalized 0..1, y points down).
local GF_BOLT = {
  { 0.52, 0.02 }, { 0.18, 0.56 }, { 0.44, 0.56 },
  { 0.30, 0.98 }, { 0.82, 0.42 }, { 0.56, 0.42 }, { 0.70, 0.02 },
}
local function gfBoltCoords(cx, cy, size)
  local pts = {}
  for i = 1, #GF_BOLT do
    pts[i] = { x = cx + (GF_BOLT[i][1] - 0.5) * size, y = cy + (GF_BOLT[i][2] - 0.5) * size }
  end
  return pts
end

-- ---- Style: animated level-meter bars --------------------------------------
local function groqFlowShowMeter(rgb)
  local w = GF_BARS * GF_BARW + (GF_BARS - 1) * GF_GAP
  local x, y = gfPos(w, GF_MAXH)
  local fill = { red = rgb[1], green = rgb[2], blue = rgb[3], alpha = 0.95 }
  groqFlowCanvas = hs.canvas.new({ x = x, y = y, w = w, h = GF_MAXH })
  for i = 1, GF_BARS do
    groqFlowCanvas[i] = {
      type = "rectangle",
      action = "fill",
      fillColor = fill,
      roundedRectRadii = { xRadius = 2.5, yRadius = 2.5 },
      frame = { x = (i - 1) * (GF_BARW + GF_GAP), y = GF_MAXH - GF_MINH, w = GF_BARW, h = GF_MINH },
    }
  end
  groqFlowCanvas:level(hs.canvas.windowLevels.overlay)
  groqFlowCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  groqFlowCanvas:show()
  groqFlowTimer = hs.timer.doEvery(0.1, function()
    if not groqFlowCanvas then return end
    for i = 1, GF_BARS do
      local bh = GF_MINH + math.random() * (GF_MAXH - GF_MINH)
      groqFlowCanvas[i].frame = { x = (i - 1) * (GF_BARW + GF_GAP), y = GF_MAXH - bh, w = GF_BARW, h = bh }
    end
  end)
end

-- ---- Style: pulsing 3D orb with the Grok lightning bolt ---------------------
local function groqFlowShowOrb(rgb)
  local SZ = 84
  local x, y = gfPos(SZ, SZ)
  local cx, cy, R = SZ / 2, SZ / 2, SZ * 0.34
  groqFlowCanvas = hs.canvas.new({ x = x, y = y, w = SZ, h = SZ })
  groqFlowCanvas[1] = { -- thin (~2px) ring around the orb (gently pulses)
    type = "circle", action = "stroke",
    strokeColor = { red = rgb[1], green = rgb[2], blue = rgb[3], alpha = 0.9 },
    strokeWidth = 2,
    center = { x = cx, y = cy }, radius = R + 2,
  }
  groqFlowCanvas[2] = { -- white 3D sphere: radial gradient bright -> light gray
    type = "circle", action = "fill",
    fillGradient = "radial",
    fillGradientColors = { { white = 1, alpha = 1 }, { white = 0.78, alpha = 1 } },
    fillGradientCenter = { x = -0.35, y = -0.35 }, -- highlight toward top-left
    center = { x = cx, y = cy }, radius = R,
  }
  groqFlowCanvas[3] = { -- bright glossy specular highlight
    type = "circle", action = "fill",
    fillColor = { white = 1, alpha = 0.9 },
    center = { x = cx - R * 0.34, y = cy - R * 0.36 }, radius = R * 0.18,
  }
  groqFlowCanvas[4] = { -- the Grok lightning bolt — the colored part
    type = "segments", closed = true, action = "fill",
    fillColor = { red = rgb[1], green = rgb[2], blue = rgb[3], alpha = 1 },
    coordinates = gfBoltCoords(cx, cy, R * 1.45),
  }
  groqFlowCanvas:level(hs.canvas.windowLevels.overlay)
  groqFlowCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  groqFlowCanvas:show()
  local t = 0
  groqFlowTimer = hs.timer.doEvery(0.05, function() -- gentle ~2.2s pulse of the ring
    if not groqFlowCanvas then return end
    t = t + 1
    local u = math.sin(t * (2 * math.pi / 44)) * 0.5 + 0.5
    groqFlowCanvas[1].strokeColor = { red = rgb[1], green = rgb[2], blue = rgb[3], alpha = 0.55 + 0.45 * u }
  end)
end

function groqFlowIndicator(on, color, style)
  if groqFlowTimer then groqFlowTimer:stop(); groqFlowTimer = nil end
  if groqFlowCanvas then groqFlowCanvas:delete(); groqFlowCanvas = nil end
  if not on then return end
  local rgb = GF_COLORS[color] or GF_COLORS.red
  if style == "orb" then
    groqFlowShowOrb(rgb)
  else
    groqFlowShowMeter(rgb)
  end
end

-- ---- Hotkeys ---------------------------------------------------------------
local function runGroqFlow()
  hs.task.new(GROQ_FLOW, nil):start()
end

hs.hotkey.bind({}, "f18", runGroqFlow)             -- Caps Lock (via Karabiner → F18)
hs.hotkey.bind({ "cmd", "alt" }, "D", runGroqFlow) -- backup chord

groqFlowBuild = "ring-v1"
hs.alert.show("groq-flow loaded (" .. groqFlowBuild .. ")")
