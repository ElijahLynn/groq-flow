# groq-flow

A Whispr Flow-style dictation tool for macOS. Press a hotkey to start
recording, press it again to stop — the transcript is typed straight into
whatever app has focus. Transcription runs through the **Groq Speech-to-Text
API** (`whisper-large-v3-turbo`).

It's the macOS cousin of [xhisper](https://github.com/imaginalnika/xhisper)
(Linux): same toggle-to-dictate idea, but built on macOS audio + Accessibility
APIs. Like xhisper, it uses Groq's blazing-fast Whisper inference (~200x+
real-time), so dictation feels near-instant.

## How it works

1. First hotkey press → starts recording your mic (`sox`, 16 kHz mono).
2. Second press → stops, uploads the clip to
  `https://api.groq.com/openai/v1/audio/transcriptions`, gets text back, and
  types it at your cursor.
3. Silent clips and API errors just show a notification and do nothing.

The API key is read from `~/.env` (handy for a global hotkey, which runs from
no particular directory) and, if present, a project-local `./.env` that takes
precedence. It never leaves your machine except in the request to Groq — this
is a local CLI, not a web app, so the key isn't exposed to a browser.

## Install

```bash
# 1. Dependencies
brew install sox jq curl

# 2. API key — get one at https://console.groq.com/keys, then:
echo 'GROQ_API_KEY=gsk_xxxxxxxxxxxxxxxxxxxxxxxx' >> ~/.env
# (or drop a project-local ./.env with the same line — it overrides ~/.env)

# 3. Drop the script somewhere on your PATH and make it runnable
mkdir -p ~/bin
cp groq-flow.sh ~/bin/groq-flow
chmod +x ~/bin/groq-flow

# 4. (optional) config
mkdir -p ~/.config/groq-flow
cp default_groq-flowrc ~/.config/groq-flow/groq-flowrc

# 5. Sanity check
groq-flow --check
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

**Raycast** (easiest): create a Script Command pointing at `~/bin/groq-flow`,
then assign it a hotkey in Raycast's settings.

**Hammerspoon** — add to `~/.hammerspoon/init.lua`:

```lua
hs.hotkey.bind({"cmd", "alt"}, "D", function()
  hs.task.new("/Users/YOU/bin/groq-flow", nil):start()
end)
```

**skhd** — add to `~/.skhdrc`:

```
cmd + alt - d : /Users/YOU/bin/groq-flow
```

**Automator + Shortcuts**: wrap `~/bin/groq-flow` in a "Run Shell Script" Quick
Action, then assign a keyboard shortcut to it in System Settings → Keyboard →
Keyboard Shortcuts → Services.

## Usage

- Run `groq-flow` (via your hotkey) once to start, again to stop + transcribe.
- `groq-flow --check` — verify deps, key, and mic.
- `groq-flow --stop`  — abort a recording without transcribing.
- `groq-flow --log`   — show the transcription log at `/tmp/groq-flow.log`.

## Config (`~/.config/groq-flow/groq-flowrc`)


| Key                    | Default                   | What it does                                       |
| ---------------------- | ------------------------- | -------------------------------------------------- |
| `model`                | `whisper-large-v3-turbo`  | Groq STT model id                                  |
| `language`             | `en`                      | ISO-639-1 code; blank = auto-detect                |
| `transcription-prompt` | *(empty)*                 | jargon / spelling hints                            |
| `silence-threshold`    | `-50`                     | dB peak below which a clip counts as silent        |
| `paste-mode`           | `type`                    | `type` (keystrokes) or `paste` (clipboard + Cmd-V) |
| `max-record-seconds`   | `300`                     | hard cap on one recording                          |

Set `model: whisper-large-v3` if you want the slightly more accurate (but
slower) model for long or noisy audio.

## Notes & limits

- **`type` vs `paste`**: `type` simulates keystrokes and never touches your
clipboard, but is slower for long dictations and can occasionally drop
characters in apps that throttle input. `paste` is faster and Unicode-clean;
it briefly uses the clipboard and restores it afterward. Switch in the config.
- **Terminal apps**: keystroke injection works in most apps. If a specific app
misbehaves, try `paste-mode: paste`.
- Groq transcription pricing is billed per hour of audio — verify current rates
and your account limits in the [Groq console](https://console.groq.com).
- This uses the REST endpoint (record-then-send), which is ideal for
push-to-dictate.

## Troubleshooting

- *Nothing types* → Accessibility permission for the launching app.
- *Recording fails / "No sound detected"* → Microphone permission, or lower
`silence-threshold` to e.g. `-55`.
- *Transcription fails* → run `groq-flow --log` to see the raw API response;
usually a bad/expired `GROQ_API_KEY` or a rate limit.
