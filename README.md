# groq-flow

A Whispr Flow-style dictation tool for macOS. Press a hotkey to start
recording, press it again to stop — the transcript is typed straight into
whatever app has focus. Transcription runs through the **Groq Speech-to-Text
API** (`whisper-large-v3-turbo`).

**Mostly free.** The script costs nothing; you only need a free [Groq API
key](https://console.groq.com/keys). On the default model, Groq's free tier
includes **480 minutes (~8 hours) of audio per day** and **120 minutes per
hour** — more than enough for everyday dictation. Each clip counts for at
least 10 seconds. Limits are per organization and can change; see
[Groq rate limits](https://console.groq.com/docs/rate-limits).

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
brew install --cask hammerspoon

# 2. API key — get one at https://console.groq.com/keys, then:
echo 'GROQ_API_KEY=gsk_xxxxxxxxxxxxxxxxxxxxxxxx' >> ~/.env
# (or drop a project-local ./.env with the same line — it overrides ~/.env)

# 3. Drop the script somewhere on your PATH and make it runnable
mkdir -p ~/.local/bin
cp groq-flow.sh ~/.local/bin/groq-flow
chmod +x ~/.local/bin/groq-flow
# fish adds ~/.local/bin automatically; zsh users may need:
#   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

# 4. (optional) config
mkdir -p ~/.config/groq-flow
cp default_groq-flowrc ~/.config/groq-flow/groq-flowrc

# 5. Sanity check
groq-flow --check
```

## Permissions (the part everyone misses)

macOS gates microphone and synthetic keystrokes separately, and the permissions
attach to **the app that hosts the script** — with the recommended setup that's
**Hammerspoon**.

- **Microphone** → allow **Hammerspoon** (required to record). It won't appear in
  the list until it has tried recording once — trigger a dictation and allow the
  prompt. If the recording comes back as "No sound detected" with a *silent*
  clip, the host process never got mic access.
- **Accessibility** → enable **Hammerspoon** (required to type the text). If
  nothing types, this is almost always why.
- **Karabiner-Elements** has its own one-time setup: approve the **driver /
  system extension** and turn on **Input Monitoring** so it can remap Caps Lock.

All under **System Settings → Privacy & Security**.

## Bind it to a hotkey

### Caps Lock (recommended) — Karabiner → F18 → Hammerspoon

Caps Lock is a great push-to-dictate key, but macOS doesn't expose it as a
bindable key to normal hotkey tools. The working chain is:

```
Caps Lock ──(Karabiner: remap to F18)──▶ Hammerspoon (F18 hotkey) ──▶ groq-flow.sh
```

Why two tools? A command launched directly by Karabiner's `shell_command` runs
from a background daemon that **macOS won't grant Microphone access to** — so
recordings come back silent. Remapping Caps Lock to an unused key (**F18**) and
catching it in **Hammerspoon** — a real app you grant Microphone + Accessibility
— gives the spawned `sox`/`osascript` a permitted context. Hammerspoon also
draws the on-screen recording level-meter.

Ready-to-use configs are in [`examples/`](examples/) — see
[`examples/README.md`](examples/README.md) for step-by-step setup:

- [`examples/karabiner-caps-lock-to-f18.json`](examples/karabiner-caps-lock-to-f18.json) — importable Karabiner rule
- [`examples/hammerspoon-init.lua`](examples/hammerspoon-init.lua) — F18 binding + level-meter

```bash
brew install --cask karabiner-elements hammerspoon
```

### Other launchers

Any launcher that holds Microphone + Accessibility and can run a command on a
hotkey works (Raycast script command, skhd, an Automator Quick Action, etc.) —
just point it at your installed `groq-flow`. Caps Lock specifically still needs
Karabiner to remap it first.

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
- **Free tier limits**: see the summary at the top. Paid tiers bill per hour of
  audio — check the [Groq console](https://console.groq.com) for current rates.
- This uses the REST endpoint (record-then-send), which is ideal for
push-to-dictate.

## Troubleshooting

- *Nothing types* → Accessibility permission for Hammerspoon.
- *Recording fails / "No sound detected"* → use the hotkey once and allow the
  Microphone prompt, then check **System Settings → Privacy & Security →
  Microphone** for Hammerspoon; or lower `silence-threshold` to e.g. `-55`.
- *Transcription fails* → run `groq-flow --log` to see the raw API response;
usually a bad/expired `GROQ_API_KEY` or a rate limit.
