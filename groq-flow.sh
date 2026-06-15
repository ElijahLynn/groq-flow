#!/bin/bash
# groq-flow v1.0 — Whispr Flow-style dictation for macOS.
# Push a hotkey to start recording, push it again to stop and transcribe.
# The transcript is typed at your cursor in whatever app is focused.
#
# Transcription via the Groq Speech-to-Text REST API (model: whisper-large-v3-turbo).
#
# Requirements (install with: brew install sox jq curl):
#   - sox      (audio recording)
#   - jq       (JSON parsing)
#   - curl     (HTTP)
#   - osascript / pbcopy  (built into macOS — typing & clipboard)
#
# Setup:
#   1. Get a Groq API key from https://console.groq.com/keys and put it in
#      ~/.env (or a project-local ./.env, which overrides ~/.env) :
#        GROQ_API_KEY=gsk_xxxxxxxxxxxxxxxxxxxxxxxx
#   2. chmod +x groq-flow.sh ; ./groq-flow.sh --check
#   3. Grant Accessibility to Hammerspoon; Microphone is prompted on first
#      recording (System Settings > Privacy & Security).
#   4. Bind a hotkey to: /path/to/groq-flow.sh   (see README).

set -euo pipefail

# Ensure Homebrew tools (sox/rec/jq) resolve even when launched from a
# minimal-PATH context like Karabiner-Elements, Raycast, or launchd.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# ---- Load API key ----------------------------------------------------------
# Source ~/.env first (the usual spot for a globally-invoked hotkey command),
# then a project-local ./.env if present — local wins so you can override per dir.
[ -f "$HOME/.env" ] && source "$HOME/.env"
[ -f "./.env" ] && source "./.env"

# macOS sox needs to be told to use the CoreAudio driver explicitly; otherwise
# it fails with "no default audio device configured". Honor an existing override.
export AUDIODRIVER="${AUDIODRIVER:-coreaudio}"

# ---- Defaults (override in ~/.config/groq-flow/groq-flowrc) -------------------
model="whisper-large-v3-turbo"
language="en"             # ISO-639-1; "" = auto-detect
transcription_prompt=""   # domain words / spelling hints
silence_threshold=-45     # dB RMS; clips with average level below this are treated as silent
paste_mode="type"         # "type" = simulate keystrokes, "paste" = clipboard + Cmd-V
max_record_seconds=300    # hard cap so a forgotten recording can't run forever
indicator_color="red"     # indicator color: red, orange, yellow, green, blue, purple, pink, white
indicator_style="meter"   # indicator style: "meter" (level bars) or "orb" (pulsing Grok orb)
input_device=""           # CoreAudio input device name; "" = system default mic

RECORDING="/tmp/groq-flow.wav"
PIDFILE="/tmp/groq-flow.pid"
LOGFILE="/tmp/groq-flow.log"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/groq-flow/groq-flowrc"

# Resolve the input device BEFORE launching rec so the very first capture uses
# the right mic. Bluetooth headset mics cold-start slowly (the link switches to
# hands-free mode) and clip the first word — pinning to the built-in mic via the
# input-device setting avoids that. (Full config parse happens below.)
if [ -f "$CONFIG_FILE" ]; then
  _dev=$(sed -n 's/^[[:space:]]*input-device[[:space:]]*:[[:space:]]*//p' "$CONFIG_FILE" | head -1)
  _dev="${_dev%\"}"; _dev="${_dev#\"}"
  [ -n "$_dev" ] && export AUDIODEV="$_dev"
fi

# Start capturing IMMEDIATELY on a plain toggle press — before the rest of setup
# — so the first word isn't lost to startup latency. Only for the normal toggle
# (no args) when not already recording; flags and the stop press fall through to
# Main below. Native rate/channels (no -r/-c) keep the device open fast.
GF_EARLY_START=0
if [ -z "${1:-}" ] && command -v rec >/dev/null 2>&1 \
   && ! { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }; then
  rm -f "$PIDFILE"
  rec -q "$RECORDING" trim 0 "$max_record_seconds" >/dev/null 2>&1 &
  echo $! > "$PIDFILE"
  GF_EARLY_START=1
fi
if [ -f "$CONFIG_FILE" ]; then
  while IFS=: read -r key value || [ -n "$key" ]; do
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
    case "$key" in
      model)                 model="$value" ;;
      language)              language="$value" ;;
      transcription-prompt)  transcription_prompt="$value" ;;
      silence-threshold)     silence_threshold="$value" ;;
      paste-mode)            paste_mode="$value" ;;
      max-record-seconds)    max_record_seconds="$value" ;;
      indicator-color)       indicator_color="$value" ;;
      indicator-style)       indicator_style="$value" ;;
      input-device)          input_device="$value" ;;
    esac
  done < "$CONFIG_FILE"
fi

# ---- Helpers ---------------------------------------------------------------
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOGFILE"; }

notify() {
  # title, message — uses macOS Notification Center, silently no-ops if blocked
  /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true
}

die() { echo "Error: $*" >&2; log "ERROR: $*"; exit 1; }

# Recording indicator: a persistent on-screen overlay via Hammerspoon if it's
# reachable (hs CLI + IPC), otherwise a transient macOS notification.
indicator_show() {
  # Sanitize to letters only so it's safe to interpolate into the hs command.
  local color="${indicator_color//[^a-zA-Z]/}"
  local style="${indicator_style//[^a-zA-Z]/}"
  if command -v hs >/dev/null 2>&1 && hs -c "groqFlowIndicator(true, '${color:-red}', '${style:-meter}')" >/dev/null 2>&1; then
    return
  fi
  notify "groq-flow" "Recording… (hotkey again to stop)"
}
indicator_hide() {
  command -v hs >/dev/null 2>&1 && hs -c "groqFlowIndicator(false)" >/dev/null 2>&1 || true
}

check_deps() {
  local missing=()
  for cmd in sox jq curl rec; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing dependencies: ${missing[*]}" >&2
    echo "Install with:  brew install sox jq curl" >&2
    exit 1
  fi
  [ -n "${GROQ_API_KEY:-}" ] || die "GROQ_API_KEY not set. Add it to ~/.env"
  echo "All dependencies present. GROQ_API_KEY is set."
  echo "Audio driver: AUDIODRIVER=$AUDIODRIVER"
  echo "Recording device check:"
  local err
  if err=$(rec -q -c 1 -r 16000 /tmp/groq-flow_devtest.wav trim 0 0.1 2>&1); then
    echo "  microphone OK"
    rm -f /tmp/groq-flow_devtest.wav
  else
    echo "  microphone test FAILED:"
    echo "    ${err//$'\n'/$'\n'    }"
    echo "  • 'can not open audio device' → grant your terminal/launcher app"
    echo "    Microphone access in System Settings → Privacy & Security → Microphone."
    echo "  • 'no default audio device configured' → set AUDIODRIVER=coreaudio."
  fi
}

# ---- Typing / pasting at the cursor ----------------------------------------
type_text() {
  local text="$1"
  [ -z "$text" ] && return 0

  if [ "$paste_mode" = "paste" ]; then
    # Clipboard + Cmd-V. Faster for long text and Unicode-safe, but clobbers
    # whatever is on the clipboard.
    local saved; saved="$(pbpaste 2>/dev/null || true)"
    printf '%s' "$text" | pbcopy
    /usr/bin/osascript -e 'tell application "System Events" to keystroke "v" using command down'
    sleep 0.15
    printf '%s' "$saved" | pbcopy   # restore previous clipboard
  else
    # Simulate keystrokes directly. Unicode-safe via System Events keystroke.
    # Escape backslashes and double quotes for AppleScript.
    local esc
    esc=$(printf '%s' "$text" | sed 's/\\/\\\\/g; s/"/\\"/g')
    /usr/bin/osascript -e "tell application \"System Events\" to keystroke \"$esc\""
  fi
}

# ---- Silence detection -----------------------------------------------------
is_silent() {
  local recording="$1"
  # Use RMS (average) amplitude, not peak: it reflects sustained energy, so it
  # tells real speech apart from quiet room tone (which a stray click would spike
  # on a peak meter and wrongly pass through to the API as "sound").
  local rms
  rms=$(sox "$recording" -n stat 2>&1 | awk -F: '/RMS[[:space:]]+amplitude/{gsub(/ /,"",$2); print $2}')
  [ -z "$rms" ] && return 1
  # amplitude 0..1 -> dB. Guard against 0.
  awk -v a="$rms" -v t="$silence_threshold" 'BEGIN{
    if (a<=0) { print "silent"; exit }
    db = 20*log(a)/log(10);
    if (db < t) print "silent"; else print "sound";
  }' | grep -q silent
}

# Whisper-class models loop/repeat when fed (near-)silence — e.g. "iDRAC, RHEL,
# iDRAC, RHEL, ...". Treat output as hallucination when it's long but made of
# very few unique words.
is_repetitive() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' ' ' | awk '
    { for (i = 1; i <= NF; i++) { total++; seen[$i] = 1 } }
    END {
      uniq = 0; for (k in seen) uniq++;
      exit (total >= 6 && uniq <= total * 0.4) ? 0 : 1;
    }'
}

# Whisper-class models echo the bias prompt when the audio is (near-)silent, so
# an empty press can "transcribe" to your jargon list. Treat the result as
# no-speech when every word of it also appears in the transcription prompt.
is_prompt_echo() {
  local text="$1"
  [ -z "$transcription_prompt" ] && return 1
  local norm_prompt norm_text w
  norm_prompt=$(printf ' %s ' "$transcription_prompt" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' ' ')
  norm_text=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' ' ')
  [ -z "${norm_text// /}" ] && return 1   # no real words -> let other checks handle it
  for w in $norm_text; do
    case "$norm_prompt" in
      *" $w "*) ;;        # word came from the prompt
      *) return 1 ;;       # a word outside the prompt -> real speech, keep it
    esac
  done
  return 0                 # every word was a prompt word -> echo, discard
}

# ---- Transcription via Groq STT --------------------------------------------
transcribe() {
  local recording="$1"
  local start_ns; start_ns=$(date +%s)

  local lang_args=()
  [ -n "$language" ] && lang_args=(-F "language=$language")

  local prompt_args=()
  [ -n "$transcription_prompt" ] && prompt_args=(-F "prompt=$transcription_prompt")

  local response
  response=$(curl -s --max-time 120 -X POST "https://api.groq.com/openai/v1/audio/transcriptions" \
    -H "Authorization: Bearer $GROQ_API_KEY" \
    -F "model=$model" \
    -F "file=@$recording" \
    -F "response_format=json" \
    "${lang_args[@]}" \
    "${prompt_args[@]}")

  # Groq's OpenAI-compatible endpoint returns JSON with a "text" field.
  local text
  text=$(printf '%s' "$response" | jq -r '.text // empty' 2>/dev/null)

  if [ -z "$text" ]; then
    local err
    err=$(printf '%s' "$response" | jq -r '.error.message // .error // empty' 2>/dev/null)
    log "Transcription failed. Raw response: $response"
    notify "groq-flow" "Transcription failed${err:+: $err}"
    echo ""
    return 1
  fi

  # Strip a common leading space.
  text="${text# }"
  log "Transcription (${SECONDS}s start->now): [$text]"
  printf '%s' "$text"
}

# ---- Recording control -----------------------------------------------------
start_recording() {
  log "Recording started."
  # Native rate/channels for lowest startup latency (no resampler priming).
  # rec writes until killed or max_record_seconds elapses.
  [ -n "$input_device" ] && export AUDIODEV="$input_device"
  rec -q "$RECORDING" trim 0 "$max_record_seconds" >/dev/null 2>&1 &
  echo $! > "$PIDFILE"
  indicator_show
}

stop_and_transcribe() {
  local pid; pid=$(cat "$PIDFILE")
  rm -f "$PIDFILE"
  kill "$pid" 2>/dev/null || true
  indicator_hide
  sleep 0.3   # let sox flush the WAV

  [ -f "$RECORDING" ] || { notify "groq-flow" "No recording found"; exit 0; }

  if is_silent "$RECORDING"; then
    log "Silent clip — nothing to transcribe."
    rm -f "$RECORDING"
    exit 0
  fi

  local transcription
  transcription=$(transcribe "$RECORDING") || { rm -f "$RECORDING"; exit 1; }
  rm -f "$RECORDING"

  [ -z "$transcription" ] && exit 0
  if is_prompt_echo "$transcription" || is_repetitive "$transcription"; then
    log "Discarded likely hallucination (no speech): [$transcription]"
    exit 0
  fi
  type_text "$transcription"
}

# ---- Main ------------------------------------------------------------------
case "${1:-}" in
  --check)  check_deps; exit 0 ;;
  --log)    [ -f "$LOGFILE" ] && cat "$LOGFILE" || echo "No log at $LOGFILE"; exit 0 ;;
  --stop)   # force-stop any running recording without transcribing
            [ -f "$PIDFILE" ] && { kill "$(cat "$PIDFILE")" 2>/dev/null || true; rm -f "$PIDFILE" "$RECORDING"; echo "Stopped."; } || echo "Not recording."
            exit 0 ;;
  --help|-h)
    grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '1d'
    exit 0 ;;
  "") ;; # normal toggle
  *) die "Unknown option '$1' (try --help)" ;;
esac

command -v rec >/dev/null 2>&1 || die "sox not installed. Run: brew install sox  (then ./groq-flow.sh --check)"

# Recording was already launched at the top (see GF_EARLY_START); just confirm.
if [ "$GF_EARLY_START" = "1" ]; then
  log "Recording started."
  indicator_show
  exit 0
fi

# Toggle: if a recording PID is live, stop+transcribe; otherwise start (fallback).
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  [ -n "${GROQ_API_KEY:-}" ] || die "GROQ_API_KEY not set. Add it to ~/.env"
  stop_and_transcribe
else
  rm -f "$PIDFILE"
  start_recording
fi
