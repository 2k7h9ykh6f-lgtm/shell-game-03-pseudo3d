aliasing () {
    # $1 cond
    # $2 alias name
    # $3 optional 2nd alias (otherwise, no$2)

    local -i cond=$1
    ((cond==0)) &&
        BASH_ALIASES[$2]=    BASH_ALIASES[${3-no$2}]='#' ||
        BASH_ALIASES[$2]='#' BASH_ALIASES[${3-no$2}]=
    ((cond==0))
}

dumpstats() {
    # see tests in https://gist.github.com/izabera/3d1e5dfabbe80b3f5f2e50ec6f56eadb
    END=${EPOCHREALTIME/.}
    title () { printf '\e[38;5;201m==== %s ====\e[m\n' "$@"; }
    info () {
        local -A colours=([true]=46 [false]=196)
        printf '%s: \e[38;5;%sm%s\e[m\n' "$1" "${colours[${2:-0}]-33}" "$2"
    }
    note () { echo "note: $*"; }

    title 'frame stats'
    info 'final resolution' "${cols}x$((rows*2))"
    info 'fps target' "$FPS"

    info 'renderers' "${NTHR-1}"
    tf=(false true)
    [[ $UNBUFFERED ]]
    info 'unbuffered' "${tf[!$?]}"
    [[ $MINIMAP ]]
    info 'minimap' "${tf[!$?]}"

    info 'terminated after frame' "$FRAME"

    if ((BENCHMARK)); then
        info 'time per frame' "$(((END-START)/FRAME))µs"
    else
        info 'skipped frames' "$TOTALSKIPPED ($((TOTALSKIPPED*100/FRAME))%)"
    fi
    if ((${#frametimes[@]})); then
        # basic counting sort
        sorted=() sum=0 counted=()
        for n in "${!frametimes[@]}"; do counted[n]=${frametimes[$n]}; done
        for n in "${!counted[@]}"; do
            for ((i=0;i<counted[n];i++)) do
                sorted+=("$n")
                ((sum+=n))
            done
        done

        min=${sorted[0]} max=${sorted[-1]}
        framecount=${#sorted[@]}
        mean=$((sum/framecount))
        sum=0 sqdiffs=()
        for i in "${!sorted[@]}"; do
            ((sum+=(sqdiffs[i]=(sorted[i]-mean)**2)))
        done
        variance=$((sum/framecount))

        # newton's method
        x=$((variance/2))
        while ((x)); do
            ((prev=x,x=(x+variance/x)/2,x==prev)) && break
        done
        stddev=$x

        info 'fastest frame' "$min"µs
        info 'slowest frame' "$max"µs
        info 'average frame' "$mean"µs
        info '95th %ile' "${sorted[framecount*95/100]}"µs
        info 'std dev' "$stddev"µs
        info 'your bash can render' "$((1000000/max))-$((1000000/mean))fps"
        note 'times are collected after drawing to the terminal,' \
             'but they do not accurately account for any slowness induced by it'
    fi

    title 'shell info'
    info 'bash path' "$BASH"
    info 'bash version' "$BASH_VERSION"
    info 'preload' "${LD_PRELOAD:-<empty>}"

    affinity=$(taskset -pc "$$" 2>/dev/null)
    affinity=${affinity##*: }
    info 'cpu affinity' "${affinity:-unknown}"

    # sometimes useful but they don't really need to be accessed at runtime
    # {
    #     comment=$(readelf -p .comment "$BASH")
    #     cmdline=$(readelf -p .GCC.command.line "$BASH")
    # } 2>/dev/null
    # info '.comment' "${comment:-empty}"
    # info '.GCC.command.line' "${cmdline:-empty}"

    title 'terminal info'
    info '$TERM' "$TERM"
    info '$COLORTERM' "$COLORTERM"
    if [[ $DISPLAY ]] && type xprop &>/dev/null; then
        IFS=' ' read -r _ _ _ _ self _ < <(xprop -root _NET_ACTIVE_WINDOW)
        IFS='"' read -r _ _ _ class _ < <(xprop -id "$self" WM_CLASS)
    else
        class=unknown
    fi
    info 'wm class' "$class"

    colours=(256 truecolor)

    info colours "${colours[truecolor]}"
    info 'kitty keyboard proto support' "${tf[kitty]}"
    info 'synchronised output support' "${tf[sync]}"

    #      r      |     g     |     b     | rdx | gdx | bdx
    # ------------+-----------+-----------+-----+-----+----
    # max         | 0->max    | 0         |  0  |  1  |  0
    # max->0      |    max    | 0         | -1  |  0  |  0
    #      0      |    max    | 0->max    |  0  |  0  |  1
    #      0      |    max->0 |    max    |  0  | -1  |  0
    #      0->max |         0 |    max    |  1  |  0  |  0
    #         max |         0 |    max->0 |  0  |  0  | -1

    # walk around an rgb cube on the edges that don't include black or white
    walkcube () {
        local max=$(($1-1)) fmt=$2
        local rdx=4 gdx=2 bdx=0
        local r=max g=0 b=0
        local i j

        for (( i = 0; i < 6; i++ )) do
            for (( j = 0; j < max; j++ )) do
                printf -v 'hues[i*max+j]' "$fmt" \
                    "$(( r += (rdx%6==2)-(rdx%6==5) ))" \
                    "$(( g += (gdx%6==2)-(gdx%6==5) ))" \
                    "$(( b += (bdx%6==2)-(bdx%6==5) ))"
            done
            (( rdx = (rdx+1) % 6, gdx = (gdx+1) % 6, bdx = (bdx+1) % 6 ))
        done
    }

    declare -ai hues
    walkcube 6 '16 + %d*6*6 + %d*6 + %d'

    printf '256 colour test: '
    printf '\e[38;5;%s;48;5;%sm▌' "${hues[@]}"
    printf '\e[m\n'

    unset hues
    walkcube 256 '%d;%d;%d'

    h=${#hues[@]}
    for (( i = 0; i < h && h>cols; i++ )) do
        (( i % (h/cols) )) && unset 'hues[i]'
    done

    printf '24bit colour test: '
    printf '\e[38;2;%s;48;2;%sm▌' "${hues[@]}"
    printf '\e[m\n'
    ((truecolor)) || note 'if the 24bit colour test looks ok, set COLORTERM=truecolor'
}

drawmsgs () {
    set -- "${msgs[@]:(${#msgs[@]}>5?-5:0):5}"
    printf '\e[m\e[%s;2H' "$((rows+2-$#))"
    printf "%.$((cols+5))s\r\e[B\e[C" "$@"
}
declare -A infos
drawinfo () {
    ((${#infos[@]}))||return
    printf '\e[1;1H\e[m'
    printf '%s=%s\t' "${infos[@]@k}"
}
drawborder () {
    local i
    printf '\e[H'
    printf '+%s+\e[K\r\e[B' "${hspaces// /-}"
    for ((i=1;i<=rows;i++)) do
        printf '|\e[%sC|%d\e[K\r\e[B' "$cols" "$i"
    done
    printf '+%s+\e[K\r\e[B' "${hspaces// /-}"
}

drawdebug() {
    local -i d_mapH d_startR d_startC d_r d_c d_cell d_or d_idx
    local d_pr d_pc d_or2 d_cell2 d_fgR d_fgG d_fgB d_bgR d_bgG d_bgB

    # half-block rendering: 2 map rows per terminal row
    ((d_mapH=(maph+1)/2))
    ((d_startR=rows-d_mapH-3, d_startR<1 && (d_startR=1)))
    ((d_startC=cols-mapw-1, d_startC<1 && (d_startC=1)))

    # player grid cell (mx=column, my=row in the map array)
    ((d_pr=my/scale, d_pc=mx/scale))

    # 3x3 collision neighbourhood
    declare -A d_coll=()
    for ((d_dr=-1; d_dr<=1; d_dr++)); do
        for ((d_dc=-1; d_dc<=1; d_dc++)); do
            ((d_r=d_pr+d_dr, d_c=d_pc+d_dc))
            ((d_r>=0 && d_r<maph && d_c>=0 && d_c<mapw)) &&
                d_coll["$d_r,$d_c"]=1
        done
    done

    # direction ray via sampling (3 cells, 8 sub-samples each)
    # sin affects row (my direction), cos affects column (mx direction)
    declare -A d_dir=()
    for ((d_s=1; d_s<=24; d_s++)); do
        ((d_r=(my+sin*d_s/8)/scale, d_c=(mx+cos*d_s/8)/scale))
        ((d_r<0||d_r>=maph||d_c<0||d_c>=mapw)) && break
        d_dir["$d_r,$d_c"]=1
        ((map[d_r*mapw+d_c])) && break
    done

    # render map using half-block cells (two map rows → one terminal row)
    for ((d_or=0; d_or<maph; d_or+=2)) do
        printf '\e[%d;%dH' "$((d_startR+d_or/2))" "$d_startC"
        for ((d_c=0; d_c<mapw; d_c++)) do
            # upper pixel = map row d_or, lower pixel = map row d_or+1
            ((d_idx=d_or*mapw+d_c, d_cell=map[d_idx],
              d_or2=d_or+1, d_cell2=(d_or2<maph?map[d_or2*mapw+d_c]:0)))

            # set fg (upper pixel) colour
            if ((d_cell)); then
                ((d_fgR=wallsr[d_cell], d_fgG=wallsg[d_cell], d_fgB=wallsb[d_cell]))
            else
                ((d_fgR=20, d_fgG=20, d_fgB=25))
            fi
            # set bg (lower pixel) colour
            if ((d_or2<maph && d_cell2)); then
                ((d_bgR=wallsr[d_cell2], d_bgG=wallsg[d_cell2], d_bgB=wallsb[d_cell2]))
            else
                ((d_bgR=20, d_bgG=20, d_bgB=25))
            fi

            # overlays: player > direction > collision neighbourhood
            if ((d_pr==d_or && d_pc==d_c)); then
                ((d_fgR=0, d_fgG=255, d_fgB=50))
            elif [[ ${d_dir["$d_or,$d_c"]} ]]; then
                ((d_fgR=255, d_fgG=220, d_fgB=0))
            elif [[ ${d_coll["$d_or,$d_c"]} && !d_cell ]]; then
                ((d_fgR=90, d_fgG=25, d_fgB=25))
            fi
            if ((d_or2<maph)); then
                if ((d_pr==d_or2 && d_pc==d_c)); then
                    ((d_bgR=0, d_bgG=255, d_bgB=50))
                elif [[ ${d_dir["$d_or2,$d_c"]} ]]; then
                    ((d_bgR=255, d_bgG=220, d_bgB=0))
                elif [[ ${d_coll["$d_or2,$d_c"]} && !d_cell2 ]]; then
                    ((d_bgR=90, d_bgG=25, d_bgB=25))
                fi
            fi

            printf '\e[38;2;%d;%d;%d;48;2;%d;%d;%dm▀' \
                "$d_fgR" "$d_fgG" "$d_fgB" "$d_bgR" "$d_bgG" "$d_bgB"
        done
    done

    # bottom border
    printf '\e[%d;%dH\e[m' "$((d_startR+d_mapH))" "$d_startC"
    printf '─%.0s' $(seq 1 "$mapw")

    # info line below the map
    printf '\e[m\e[%d;%dH\e[38;2;180;180;180mpos(%d,%d) cell(%d,%d) angle=%d coll[±1]' \
        "$((d_startR+d_mapH+1))" "$d_startC" \
        "$((mx/scale))" "$((my/scale))" "$d_pr" "$d_pc" "$((angle))"
}

infos=()
msg= msgs=()
error() { printf -v 'msgs[msg++]' '\e[31m%(%T)T [ERROR]: %s\e[m' -1 "$1"; }
warn () { printf -v 'msgs[msg++]' '\e[33m%(%T)T [WARNING]: %s\e[m' -1 "$1"; }
info () { printf -v 'msgs[msg++]' '\e[34m%(%T)T [INFO]: %s\e[m' -1 "$1"; }
