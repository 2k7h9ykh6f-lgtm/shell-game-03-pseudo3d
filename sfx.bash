# sfx.bash -- sound effects for the game
# sourced by game.bash

# ── Synthesis engine (namespaced with snd_ to avoid collision with maths.bash) ──

samples=${samples:-8000}           # 8kHz sample rate

snd_scale=$((32*1024-1))           # 32767
snd_pi=102941
snd_pi2=205881
snd_pisq=10596760227
snd_pi_2=51470
snd_pi3_2=154411

snd_cosine='(snd_pisq-4*y*y)*snd_scale/(snd_pisq+y*y)'

snd_coscalc=(x snd_pi-x x-snd_pi x-snd_pi2 x-snd_pi2)
snd_cosmult=(1  -1   -1    1     1  )
snd_cos=(
    "y=${snd_coscalc[0]},${snd_cosmult[0]%1}snd_cosine"
    "y=${snd_coscalc[1]},${snd_cosmult[1]%1}snd_cosine"
    "y=${snd_coscalc[2]},${snd_cosmult[2]%1}snd_cosine"
    "y=${snd_coscalc[3]},${snd_cosmult[3]%1}snd_cosine"
    "y=${snd_coscalc[4]},${snd_cosmult[4]%1}snd_cosine"
)

# note frequency table (C0-B7)
declare -A snd_notes=(
[c0]=535792    [cs0]=567652    [d0]=601407    [ds0]=637168    [e0]=675056    [f0]=715197    [fs0]=757725    [g0]=802782     [gs0]=850518     [a0]=901092     [as0]=954674     [b0]=1011442
[c1]=1071585   [cs1]=1135305   [d1]=1202814   [ds1]=1274337   [e1]=1350113   [f1]=1430395   [fs1]=1515450   [g1]=1605564    [gs1]=1701036    [a1]=1802185    [as1]=1909348    [b1]=2022884
[c2]=2143171   [cs2]=2270610   [d2]=2405628   [ds2]=2548674   [e2]=2700226   [f2]=2860790   [fs2]=3030901   [g2]=3211128    [gs2]=3402072    [a2]=3604370    [as2]=3818696    [b2]=4045768
[c3]=4286342   [cs3]=4541221   [d3]=4811256   [ds3]=5097348   [e3]=5400453   [f3]=5721580   [fs3]=6061803   [g3]=6422257    [gs3]=6804144    [a3]=7208740    [as3]=7637393    [b3]=8091537
[c4]=8572684   [cs4]=9082443   [d4]=9622513   [ds4]=10194697  [e4]=10800906  [f4]=11443161  [fs4]=12123607  [g4]=12844514   [gs4]=13608289   [a4]=14417480   [as4]=15274787   [b4]=16183074
[c5]=17145369  [cs5]=18164886  [d5]=19245026  [ds5]=20389395  [e5]=21601812  [f5]=22886322  [fs5]=24247214  [g5]=25689028   [gs5]=27216578   [a5]=28834960   [as5]=30549575   [b5]=32366148
[c6]=34290739  [cs6]=36329773  [d6]=38490053  [ds6]=40778791  [e6]=43203624  [f6]=45772645  [fs6]=48494428  [g6]=51378057   [gs6]=54433156   [a6]=57669920   [as6]=61099151   [b6]=64732296
[c7]=68581479  [cs7]=72659546  [d7]=76980107  [ds7]=81557583  [e7]=86407249  [f7]=91545291  [fs7]=96988857  [g7]=102756115  [gs7]=108866312  [a7]=115339840  [as7]=122198303  [b7]=129464593
)

# binary lookup table for 16-bit PCM encoding
snd_umax=$((64*1024))
declare -A snd_binary
for ((snd_i=0; snd_i<snd_umax; snd_i++)); do
    printf -v snd_tmp '\\x%02x\\x%02x' "$((snd_i&0xff))" "$((snd_i>>8))"
    snd_binary[$snd_i]=$snd_tmp snd_binary[$((snd_i-snd_umax))]=$snd_tmp
done

# default ADSR envelope (attack decay sustain% release, in ms ms % ms)
snd_adsr=(18 100 17 10)

_snd_calc_envelope() {
    ((
        snd_attack   = samples*snd_adsr[0]/1000,
        snd_decay    = samples*snd_adsr[1]/1000,
        snd_sustain  = snd_scale*snd_adsr[2]/100,
        snd_release  = samples*snd_adsr[3]/1000,
        snd_attack_e = snd_decay_s = snd_attack,
        snd_decay_e  = snd_sustain_s = snd_decay + snd_attack_e,
        snd_decrease = snd_sustain - snd_scale,
        snd_ssamples = samples * snd_scale
    ))
}
_snd_calc_envelope

snd_envelope='
    j < snd_attack_e  ? j*snd_scale/snd_attack                    :
    j < snd_decay_e   ? snd_scale+(j-snd_attack_e)*snd_decrease/snd_decay :
    j < release_s ? snd_sustain                               :
                    snd_sustain-(j-release_s)*snd_sustain/snd_release
'
snd_envelope=${snd_envelope//[[:space:]]}

# harmonics
snd_hnum=${snd_hnum:-4}
snd_harmonics="sample+=snd_cos[(x=(freq*snd_pi2*t/snd_ssamples)%snd_pi2)/snd_pi_2]"
for ((snd_hi=2; snd_hi<=snd_hnum; snd_hi++)); do
    snd_harmonics+=",sample+=snd_cos[(x=($snd_hi*freq*snd_pi2*t/snd_ssamples)%snd_pi2)/snd_pi_2]/$((2**(snd_hi-1)))"
done

# ── Generators (output raw PCM bytes to stdout) ──

# snd_generate <duration_ms> <freq1> [freq2 ...]
snd_generate() {
    local duration_ms=$1; shift
    local -a freqs=("$@")
    local notel=$((samples * duration_ms / 1000))
    local release_s=$((notel - snd_release))
    local t=0 j sample freq x

    for ((j=0; j<notel; j++, t++)); do
        sample=0
        for freq in "${freqs[@]}"; do
            ((snd_harmonics))
        done
        printf %b "${snd_binary[$((sample * snd_envelope / snd_scale / 10))]}"
    done
}

# snd_generate_sweep <duration_ms> <start_freq> <end_freq>
snd_generate_sweep() {
    local duration_ms=$1 start_freq=$2 end_freq=$3
    local notel=$((samples * duration_ms / 1000))
    local release_s=$((notel - snd_release))
    local t=0 j sample freq x
    local freq_range=$((end_freq - start_freq))

    for ((j=0; j<notel; j++, t++)); do
        sample=0
        (( freq = start_freq + freq_range * j / notel ))
        ((snd_harmonics))
        printf %b "${snd_binary[$((sample * snd_envelope / snd_scale / 10))]}"
    done
}

# snd_generate_noise <duration_ms> [lfsr_seed]
snd_generate_noise() {
    local duration_ms=$1
    local lfsr=${2:-0xACE1}
    local notel=$((samples * duration_ms / 1000))
    local release_s=$((notel - snd_release))
    local t=0 j sample bit x

    for ((j=0; j<notel; j++, t++)); do
        (( bit = (lfsr ^ (lfsr >> 2) ^ (lfsr >> 3) ^ (lfsr >> 5)) & 1 ))
        (( lfsr = (lfsr >> 1) | (bit << 15) ))
        (( sample = (lfsr & 0xFFFF) - 32768 ))
        (( sample = sample * snd_scale / 32768 ))
        printf %b "${snd_binary[$((sample * snd_envelope / snd_scale / 10))]}"
    done
}

# ── Audio backend detection ──

_sfx_backend=
if [[ -z $MUTE ]]; then
    if command -v mpv &>/dev/null; then
        _sfx_backend=mpv
    elif command -v ffplay &>/dev/null; then
        _sfx_backend=ffplay
    elif command -v aplay &>/dev/null; then
        _sfx_backend=aplay
    else
        _sfx_backend=none
    fi
fi

# play a pre-generated PCM file through the audio backend
# $1 = path to raw PCM file
_sfx_play_file() {
    case $_sfx_backend in
        mpv)    mpv --no-video \
                    --demuxer=rawaudio \
                    --demuxer=rawaudio-format=s16le \
                    --demuxer=rawaudio-rate="$samples" \
                    --demuxer=rawaudio-channels=1 \
                    --no-terminal "$1" 2>/dev/null ;;
        ffplay) ffplay \
                    -v -8 -nodisp -nostats -hide_banner -autoexit \
                    -f s16le -ar "$samples" -ch_layout mono "$1" 2>/dev/null ;;
        aplay)  aplay -f S16_LE -r "$samples" "$1" 2>/dev/null ;;
        none)   ;;
    esac
}

# ── Sound effect cache (temp files) and playback ──

declare -A _sfx_files    # name -> temp file path
declare -A _sfx_cooldown # name -> earliest frame allowed to re-trigger
_sfx_tmpdir=

_sfx_cleanup() {
    [[ $_sfx_tmpdir ]] && rm -rf "$_sfx_tmpdir"
}
trap _sfx_cleanup EXIT

sfx() {
    [[ $MUTE || $_sfx_backend == none || $_sfx_backend == '' ]] && return 0

    local name=$1
    local cooldown=${2:-0}

    # cooldown check: prevent re-triggering too frequently
    if ((cooldown > 0)); then
        (( FRAME < _sfx_cooldown[$name] )) && return 0
        (( _sfx_cooldown[$name] = FRAME + cooldown ))
    fi

    local file="${_sfx_files[$name]}"
    [[ -f $file ]] || return 0

    # non-blocking: fork into background
    _sfx_play_file "$file" &
}

# synchronous quit sound (blocks until finished)
sfx_quit() {
    [[ $MUTE || $_sfx_backend == none || $_sfx_backend == '' ]] && return 0
    local file="${_sfx_files[quit]}"
    [[ -f $file ]] || return 0
    _sfx_play_file "$file"
}

# ── Pre-generate all sound effects at startup ──

_sfx_init() {
    [[ $MUTE || $_sfx_backend == none || $_sfx_backend == '' ]] && return 0

    _sfx_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/bash-sfx.XXXXXX")
    [[ $_sfx_tmpdir ]] || return 0

    # collision: short noise burst, 25ms — concrete wall thud
    snd_generate_noise 25 > "$_sfx_tmpdir/collision.pcm"
    _sfx_files[collision]=$_sfx_tmpdir/collision.pcm

    # game start: C major chord (C4+E4+G4), 150ms — bright welcome chime
    snd_generate 150 "${snd_notes[c4]}" "${snd_notes[e4]}" "${snd_notes[g4]}" > "$_sfx_tmpdir/gamestart.pcm"
    _sfx_files[gamestart]=$_sfx_tmpdir/gamestart.pcm

    # footstep: very short noise, 8ms with custom quiet envelope
    local saved_adsr=("${snd_adsr[@]}")
    snd_adsr=(1 2 10 2)
    _snd_calc_envelope
    snd_generate_noise 8 > "$_sfx_tmpdir/footstep.pcm"
    _sfx_files[footstep]=$_sfx_tmpdir/footstep.pcm
    snd_adsr=("${saved_adsr[@]}")
    _snd_calc_envelope

    # fov zoom in: ascending sweep ~400Hz -> ~800Hz, 40ms
    snd_generate_sweep 40 "${snd_notes[a4]}" "${snd_notes[a5]}" > "$_sfx_tmpdir/fov_in.pcm"
    _sfx_files[fov_in]=$_sfx_tmpdir/fov_in.pcm

    # fov zoom out: descending sweep ~800Hz -> ~400Hz, 40ms
    snd_generate_sweep 40 "${snd_notes[a5]}" "${snd_notes[a4]}" > "$_sfx_tmpdir/fov_out.pcm"
    _sfx_files[fov_out]=$_sfx_tmpdir/fov_out.pcm

    # quit: G4 tone, 100ms
    snd_generate 100 "${snd_notes[g4]}" > "$_sfx_tmpdir/quit.pcm"
    _sfx_files[quit]=$_sfx_tmpdir/quit.pcm
}

_sfx_init
