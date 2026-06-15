# event sound effects for the bash raycaster
#
# how it works:
#   music.bash is the synth.  when its stdout is not a tty its player() just
#   cat()s the raw PCM, so we can capture it.  bash DSP is slow, so we render
#   each effect to a small WAV file *once* at startup and then just play the
#   cached file on each event (backgrounded + throttled).
#
# notes:
#   - music.bash needs bash 4+ (associative arrays); we invoke it with "$BASH"
#     (the interpreter already running the game), never a bare `bash`, because
#     the system bash may be too old (e.g. macOS ships 3.2).
#   - WAV is used because it is the one format every detected player accepts
#     (afplay needs a real container; it cannot play raw PCM).
#   - if no player is available (or NOSOUND is set) SOUND stays 0 and every
#     sfx call is a silent no-op, so terminals without audio behave exactly as
#     before.
#   - mute: MUTE=1 (env or .config) starts muted; sfx_toggle_mute flips it live.

# short effects in music.bash arg syntax ("note:duration%").  bump is wired to
# wall collisions; door/map are ready for those events when they exist.
declare -A _sfx_notes=(
    [bump]='c3:40 g2:55'
    [door]='e4:40 b4:40 e5:80'
    [map]='c4:35 e4:35 g4:35 c5:90'
)

_sfx_throttle=120000          # min microseconds between repeats of one effect
declare -A _sfx_last
SOUND=0 MUTED=0 _sfx_dir=

# write a canonical PCM / mono / 16-bit WAV header to stdout for $1 data bytes
_wav_header () {
    local data=$1 rate=${samples:-8000} bits=16 ch=1 byterate align riff
    (( byterate = rate*ch*bits/8, align = ch*bits/8, riff = 36 + data ))
    # print integer $1 little-endian, $2 bytes wide, as raw bytes
    _le () { local v=$1 w=$2 i out=; for ((i=0;i<w;i++)); do printf -v out '%s\\x%02x' "$out" "$((v&255))"; ((v>>=8)); done; printf %b "$out"; }
    printf %s RIFF; _le "$riff" 4; printf %s WAVE
    printf %s 'fmt '; _le 16 4; _le 1 2; _le "$ch" 2; _le "$rate" 4; _le "$byterate" 4; _le "$align" 2; _le "$bits" 2
    printf %s data; _le "$data" 4
}

# render one effect: $1 name, $2 notes -> $_sfx_dir/$1.wav
_sfx_render () {
    local name=$1 notes=$2 pcm="$_sfx_dir/$1.pcm" wav="$_sfx_dir/$1.wav" n
    "$BASH" ./music.bash $notes > "$pcm" 2>/dev/null || { rm -f "$pcm"; return; }
    n=$(wc -c < "$pcm")
    (( n > 200 )) || { rm -f "$pcm"; return; }   # synth produced nothing usable
    { _wav_header "$n"; cat "$pcm"; } > "$wav" 2>/dev/null
    rm -f "$pcm"
}

# detect a player, render the effects.  safe to leave SOUND=0 on any failure.
sfx_init () {
    [[ $NOSOUND ]] && return
    [[ $MUTE ]] && MUTED=1

    if   command -v afplay >/dev/null; then _sfx_play () { afplay "$1"; }
    elif command -v ffplay >/dev/null; then _sfx_play () { ffplay -v quiet -nodisp -autoexit "$1"; }
    elif command -v paplay >/dev/null; then _sfx_play () { paplay "$1"; }
    elif command -v aplay  >/dev/null; then _sfx_play () { aplay -q "$1"; }
    elif command -v mpv    >/dev/null; then _sfx_play () { mpv --no-video --no-terminal "$1"; }
    else return; fi

    _sfx_dir=$(mktemp -d "${TMPDIR:-/tmp}/bashray-sfx.XXXXXX") 2>/dev/null || return
    SOUND=1

    # render in a detached, monitor-off subshell so background jobs are silent
    # and don't print [n] PID lines over the game screen
    ( set +m
      { for name in "${!_sfx_notes[@]}"; do _sfx_render "$name" "${_sfx_notes[$name]}"; done; } &
    ) 2>/dev/null
}

# play an effect by name; no-op unless enabled, unmuted, rendered, and not
# played within the throttle window.  fire-and-forget, never blocks the loop.
sfx () {
    (( SOUND && !MUTED )) || return
    local wav="$_sfx_dir/$1.wav" now
    [[ -s $wav ]] || return
    now=${EPOCHREALTIME/.}
    (( now - ${_sfx_last[$1]:-0} < _sfx_throttle )) && return
    _sfx_last[$1]=$now
    { _sfx_play "$wav"; } &>/dev/null &
}

# flip mute; give an audible confirmation when turning sound back on.
# debounced because held keys re-fire every frame under the kitty protocol.
sfx_toggle_mute () {
    local now=${EPOCHREALTIME/.}
    (( now - ${_mute_t:-0} < 300000 )) && return
    _mute_t=$now
    (( MUTED = !MUTED )); (( MUTED )) || sfx map
}

sfx_cleanup () { [[ $_sfx_dir ]] && rm -rf "$_sfx_dir"; }
