# Caps Lock dictation setup (Karabiner + Hammerspoon)

These files make **Caps Lock** toggle groq-flow dictation, with a small
recording indicator at the bottom of the screen (a level-meter or, with
`indicator-style: orb`, a pulsing 3D Grok orb).

## Why two tools?

```
Caps Lock ──(Karabiner: remap to F18)──▶ Hammerspoon (F18 hotkey) ──▶ groq-flow.sh
```

- **Karabiner-Elements** is the only reliable way to repurpose Caps Lock — macOS
  doesn't expose it as a bindable key to normal hotkey tools.
- We remap Caps Lock to **F18** (an unused key) rather than having Karabiner run
  the script directly. A command launched by Karabiner's `shell_command` runs
  from a background daemon that **macOS will not grant Microphone access to**, so
  recordings come back silent. Routing through **Hammerspoon** — a regular app
  you grant Microphone + Accessibility — gives `sox` and `osascript` a permitted
  context.

## Install

1. **Karabiner-Elements**

   ```bash
   brew install --cask karabiner-elements
   open -a Karabiner-Elements   # approve the driver + Input Monitoring when asked
   ```

   Copy `karabiner-caps-lock-to-f18.json` into
   `~/.config/karabiner/assets/complex_modifications/`, then in Karabiner →
   *Complex Modifications* → *Add rule* → enable **"Caps Lock → F18"**.

2. **Hammerspoon**

   ```bash
   brew install --cask hammerspoon
   ```

   Copy `hammerspoon-init.lua` to `~/.hammerspoon/init.lua` (merge if you already
   have one), **edit the `GROQFLOW` path** to your install location, then reload
   Hammerspoon (menu-bar icon → *Reload Config*).

3. **Permissions** — System Settings → Privacy & Security:
   - **Accessibility** → enable **Hammerspoon** (required to type the text)
   - **Microphone** → allow **Hammerspoon** when first prompted (required to record)
   - **Input Monitoring** → enable **Karabiner** (its installer prompts for this)

## Test

Click into any text field, tap **Caps Lock**, speak, tap **Caps Lock** again —
the indicator appears while recording and the transcript types at your cursor.
Run `groq-flow --log` if anything misbehaves.
