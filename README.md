# grokflow

A Whispr Flow-style dictation tool for macOS. Press a hotkey to start
recording, press it again to stop — the transcript is typed straight into
whatever app has focus. Transcription runs through the **xAI Grok
Speech-to-Text API** (`grok-stt`).

It's the macOS cousin of [xhisper](https://github.com/imaginalnika/xhisper)
(Linux): same toggle-to-dictate idea, but built on macOS audio + Accessibility
APIs and pointed at Grok instead of Groq Whisper.

## How it works

1. First hotkey press → starts recording your mic (`sox`, 16 kHz mono).
2. Second press → stops, uploads the clip to `https://api.x.ai/v1/stt`,
   gets text back, and types it at your cursor.
3. Silent clips and API errors just show a notification and do nothing.

The API key never leaves your machine except in the request to xAI. This is a
local CLI, not a web app, so the key isn't exposed to a browser.

## Install

```bash
# 1. Dependencies
brew install sox jq curl

# 2. API key — get one at https://console.x.ai, then:
echo 'XAI_API_KEY=xai-xxxxxxxxxxxxxxxxxxxxxxxx' >> ~/.env

# 3. Drop the script somewhere on your PATH and make it runnable
mkdir -p ~/bin
cp grokflow.sh ~/bin/grokflow
chmod +x ~/bin/grokflow

# 4. (optional) config
mkdir -p ~/.config/grokflow
cp default_grokflowrc ~/.config/grokflow/grokflowrc

# 5. Sanity check
grokflow --check
```

## Permissions (the part everyone misses)

macOS gates both the mic and synthetic keystrokes. Grant these to **whatever
app launches the hotkey** — your terminal, Raycast, Hammerspoon, BetterTouchTool,
or Shortcuts:

- **System Settings → Privacy & Security → Microphone** → enable the launching app
- **System Settings → Privacy & Security → Accessibility** → enable the launching app

If text isn't appearing, Accessibility is almost always the cause. If recording
fails, it's Microphone.

## Bind it to a hotkey

You can't bind a shell script to a global key on its own — you need a launcher.
Pick one:

**Raycast** (easiest): create a Script Command pointing at `~/bin/grokflow`,
then assign it a hotkey in Raycast's settings.

**Hammerspoon** — add to `~/.hammerspoon/init.lua`:

```lua
hs.hotkey.bind({"cmd", "alt"}, "D", function()
  hs.task.new("/Users/YOU/bin/grokflow", nil):start()
end)
```

**skhd** — add to `~/.skhdrc`:

```
cmd + alt - d : /Users/YOU/bin/grokflow
```

**Automator + Shortcuts**: wrap `~/bin/grokflow` in a "Run Shell Script" Quick
Action, then assign a keyboard shortcut to it in System Settings → Keyboard →
Keyboard Shortcuts → Services.

## Usage

- Run `grokflow` (via your hotkey) once to start, again to stop + transcribe.
- `grokflow --check` — verify deps, key, and mic.
- `grokflow --stop`  — abort a recording without transcribing.
- `grokflow --log`   — show the transcription log at `/tmp/grokflow.log`.

## Config (`~/.config/grokflow/grokflowrc`)

| Key | Default | What it does |
| --- | --- | --- |
| `model` | `grok-stt` | xAI STT model id |
| `language` | `en` | ISO-639-1 code; blank = auto-detect |
| `transcription-prompt` | _(empty)_ | jargon / spelling hints |
| `silence-threshold` | `-50` | dB peak below which a clip counts as silent |
| `paste-mode` | `type` | `type` (keystrokes) or `paste` (clipboard + Cmd-V) |
| `max-record-seconds` | `300` | hard cap on one recording |

## Notes & limits

- **`type` vs `paste`**: `type` simulates keystrokes and never touches your
  clipboard, but is slower for long dictations and can occasionally drop
  characters in apps that throttle input. `paste` is faster and Unicode-clean;
  it briefly uses the clipboard and restores it afterward. Switch in the config.
- **Terminal apps**: keystroke injection works in most apps. If a specific app
  misbehaves, try `paste-mode: paste`.
- Grok STT pricing at launch was about $0.10/hour of audio for REST batch
  transcription — verify current rates and your account limits in the xAI console.
- This uses the REST endpoint (record-then-send). Grok also has a streaming
  WebSocket endpoint for live captions; that's a different, more involved build.

## Troubleshooting

- *Nothing types* → Accessibility permission for the launching app.
- *Recording fails / "No sound detected"* → Microphone permission, or lower
  `silence-threshold` to e.g. `-55`.
- *Transcription fails* → run `grokflow --log` to see the raw API response;
  usually a bad/expired `XAI_API_KEY` or a rate limit.
