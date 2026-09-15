#!/usr/bin/env sh

LOBSTER_VERSION="5.0.0"

### General variables ###
lobster_editor="${VISUAL:-$EDITOR}"
# some macOS setups (sandboxes, restricted profiles) hand out a
# read-only $TMPDIR/tmp; fall back to a dir we can actually write to.
[ -w "${TMPDIR:-/tmp}" ] || TMPDIR=$(mktemp -d 2>/dev/null || echo "$HOME/.cache/lobster-tmp")
mkdir -p "${TMPDIR:-/tmp}"
tmp_dir="${TMPDIR:-/tmp}/lobster"
lr_tmp="$tmp_dir/lobster-resolve"
mkdir -p "$lr_tmp"
lobster_socket="${TMPDIR:-/tmp}/lobster.sock"          # used by mpv, see play()
lobster_logfile="${TMPDIR:-/tmp}/lobster.log"          # only written to in --debug mode
applications="$HOME/.local/share/applications/lobster" # external-menu (rofi) icon entries
mkdir -p "$tmp_dir"

# Literal newline, used for pattern matching against multi-line command output.
nl='
'
# Not arbitrary: these match rofi's kb-custom-1 / kb-custom-2 exit codes, and
# fzf's back/forward keybinds are mapped onto them below.
BACK_CODE=10
FORWARD_CODE=11
DELETE_CODE=12

### Notifications ###
command -v notify-send >/dev/null 2>&1 && notify_send_available="true" || notify_send_available="false"
command -v osascript >/dev/null 2>&1 && osascript_available="true" || osascript_available="false"
# notify [message] [timeout_ms] [icon] [title]
# In fzf mode this just prints a colored status line. In rofi mode (or when a
# desktop notification daemon is available) it also fires a notify-send popup.
notify() {
    [ "$json_output" = "true" ] && return
    if [ "$use_external_menu" = "false" ] || [ -z "$use_external_menu" ]; then
        if [ -z "$4" ]; then
            printf "\33[2K\r\033[1;34m%s\n\033[0m" "$1"
        else
            printf "\33[2K\r\033[1;34m%s - %s\n\033[0m" "$1" "$4"
        fi
        return
    fi
    timeout="${2:-3000}"
    if [ "$notify_send_available" = "true" ]; then
        if [ -z "$3" ]; then
            notify-send "$1" "$4" -t "$timeout" -h string:x-dunst-stack-tag:vol
        else
            notify-send "$1" "$4" -t "$timeout" -i "$3" -h string:x-dunst-stack-tag:vol
        fi
    elif [ "$osascript_available" = "true" ]; then
        osascript -e "display notification \"$4\" with title \"$1\""
    fi
}

# desktop_notify [title] [timeout_ms] [body] - an actual desktop popup
# regardless of fzf/rofi mode, for things that should surface even when the
# terminal is behind other windows (download finished, etc.). Falls back to
# the same colored line notify() uses when no notifier exists.
desktop_notify() {
    [ "$json_output" = "true" ] && return
    lr_dn_timeout="${2:-5000}"
    if [ "$notify_send_available" = "true" ]; then
        notify-send "$1" "$3" -t "$lr_dn_timeout"
    elif [ "$osascript_available" = "true" ]; then
        osascript -e "display notification \"$3\" with title \"$1\""
    else
        printf '\33[2K\r\033[1;34m%s - %s\n\033[0m' "$1" "$3"
    fi
}

# clipboard_copy <text> - copies to the system clipboard via whatever
# tool the platform has (Wayland, X11, macOS, Windows, Android). Prints the
# text instead of silently dropping it when none of them exist.
clipboard_copy() {
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null 2>&1; then
        printf '%s' "$1" | wl-copy
    elif [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then
        printf '%s' "$1" | xclip -selection clipboard
    elif [ -n "${DISPLAY:-}" ] && command -v xsel >/dev/null 2>&1; then
        printf '%s' "$1" | xsel --clipboard --input
    elif command -v pbcopy >/dev/null 2>&1; then
        printf '%s' "$1" | pbcopy
    elif command -v clip.exe >/dev/null 2>&1; then
        printf '%s' "$1" | clip.exe
    elif command -v termux-clipboard-set >/dev/null 2>&1; then
        printf '%s' "$1" | termux-clipboard-set
    else
        printf '%s\n' "$1"
    fi
}

# status <backend> - an animated "Resolving via <backend>" line on stderr, so
# a slow resolve never leaves a blank terminal (stderr keeps --json's stdout
# clean). Silent in rofi mode and json mode.
status() {
    [ "$json_output" = "true" ] && return
    [ "$use_external_menu" = "true" ] && return
    # A batch download draws its own live table and owns the terminal; this
    # spinner writes \r-terminated lines to the same stderr, so leaving it
    # on would have it scribbling through the block being redrawn in place.
    [ "$lr_no_status" = "true" ] && return
    clear_status
    lr_status_msg=$1
    printf '\033[?25l' >&2
    (
        set -- ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏
        while :; do
            for frame; do
                printf '\33[2K\r\033[36m%s\033[0m \033[2mResolving via\033[0m \033[1;36m%s\033[0m' "$frame" "$lr_status_msg" >&2
                sleep 0.08
            done
        done
    ) &
    lr_spinner_pid=$!
}

# status_note <text> - a single static (non-spinning) dim line, for asides
# where nothing is actually loading (a skip notice, a between-step message).
status_note() {
    [ "$json_output" = "true" ] && return
    [ "$use_external_menu" = "true" ] && return
    [ "$lr_no_status" = "true" ] && return
    clear_status
    printf '\33[2K\r\033[2m%s\033[0m' "$1" >&2
}

clear_status() {
    if [ -n "$lr_spinner_pid" ]; then
        kill "$lr_spinner_pid" 2>/dev/null
        wait "$lr_spinner_pid" 2>/dev/null
        lr_spinner_pid=""
    fi
    [ "$json_output" = "true" ] && return
    [ "$use_external_menu" = "true" ] && return
    # Same reason as status(): don't clear a line or un-hide the cursor out
    # from under the batch renderer.
    [ "$lr_no_status" = "true" ] && return
    printf '\33[2K\r\033[?25h' >&2
}

### Discord rich presence (optional, experimental) ###
presence_client_id="1239340948048187472"
# shellcheck disable=SC2154
discord_ipc="${XDG_RUNTIME_DIR}/discord-ipc-0"
handshook="$tmp_dir/handshook"
ipclog="$tmp_dir/ipclog"
presence="$tmp_dir/presence"
small_image="https://www.pngarts.com/files/9/Juvenile-American-Lobster-PNG-Transparent-Image.png"

### OS-specific variables ###
separator=':'             # subtitle-list separator passed to mpv
path_thing="\\"           # escape prefix for ':' inside Windows paths
ueberzugpp_tmp_dir="/tmp" # ueberzugpp only honors $TMPDIR on Darwin
case "$(uname -s)" in
    MINGW* | *Msys) separator=';' && path_thing='' ;;
    *arwin) ueberzugpp_tmp_dir="${TMPDIR:-/tmp}" ;;
    *) : ;;
esac

### Cleanup ###
rpc_cleanup() {
    pkill -f "nc -U $discord_ipc" >/dev/null 2>&1
    pkill -f "tail -f $presence" >/dev/null 2>&1
    rm -f "$handshook" "$ipclog" "$presence"
}

cleanup() {
    rc=$?
    # Stop the traps from re-firing off the kill below.
    trap '' INT TERM
    printf '\033[?25h' >&2 # in case a Ctrl-C landed mid-spinner
    [ "$remove_tmp_lobster" = "true" ] && rm -rf "$tmp_dir"
    if [ "$image_preview" = "true" ] && [ "$use_external_menu" = "false" ] && [ "$use_ueberzugpp" = "true" ]; then
        # Only the instance we started, via the pid file image_preview_fzf
        # asked ueberzugpp to write. `killall ueberzugpp` would also take down
        # another session's viewer, and isn't POSIX to begin with.
        ub_pid=$(cat "$tmp_dir.$$" 2>/dev/null)
        [ -n "$ub_pid" ] && kill "$ub_pid" 2>/dev/null
        rm -f "$tmp_dir.$$" "$ueberzugpp_tmp_dir/ueberzugpp-$ub_pid.socket"
    fi
    # Take the whole process group down, not just ourselves: backgrounded
    # curl/node/ffprobe otherwise outlive the trap and the calling shell keeps
    # waiting on the group, which looks like a hung terminal.
    # See docs/implementation-notes.md.
    kill -TERM -- "-$$" 2>/dev/null
    exit "$rc"
}
trap cleanup EXIT INT TERM
# Quit from anywhere, including inside a $(command substitution). fzf reads
# Ctrl-C as a raw keypress rather than raising SIGINT, so a plain `exit` in a
# menu only kills the subshell and the caller happily carries on with an empty
# selection (and tries to play it). Signal the real script instead; $$ is the
# parent pid even in a subshell, and the TERM trap above does the cleanup.
quit_now() {
    kill -TERM "$$" 2>/dev/null
    exit 0
}

### Help ###
usage() {
    printf "
  Usage: %s [options] [query]
  If a query is provided, it will be used to search for a Movie/TV Show.
  Metadata comes from themoviedb.org - no account or API key needed.

  Options:
    -c, --continue
      Continue watching from history
    --genre <name> [movie|tv]
      Browse titles by genre (defaults to movie)
    --last
      Resume the most recently watched entry directly
    --binge
      Auto-play the next episode, no menu, no wait
    --clear-history
      Erase the watch history file
    --config-regenerate
      Write a fresh commented config template (old one kept as .bak)
    -d, --download [path]
      Download the selected movie/episode (defaults to the current directory)
    --discord, --discord-presence, --rpc, --presence
      Enable Discord rich presence (Linux only, experimental)
    -e, --edit
      Open the config file in \$lobster_editor (\$EDITOR by default); a
      commented template listing every option is created on first run
    -h, --help
      Show this help message and exit
    -i, --image-preview
      Show cover art during selection (requires chafa, or optionally ueberzugpp)
    -j, --json
      Print selected title's metadata plus all resolved video/subtitle sources as JSON
    -l, --language [language]
      Subtitle language passed to resolve_stream (defaults to english)
    --rofi, --external-menu
      Use rofi instead of fzf
    -n, --no-subs
      Disable subtitles
    --provider [videasy|rivestream|cinezo|vidlove|penguplay|aiostreams]
      Use only this source backend instead of trying them all in order
      (config: provider_order sets the order they're tried in)
    -q, --quality [quality]
      Preferred quality, passed to resolve_stream (defaults to 1080)
    -r, --recent [movie|tv]
      Browse currently-airing/now-playing titles (defaults to movie)
    -s, --syncplay
      Use Syncplay to watch with friends
    -t, --trending
      Browse this week's trending titles
    -T, --top-rated [movie|tv]
      Browse top-rated titles (defaults to movie)
    --year <year> [movie|tv]
      Browse titles from a specific year (defaults to movie)
    -u, -U, --update
      Update the script
    -v, -V, --version
      Show the version of the script
    -x, --debug
      Enable debug mode (logs to \$TMPDIR/lobster.log)

  Note:
    Every option can also be set in the config file; a command-line flag
    always overrides the config file's value.

  Some example usages:
    ${0##*/} -i a silent voice --rofi
    ${0##*/} -l spanish -q 720 fight club -i -d
    ${0##*/} -l spanish blade runner --json

" "${0##*/}"
}

### Dependency check ###
dep_check() {
    for dep; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            notify "Error" "5000" "" "\"$dep\" is required but was not found, please install it"
            exit 1
        fi
    done
}

### Configuration ###
# Written to $config_file on first run so there's always something to open
# with -e. Every line is commented out on purpose: the defaults below in
# configuration() stay the single source of truth, and a template that sets
# nothing can never fight a future default change. Adding an option here
# later is therefore always backwards compatible - existing users keep their
# file, new users get the new line. Only append; never repurpose a name.
write_default_config() {
    cat >"$1" <<'EOF'
# lobster config - plain POSIX shell, sourced before flags are parsed, so a
# command-line flag always wins over anything set here. Uncomment a line to
# change it; the value shown is the default. Full docs:
# https://github.com/justchokingaround/lobster#config

### playback
#player=mpv                       # mpv, vlc, iina, celluloid, syncplay, or any command taking a url
#quality=1080                     # 1080, 720, 2160/4k ...
#subs_language=english
#audio_language=english
#blocked_audio_languages=         # never pick these, e.g. "hindi"
#max_subs=5                       # subtitle tracks handed to the player (0 = all)
#max_audio_tracks=5               # audio candidates probed before picking (0 = all)
#no_subs=false
#binge=false                      # auto-play the next episode, no menu

### providers
#provider=                        # pin one backend: videasy, rivestream, cinezo, vidlove, penguplay, aiostreams
# order backends are tried in, best first; unknown names are skipped, so
# removing/reordering names here is always safe.
# best source: aiostreams if you have debrid/can torrent, penguplay otherwise.
# the scraped ones (videasy/rivestream/cinezo/vidlove) are just fallbacks.
#provider_order="aiostreams penguplay videasy rivestream cinezo vidlove"
#penguplay_url=                   # stremio addon manifest url
#aiostreams_url=                  # stremio addon manifest url

### history
#history=true                     # powers -c / --last
#histfile="${XDG_DATA_HOME:-$HOME/.local/share}/lobster/lobster_history.txt"
#lr_continue_back=exit            # what esc does in the continue list: exit or menu

### downloads
#download_dir="$PWD"
#downloader=ffmpeg                # aria2c to prefer it for plain direct links
#download_concurrency=8           # episodes at once in a batch download
#download_pace=1                  # minimum seconds between episode starts

### interface
#live_search=true                 # search-as-you-type in fzf
#use_external_menu=false          # rofi instead of fzf
#image_preview=false              # cover art in the picker (needs chafa or ueberzugpp)
#images_cache_dir=                # where posters are kept, defaults to <data dir>/posters
#preview_window_size=right:70%:wrap
#use_ueberzugpp=false
#ueberzug_x=10
#ueberzug_y=3
#ueberzug_max_width=              # defaults to half the terminal height
#ueberzug_max_height=
#ueberzug_output=                 # x11, wayland, ...
#image_config_path=               # rofi theme for the image picker
#rofi_prompt_config=              # rofi theme for the search prompt

### misc
#discord_presence=false           # discord rich presence (linux, experimental)
#watchlater_dir=                  # mpv resume data (auto-detected)
#remove_tmp_lobster=true          # wipe the temp dir on exit
#json_output=false                # same as -j
#debug=false                      # same as -x
#lobster_editor=                  # editor for -e, defaults to $VISUAL / $EDITOR

# You can also redefine two functions here:
#   resolve_stream()    - your own provider, see the README's providers section
#   custom_downloader() - your own downloader, see the README's downloads section
EOF
}

# Sources the user's config file (a plain shell script) and fills in any
# option it didn't set. Called once, before argument parsing, so command-line
# flags can still override whatever the config file chose.
configuration() {
    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/lobster"
    data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/lobster"
    mkdir -p "$config_dir" "$data_dir"
    config_file="$config_dir/lobster_config.sh"
    [ -f "$config_file" ] || write_default_config "$config_file" 2>/dev/null
    # shellcheck disable=SC1090
    [ -f "$config_file" ] && . "$config_file"

    : "${player:=mpv}"
    : "${download_dir:=$PWD}"
    : "${subs_language:=english}"
    # Remembered before defaulting: player_command only passes --alang when
    # the user really chose a language (see there).
    [ -n "${audio_language:-}" ] && audio_language_set="true"
    : "${audio_language:=english}"
    : "${audio_language_set:=false}"
    : "${blocked_audio_languages:=}"
    # Best-first backend order. Names not in the known set are skipped with a
    # warning rather than being an error, so a config naming a retired or
    # not-yet-existing backend keeps working across upgrades. $provider /
    # --provider still pins a single one and ignores this.
    : "${provider_order:=aiostreams penguplay videasy rivestream cinezo vidlove}"
    # Caps on how much gets collected per stream. Subtitles and audio
    # candidates both arrive as long lists (a dozen+ mirrors of the same
    # language is normal); every extra sub is another URL mpv downloads at
    # startup and every extra audio candidate is another ffprobe, so the tail
    # of those lists costs seconds and buys nothing. 0 means no cap.
    : "${max_subs:=5}"
    : "${max_audio_tracks:=5}"
    # Posters live next to the history, not in $tmp_dir: the temp dir is wiped
    # on exit, and the continue list needs its cover art to survive that.
    : "${images_cache_dir:=$data_dir/posters}"
    mkdir -p "$images_cache_dir"
    : "${histfile:=$data_dir/lobster_history.txt}"
    : "${history:=true}"
    # History is on by default, so say so - once, on first run, on stderr - and
    # never mention it again. The marker file doubles as "this install has been
    # run before".
    if [ "$history" = "true" ] && [ ! -e "$data_dir/.history_notice" ]; then
        : >"$data_dir/.history_notice"
        printf '\033[1;34mlobster keeps watch history in %s so it can resume where you stopped.\n\033[0m\033[2mset history=false in %s to turn it off; --clear-history wipes it. (shown once)\033[0m\n' \
            "${histfile:-$data_dir/lobster_history.txt}" "$config_file" >&2
    fi
    : "${binge:=false}"
    : "${live_search:=true}"
    : "${lr_continue_back:=exit}"
    : "${use_external_menu:=false}"
    : "${image_preview:=false}"
    : "${debug:=false}"
    : "${preview_window_size:=right:70%:wrap}"
    : "${use_ueberzugpp:=false}"
    : "${ueberzug_x:=10}"
    : "${ueberzug_y:=3}"
    : "${ueberzug_max_width:=$(($(tput lines 2>/dev/null || echo 40) / 2))}"
    : "${ueberzug_max_height:=$(($(tput lines 2>/dev/null || echo 40) / 2))}"
    : "${downloader:=ffmpeg}" # or aria2c, for plain (non-HLS) direct links
    # Batch (season/multi-episode) downloads cap how many run at once - a
    # provider CDN happily 4xx's/rate-limits a burst of a dozen simultaneous
    # connections from the same client. Raise it if a provider tolerates
    # more, lower it if one is still complaining at the default. 8 rather
    # than a more timid 4: the providers actually in use here serve a whole
    # batch of simultaneous range requests without complaint, and a typical
    # single episode only pulls ~15-20 MB/s, so fewer than this just leaves
    # the connection idle. Drop it if some other provider starts 4xx-ing.
    : "${download_concurrency:=8}"
    # A concurrency cap alone doesn't help against a real requests-per-
    # window quota (e.g. PenguPlay: ~15 requests per 15s) - that's about
    # cumulative request rate over time, not how many run at once. This is
    # a minimum number of seconds between starting each episode's
    # resolve+download in a batch run, throttling total throughput
    # regardless of concurrency.
    : "${download_pace:=1}"
    : "${remove_tmp_lobster:=true}"
    : "${json_output:=false}"
    : "${discord_presence:=false}"
    : "${penguplay_url:=}"
    : "${aiostreams_url:=}"
    case "$(uname -s)" in
        MINGW* | *Msys)
            if [ -z "$watchlater_dir" ]; then
                # shellcheck disable=SC2154
                case "$(command -v "$player")" in
                    *scoop*) watchlater_dir="$HOMEPATH/scoop/apps/mpv/current/portable_config/watch_later/" ;;
                    *) watchlater_dir="$LOCALAPPDATA/mpv/watch_later" ;;
                esac
            fi
            ;;
        *)
            : "${watchlater_dir:=$tmp_dir/watchlater}"
            mkdir -p "$watchlater_dir"
            ;;
    esac
}

### TMDB ###
# No API key: lobster scrapes www.themoviedb.org's public pages. Every listing
# layout wraps each card in the same `<a class="flex w-full" href="/(movie|tv)
# /ID-slug">` anchor, which is the one stable per-card boundary the parsers
# key off. See docs/implementation-notes.md.
tmdb_ua="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

tmdb_fetch() {
    path="$1"
    shift
    curl -sSL --connect-timeout 10 -m 30 -A "$tmdb_ua" -H "Accept-Language: en-US,en;q=0.9" "$@" "https://www.themoviedb.org${path}"
}
# Decodes the handful of HTML entities that actually show up in TMDB titles.
tmdb_decode() {
    sed -e 's/&amp;/\&/g' -e 's/&quot;/"/g' -e "s/&#39;/'/g" -e "s/&apos;/'/g" -e 's/&lt;/</g' -e 's/&gt;/>/g'
}

# Reads a TMDB page (search results, or a popular/now-playing/airing-today
# grid - see the layout note above) from stdin and emits one row per
# movie/tv card: poster_url \t tmdb_id \t type \t "title (year)". This is
# deliberately the same shape choose_media()/download_thumbnails() have
# always expected, so a single downstream code path handles every listing.
tmdb_extract_media() {
    tab=$(printf '\t')
    tr -d '\n' |
        sed -E 's@<a class="flex w-full"[^>]*href="/(movie|tv)/@\n&@g' |
        sed -nE 's@.*href="/(movie|tv)/([0-9]+)(-[^"]*)?".*src="(https://media\.themoviedb\.org/t/p/[^"]+\.jpg)".*<h2[^>]*>(<span>)?([^<]*).*class="release_date[^"]*">([^<]*)<.*@\4\t\2\t\1\t\6\t\7@p' |
        tmdb_decode |
        # Appends "(year)" when the date field has one, else drops the field.
        # BSD sed won't take \t inside a bracket class, so the tab is passed
        # in as a real character.
        sed -E "s/^(([^$tab]+$tab){3})([^$tab]+)$tab.*([0-9]{4})\$/\1\3 (\4)/ ; s/^(([^$tab]+$tab){3})([^$tab]+)${tab}[^$tab]*\$/\1\3/ ; s/${tab}\$//"
}

tmdb_search() {
    tmdb_fetch "/search" -G --data-urlencode "query=$1" | tmdb_extract_media
}

# fzf --preview payload for choose_media()'s picker: title/genres/rating/
# runtime/overview/cast off the public detail page. Invoked as
# "$0 --tmdb-preview <type> <id> [mode]" (see the entry point at the bottom of
# this file): fzf runs --preview as its own process with no access to this
# script's functions, so re-running the script is the only way to reuse
# tmdb_fetch et al.
tmdb_preview_text() {
    lr_tp_type=$1
    lr_tp_id=$2
    # Layout: empty (one unbroken block), "side" (split at a LOBSTER_SPLIT
    # marker, for the chafa branch), or "overlay:COL:H" (indented and padded to
    # sit beside a kitten-icat poster). See docs/implementation-notes.md.
    lr_tp_mode=$3
    [ -z "$lr_tp_id" ] && return 1

    # Debounce: fzf kills and re-runs this on the next highlight change, so a
    # fast scroll never reaches the network (and never trips TMDB's bot check).
    sleep 0.15

    lr_tp_cache="$tmp_dir/tmdb-preview-cache"
    mkdir -p "$lr_tp_cache"
    # Layout mode is part of the cache key: "side" carries a marker line the
    # plain caller must never be served, and vice versa.
    lr_tp_cache_file="$lr_tp_cache/$lr_tp_type-$lr_tp_id${lr_tp_mode:+-$lr_tp_mode}"
    if [ -s "$lr_tp_cache_file" ]; then
        cat "$lr_tp_cache_file"
    else
        lr_tp_out=$(tp_render "$lr_tp_type" "$lr_tp_id" "$lr_tp_mode")
        rc=$?
        # Only cache a real page - never a blocked/challenge response, so
        # the next highlight retries instead of caching "unavailable" forever.
        [ "$rc" -eq 0 ] && printf '%s' "$lr_tp_out" >"$lr_tp_cache_file"
        printf '%s\n' "$lr_tp_out"
    fi
}
# fzf --preview payload for image_preview_fzf()'s cover-art picker: poster
# (chafa, sized to the real pane via FZF_PREVIEW_COLUMNS/LINES) beside
# title/genres/rating/overview/cast text from tmdb_preview_text. Invoked as
# "$0 --image-preview-cell <cache filename>"; the id/type are parsed back
# out of that filename with the same pattern select_desktop_entry uses to
# parse the final choice (see download_thumbnails for how it's built).
#
# fzf's preview pane is fzf's own renderer reading our stdout line by line,
# not a real terminal, so cursor-addressing escapes sent as their own output
# lines get eaten. Two ways around that - icat placement + literal padding
# (kitty/ghostty), or paste(1)-ing chafa's rows against the text (everything
# else). Full reasoning, including the sizing math below:
# docs/implementation-notes.md.
image_preview_cell() {
    lr_ic_file=$1
    # This runs as a fresh `sh $0` with no configuration(), so the caller
    # passes the (configurable) poster dir along.
    images_cache_dir=${2:-$images_cache_dir}
    lr_ic_id=$(printf '%s' "$lr_ic_file" | sed -nE 's@.* ([0-9]+)\.jpg@\1@p')
    lr_ic_type=$(printf '%s' "$lr_ic_file" | sed -nE 's@^[[:space:]]*(.*) \((tv|movie)\)  [0-9]+\.jpg@\2@p')
    lr_ic_cols=${FZF_PREVIEW_COLUMNS:-40}
    lr_ic_lines=${FZF_PREVIEW_LINES:-30}
    # Text gets first claim on the pane's width: the poster takes at most 40%,
    # with a floor so it can't collapse on a tiny pane, because a 50/50 split
    # wraps titles/genres once fzf hands over fewer columns at high zoom.
    lr_ic_budget_w=$((lr_ic_cols * 2 / 5))
    [ "$lr_ic_budget_w" -lt 12 ] && lr_ic_budget_w=12
    lr_ic_budget_h=$((lr_ic_lines * 3 / 5))
    [ "$lr_ic_budget_h" -lt 6 ] && lr_ic_budget_h=$lr_ic_lines

    if { [ -n "$KITTY_WINDOW_ID" ] || [ -n "$GHOSTTY_RESOURCES_DIR" ]; } && command -v kitten >/dev/null 2>&1; then
        lr_ic_w=$lr_ic_budget_w
        # 2:3 posters in real terminal-cell pixels: height derived from a
        # fixed width so the box is never much wider than the poster renders.
        lr_ic_h=$((lr_ic_w / 2))
        [ "$lr_ic_h" -gt "$lr_ic_budget_h" ] && lr_ic_h=$lr_ic_budget_h
        lr_ic_dim="${lr_ic_w}x${lr_ic_h}"
        # --clear drops the previous highlight's placement; --scale-up makes
        # the ~200x300 thumbnail actually fill the box. Default z-index is
        # correct here - see docs/implementation-notes.md.
        kitten icat --clear --transfer-mode=memory --stdin=no --scale-up \
            --place="${lr_ic_dim}@0x0" "$images_cache_dir/$lr_ic_file" 2>/dev/null
        # +2 rows/cols of slack: --scale-up's fit rounds a hair taller than
        # the requested box at some zoom levels, and text landing one row
        # early prints over the poster.
        tmdb_preview_text "$lr_ic_type" "$lr_ic_id" "overlay:$((lr_ic_w + 2)):$((lr_ic_h + 2))"
        return 0
    fi

    # chafa's half-block cells are ~2x as tall as wide, so a 2:3 poster N rows
    # tall needs ~4N/3 columns (measured, not guessed). Height derives from the
    # width budget so the box never exceeds it and letterboxes.
    lr_ic_h=$((lr_ic_budget_w * 3 / 4))
    [ "$lr_ic_h" -gt "$lr_ic_budget_h" ] && lr_ic_h=$lr_ic_budget_h
    lr_ic_w=$((lr_ic_h * 4 / 3))
    lr_ic_dim="${lr_ic_w}x${lr_ic_h}"
    lr_ic_img_file="$tmp_dir/lr-ic-img.$$"
    lr_ic_text_file="$tmp_dir/lr-ic-text.$$"
    lr_ic_side_file="$tmp_dir/lr-ic-side.$$"
    lr_ic_below_file="$tmp_dir/lr-ic-below.$$"

    # shellcheck disable=SC2154 # TERM_PROGRAM is set by the terminal emulator, not by us
    [ "$TERM_PROGRAM" = "vscode" ] && lr_ic_fmt="--margin-bottom 8"
    # --format symbols, not "auto": a pixel-graphics format has no per-row
    # structure to paste text against. --scale max: chafa's default renders at
    # the source image's pixel size instead of filling -s's box.
    chafa $lr_ic_fmt --format symbols --scale max -s "$lr_ic_dim" "$images_cache_dir/$lr_ic_file" 2>/dev/null >"$lr_ic_img_file"

    tmdb_preview_text "$lr_ic_type" "$lr_ic_id" side >"$lr_ic_text_file"
    # "1,/pat/d" and "/pat/,$d" are the portable (GNU and BSD alike) way to cut
    # a stream at a matched line.
    sed '/^LOBSTER_SPLIT$/,$d' "$lr_ic_text_file" | sed 's/^/ /' >"$lr_ic_side_file"
    sed '1,/^LOBSTER_SPLIT$/d' "$lr_ic_text_file" >"$lr_ic_below_file"

    paste -d ' ' "$lr_ic_img_file" "$lr_ic_side_file"
    printf '\n'
    cat "$lr_ic_below_file"
    rm -f "$lr_ic_img_file" "$lr_ic_text_file" "$lr_ic_side_file" "$lr_ic_below_file"
}
# Downloads $1 to $2, discarding it unless it's really a JPEG: TMDB 403s
# occasionally, and an HTML error page saved as .jpg poisons the cache forever
# (chafa fails with "Unknown file format" and nothing cleans it out).
tp_download_image() {
    curl -sfL --connect-timeout 5 -m 10 -o "$2" "$1" 2>/dev/null
    case "$(head -c3 "$2" 2>/dev/null | od -An -tx1 | tr -d ' \n')" in
        ffd8ff) : ;;
        *) rm -f "$2" ;;
    esac
}
# Does the actual scrape + formatting; only called on a cache miss.
# Returns 1 (nothing cached) when TMDB didn't hand back a real detail page.
tp_render() {
    lr_tp_html=$(tmdb_fetch "/$1/$2" | tr -d '\n')
    # A real detail page always has this block; a bot-check/redirect/error
    # page doesn't, so this is the one check that decides whether anything
    # below is even attempted - the earlier version blindly sed'd whatever
    # came back and, on a blocked response, dumped raw page JS into the pane.
    case "$lr_tp_html" in
        *'class="overview"'*) : ;;
        *)
            printf '(details unavailable - try again in a moment)'
            return 1
            ;;
    esac

    # -n ...p, never a plain 's@@@': on a miss a substitution leaves the input
    # unchanged and the next "cut at the first closing tag" grabs unrelated
    # page content. See docs/implementation-notes.md.
    lr_tp_title=$(printf '%s' "$lr_tp_html" | sed -nE 's@.*<title>(.*)@\1@p' | sed 's@</title>.*@@; s/ (.*//' | tmdb_decode)
    lr_tp_tagline=$(printf '%s' "$lr_tp_html" | sed -nE 's@.*class="tagline"[^>]*>(.*)@\1@p' | sed 's@</h3>.*@@' | tp_strip | tmdb_decode)
    lr_tp_genres=$(printf '%s' "$lr_tp_html" | sed -nE 's@.*class="genres">(.*)@\1@p' | sed 's@</span>.*@@' | tp_strip | tmdb_decode)
    lr_tp_rating=$(printf '%s' "$lr_tp_html" | grep -oE 'data-percent="[0-9]+"' | head -1 | grep -oE '[0-9]+')
    lr_tp_release=$(printf '%s' "$lr_tp_html" | sed -nE 's@.*class="release">(.*)@\1@p' | sed 's@<.*@@' | tp_strip)
    lr_tp_runtime=$(printf '%s' "$lr_tp_html" | sed -nE 's@.*class="runtime">(.*)@\1@p' | sed 's@<.*@@' | tp_strip)
    # Bounded to the div's close, not the <p>'s: a title with no synopsis has
    # no <p> at all and cutting at the next one ran on into the cast list.
    lr_tp_overview=$(printf '%s' "$lr_tp_html" | sed -nE 's@.*class="overview"[^>]*>(.*)@\1@p' | sed 's@</div>.*@@' | tp_strip | tmdb_decode)
    lr_tp_cast=$(printf '%s' "$lr_tp_html" | sed -nE 's@.*class="people scroller">(.*)@\1@p' | sed 's@</ol>.*@@' |
        sed -E 's@<li class="card">@\n&@g' |
        sed -nE 's@.*<p><a[^>]*>([^<]*)</a></p>[[:space:]]*<p class="character">([^<]*)</p>.*@\1 (\2)@p' |
        head -6 | tmdb_decode)

    # 0-100 rating as a 5-star row (\xe2\x98\x85 filled / \xe2\x98\x86 empty),
    # nearest-star rounding - reads faster at a glance than a bare percent.
    lr_tp_stars=
    if [ -n "$lr_tp_rating" ]; then
        lr_tp_n=$(((lr_tp_rating + 10) / 20))
        [ "$lr_tp_n" -gt 5 ] && lr_tp_n=5
        lr_tp_i=0
        while [ "$lr_tp_i" -lt 5 ]; do
            if [ "$lr_tp_i" -lt "$lr_tp_n" ]; then
                lr_tp_stars="$lr_tp_stars\xe2\x98\x85"
            else
                lr_tp_stars="$lr_tp_stars\xe2\x98\x86"
            fi
            lr_tp_i=$((lr_tp_i + 1))
        done
    fi

    lr_tp_meta=$lr_tp_release
    [ -n "$lr_tp_runtime" ] && lr_tp_meta="$lr_tp_meta  \xc2\xb7  $lr_tp_runtime"
    [ -n "$lr_tp_stars" ] && lr_tp_meta="$lr_tp_meta  \xc2\xb7  $lr_tp_stars ${lr_tp_rating}%"

    case $lr_tp_mode in
        overlay:*)
            # fzf's renderer ignores cursor-addressing escapes but prints
            # literal characters fine, so the poster is cleared with real
            # spaces and blank lines. See docs/implementation-notes.md.
            lr_tp_col=${lr_tp_mode#overlay:}
            lr_tp_col=${lr_tp_col%%:*}
            lr_tp_h=${lr_tp_mode##*:}
            lr_tp_pad=$(printf '%*s' "$lr_tp_col" '')
            lr_tp_n=0
            printf '%s\033[1;36m%s\033[0m\n' "$lr_tp_pad" "$lr_tp_title"
            lr_tp_n=$((lr_tp_n + 1))
            if [ -n "$lr_tp_tagline" ]; then
                printf '%s\033[2;3m%s\033[0m\n' "$lr_tp_pad" "$lr_tp_tagline"
                lr_tp_n=$((lr_tp_n + 1))
            fi
            printf '\n'
            lr_tp_n=$((lr_tp_n + 1))
            printf '%s\033[2m%b\033[0m\n' "$lr_tp_pad" "$lr_tp_meta"
            lr_tp_n=$((lr_tp_n + 1))
            if [ -n "$lr_tp_genres" ]; then
                printf '%s\033[2m%s\033[0m\n' "$lr_tp_pad" "$lr_tp_genres"
                lr_tp_n=$((lr_tp_n + 1))
            fi
            # Pad to the *requested* placement height, not the poster's real
            # rendered height - the box always contains it.
            while [ "$lr_tp_n" -lt "$lr_tp_h" ]; do
                printf '\n'
                lr_tp_n=$((lr_tp_n + 1))
            done
            printf '%s\n' "$lr_tp_overview"
            [ -n "$lr_tp_cast" ] && printf '\n\033[1mCast\033[0m\n%s\n' "$lr_tp_cast"
            return 0
            ;;
    esac

    printf '\033[1;36m%s\033[0m\n' "$lr_tp_title"
    [ -n "$lr_tp_tagline" ] && printf '\033[2;3m%s\033[0m\n' "$lr_tp_tagline"
    printf '\n\033[2m%b\033[0m\n' "$lr_tp_meta"
    [ -n "$lr_tp_genres" ] && printf '\033[2m%s\033[0m\n' "$lr_tp_genres"
    # "side" mode cuts here: overview/cast go full width below the poster,
    # not squeezed into its narrow side column.
    [ "$lr_tp_mode" = "side" ] && printf 'LOBSTER_SPLIT\n'
    printf '\n%s\n' "$lr_tp_overview"
    if [ -n "$lr_tp_cast" ]; then
        printf '\n\033[1mCast\033[0m\n%s\n' "$lr_tp_cast"
    fi
}
# collapses tags + runs of whitespace left over from tr -d '\n' above
tp_strip() {
    sed -E 's@<[^>]*>@@g' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]][[:space:]]+/ /g'
}
tmdb_trending() {
    {
        tmdb_fetch "/movie"
        tmdb_fetch "/tv"
    } | tmdb_extract_media
}
# tmdb_recent <movie|tv>
tmdb_recent() {
    if [ "$1" = "tv" ]; then
        tmdb_fetch "/tv/airing-today" | tmdb_extract_media
    else
        tmdb_fetch "/movie/now-playing" | tmdb_extract_media
    fi
}
tmdb_top_rated() {
    if [ "$1" = "tv" ]; then
        tmdb_fetch "/tv/top-rated" | tmdb_extract_media
    else
        tmdb_fetch "/movie/top-rated" | tmdb_extract_media
    fi
}
# tmdb_genre <id-slug> <movie|tv> - a TMDB genre page uses the same card grid.
tmdb_genre() {
    tmdb_fetch "/genre/$1/$2" | tmdb_extract_media
}
# tmdb_year <year> <movie|tv> - TMDB's discover pages filter by release/air
# year and still serve the standard card grid.
tmdb_year() {
    if [ "$2" = "tv" ]; then
        tmdb_fetch "/discover/tv?first_air_date_year=$1" | tmdb_extract_media
    else
        tmdb_fetch "/discover/movie?primary_release_year=$1" | tmdb_extract_media
    fi
}
# Genre ids/slugs differ between movies and tv on TMDB (a movie genre id has
# no tv results), so two flat "id-slug=Name" lists, turned into menu rows by
# choose_genre's tr '=' '\t'. Static data, only changes if TMDB renames one.
MOVIE_GENRES='28-action=Action
12-adventure=Adventure
16-animation=Animation
35-comedy=Comedy
80-crime=Crime
99-documentary=Documentary
18-drama=Drama
10751-family=Family
14-fantasy=Fantasy
36-history=History
27-horror=Horror
10402-music=Music
9648-mystery=Mystery
10749-romance=Romance
878-science-fiction=Sci-Fi
10770-tv-movie=TV Movie
53-thriller=Thriller
10752-war=War
37-western=Western'
TV_GENRES='10759-action-adventure=Action & Adventure
16-animation=Animation
35-comedy=Comedy
80-crime=Crime
99-documentary=Documentary
18-drama=Drama
10751-family=Family
10762-kids=Kids
9648-mystery=Mystery
10763-news=News
10764-reality=Reality
10765-sci-fi-fantasy=Sci-Fi & Fantasy
10766-soap=Soap
10767-talk=Talk
10768-war-politics=War & Politics
37-western=Western'
# Reads a /tv/{id}/seasons page from stdin, emits "name \t season_number".
# The boundary pattern matches any /tv/*/season/N link generically, so the
# show's slug never has to be known. Split out from tmdb_seasons() so the
# parsing can be tested without a network call, same as tmdb_extract_media().
tmdb_parse_seasons() {
    tr -d '\n' |
        sed -E 's@<a href="/tv/[0-9]+-[^"]*/season/([0-9]+)">@\n&@g' |
        sed -nE 's@.*/season/([0-9]+)">.*alt="([^"]*)".*@\1\t\2@p' |
        tmdb_decode |
        awk -F'\t' 'BEGIN {
            OFS = "\t"
        }
        # Each season anchor appears twice on the page (poster + title link,
        # same as episodes below) - keep only the first, matching
        # tmdb_parse_episodes dedup.
        !seen[$1]++ {
            # Some not-yet-released seasons ship an unrendered client-side
            # template (e.g. "${data.name}") instead of real alt text.
            name = (index($2, "${") > 0 || $2 == "") ? "Season " $1 : $2
            print name, $1
        }'
}
tmdb_seasons() {
    tmdb_fetch "/tv/$1/seasons" | tmdb_parse_seasons
}
# Reads a /tv/{id}/season/{n} page from stdin, emits "name \t episode_number".
# Each episode anchor appears twice in the page (poster + title link), hence
# the dedupe. Split out from tmdb_episodes() for the same testing reason.
tmdb_parse_episodes() {
    tr -d '\n' |
        sed -E 's@<a class="no_click open"@\n&@g' |
        sed -nE 's@.*data-episode-number="([0-9]+)".*title="[^"]*Episode [0-9]+ - ([^"]*)".*@\1\t\2@p' |
        tmdb_decode |
        awk -F'\t' 'BEGIN { OFS = "\t" } !seen[$1]++ { print $1, $2, $1 ". " $2 }'
}
tmdb_episodes() {
    tmdb_fetch "/tv/$1/season/$2" | tmdb_parse_episodes
}
# JSON for whatever is currently selected; used by --json.
tmdb_detail_json() {
    json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
    # shellcheck disable=SC2312 # json_escape can't meaningfully fail here
    jseason=${season:-1}
    jepisode=${episode:-1}
    resolve_stream_bg "$media_type" "$media_id" "$jseason" "$jepisode" || lr_resolve_out=""
    stream=$lr_resolve_out
    video_link=$(printf '%s' "$stream" | cut -f1)
    referer=$(printf '%s' "$stream" | cut -f2)
    subs_csv=$(printf '%s' "$stream" | cut -f3)

    # Full per-backend listings, restricted to whatever --provider selected
    # (same filter resolve_stream just applied above) so this doesn't fire
    # every backend just to populate an informational field.
    lr_ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36"
    lr_dj_provider=${provider:-}
    if [ "$media_type" = "tv" ]; then lr_cinezo_sources=$CINEZO_TV_SOURCES; else lr_cinezo_sources=$CINEZO_MOVIE_SOURCES; fi
    vy_sources="[]" rv_sources="[]" fq_sources="[]" ss_sources="[]"
    case "$lr_dj_provider" in
        "" | videasy)
            if command -v node >/dev/null 2>&1; then
                lr_vy_dump=$(videasy_dump "$media_type" "$media_id" "$jseason" "$jepisode")
                [ -n "$lr_vy_dump" ] && vy_sources=$(printf '[%s]' "$(emit_json "$lr_vy_dump" "https://player.videasy.to/")")
            fi
            ;;
    esac
    case "$lr_dj_provider" in "" | rivestream) rv_sources=$(rivestream_dump "$media_type" "$media_id" "$jseason" "$jepisode") ;; esac
    case "$lr_dj_provider" in "" | cinezo) fq_sources=$(dump_family flikhub "$lr_cinezo_sources" "" "$media_type" "$media_id" "$jseason" "$jepisode") ;; esac
    case "$lr_dj_provider" in "" | vidlove) ss_sources=$(dump_family showsst "$VIDLOVE_SOURCES" "https://player.vidlove.cc/" "$media_type" "$media_id" "$jseason" "$jepisode") ;; esac

    subs_json=$(printf '%s' "$subs_csv" | tr ',' '\n' | awk 'NF { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "%s\"%s\"", (NR == 1 ? "" : ","), $0 }')
    [ -z "$subs_json" ] && subs_json=""
    if [ "$media_type" = "movie" ]; then
        printf '{"type":"movie","tmdb_id":"%s","title":"%s","poster":"%s","video_url":"%s","referer":"%s","sources":{"videasy":%s,"rivestream":%s,"cinezo":%s,"vidlove":%s},"subtitles":[%s]}\n' \
            "$media_id" "$(json_escape "$title")" "$(json_escape "$image_link")" "$(json_escape "$video_link")" "$(json_escape "$referer")" "$vy_sources" "$rv_sources" "$fq_sources" "$ss_sources" "$subs_json"
    else
        printf '{"type":"tv","tmdb_id":"%s","title":"%s","season":"%s","episode":"%s","episode_title":"%s","poster":"%s","video_url":"%s","referer":"%s","sources":{"videasy":%s,"rivestream":%s,"cinezo":%s,"vidlove":%s},"subtitles":[%s]}\n' \
            "$media_id" "$(json_escape "$title")" "$season" "$episode" "$(json_escape "$episode_title")" "$(json_escape "$image_link")" "$(json_escape "$video_link")" "$(json_escape "$referer")" "$vy_sources" "$rv_sources" "$fq_sources" "$ss_sources" "$subs_json"
    fi
}
# Populates $next_episode as "title \t episode_number" for whatever comes
# after the current episode, rolling into the next season if needed. Mutates
# $season/$season_title in place when it does roll over. Leaves
# $next_episode empty when there's nothing left in the show.
tmdb_next_episode() {
    next_episode=$(tmdb_episodes "$media_id" "$season" | awk -F'\t' -v e="$episode" '$1 == e + 1')
    [ -n "$next_episode" ] && return
    next_season=$((season + 1))
    candidate=$(tmdb_episodes "$media_id" "$next_season" | awk -F'\t' '$1 == 1')
    if [ -n "$candidate" ]; then
        season="$next_season"
        season_title=$(tmdb_seasons "$media_id" | awk -F'\t' -v s="$next_season" '$2 == s {print $1}')
        next_episode="$candidate"
    fi
}

### Menus (fzf / rofi) ###
generate_desktop() {
    cat <<EOF
[Desktop Entry]
Name=$1
Exec=echo %k %c
Icon=$2
Type=Application
Categories=lobster;
EOF
}
# menu <prompt> [columns-to-display]
# Shows a picker (fzf by default, rofi with --rofi) and returns the chosen
# full line on stdout. [columns-to-display] limits what's *shown* without
# altering what's returned, so callers can keep extra tab-separated fields
# (ids, years, ...) tucked away in the row they get back.
menu() {
    # menu_multi=true lets a caller tab-select several rows (fzf -m /
    # rofi -multi-select / "1,3,5-7" in the no-fzf fallback) - used for
    # batch episode downloads. Reset after every call so it never leaks
    # into the next menu().
    lr_menu_multi=$menu_multi
    menu_multi="false"
    case "$use_external_menu" in
        "true")
            lr_rofi_multi=""
            [ "$lr_menu_multi" = "true" ] && lr_rofi_multi="-multi-select"
            if [ -z "$2" ]; then
                rofi -kb-mode-next "" -kb-mode-previous "" -kb-custom-1 Shift+Left -kb-custom-2 Shift+Right $lr_rofi_multi -sort -dmenu -i -width 1500 -p "" -mesg "$1"
            else
                rofi -kb-mode-next "" -kb-mode-previous "" -kb-custom-1 Shift+Left -kb-custom-2 Shift+Right $lr_rofi_multi -sort -dmenu -i -width 1500 -p "" -mesg "$1" -display-columns "$2"
            fi
            rc=$? # 10 on kb-custom-1, 11 on kb-custom-2
            # rofi has no separate "back" gesture on plain Esc - it exits 1,
            # same as an empty dmenu cancel - so treat Esc as "back" too.
            [ "$rc" -eq 1 ] && rc="$BACK_CODE"
            ;;
        *)
            if ! command -v fzf >/dev/null 2>&1; then
                # ponytail: no fzf on PATH (e.g. plain Windows terminals) -
                # degrade to a numbered read-based picker instead of hard
                # requiring fzf. No preview support here, add if someone needs it.
                numbered_menu "$1" "$2" "$lr_menu_multi"
                return $?
            fi
            lr_fzf_multi=""
            [ "$lr_menu_multi" = "true" ] && lr_fzf_multi="-m"
            # $4, when set, is an extra --expect key (e.g. ctrl-d for delete)
            # that a caller can look for via DELETE_CODE.
            lr_expect="shift-left,esc"
            lr_header="esc: back  ctrl-c: quit"
            if [ -n "$4" ]; then
                lr_expect="$lr_expect,$4"
                lr_header="$4: delete  esc: back  ctrl-c: quit"
            fi
            if [ -z "$2" ]; then
                fzf_out=$(fzf $lr_fzf_multi --bind "shift-right:accept" --expect="$lr_expect" --header "$lr_header" --cycle --reverse --prompt "$1")
            elif [ -n "$3" ]; then
                fzf_out=$(fzf $lr_fzf_multi --bind "shift-right:accept" --bind "?:change-preview-window(right:90%:wrap|right:45%:wrap)" --expect="$lr_expect" --header "$lr_header  ?: expand info" --cycle --reverse --prompt "$1" --with-nth "$2" -d "\t" --preview "$3" --preview-window "right:45%:wrap")
            else
                fzf_out=$(fzf $lr_fzf_multi --bind "shift-right:accept" --expect="$lr_expect" --header "$lr_header" --cycle --reverse --prompt "$1" --with-nth "$2" -d "\t")
            fi
            rc=$?
            # --expect prints the key on its own line, followed by the
            # selected line if any - but on an empty/unfiltered list there's
            # no selection, so the key can be the *entire* output too.
            # Strip the optional delete key first (it can't collide with the
            # shift-left/esc/normal cases below).
            if [ -n "$4" ]; then
                case $fzf_out in
                    "$4" | "$4""$nl"*) rc="$DELETE_CODE"; fzf_out=${fzf_out#"$4"}; fzf_out=${fzf_out#"$nl"} ;;
                esac
            fi
            case $fzf_out in
                shift-left | shift-left"$nl"*)
                    rc="$BACK_CODE"
                    fzf_out=${fzf_out#shift-left}
                    fzf_out=${fzf_out#"$nl"}
                    ;;
                esc | esc"$nl"*)
                    rc="$BACK_CODE"
                    fzf_out=""
                    ;;
                "$nl"*) fzf_out=${fzf_out#"$nl"} ;;
                *) quit_now ;; # Ctrl-C, or fzf itself failed: quit cleanly
            esac
            printf '%s\n' "$fzf_out"
            ;;
    esac
    return "$rc"
}
# numbered_menu <prompt> [awk-field-spec] [multi]
# Fallback picker for systems without fzf: reads rows on stdin, prints a
# plain numbered list, and reads a choice (or "1,3,5-7" when multi=true)
# back. Same BACK_CODE/exit-on-quit contract as fzf/rofi above.
# expand_selection "1,3,5-7" -> "1\n3\n5\n6\n7" - pure line-number
# expansion for numbered_menu's multi-select mode. Split out so it's
# unit-testable without a tty attached.
expand_selection() {
    for lr_es_part in $(printf '%s' "$1" | tr ',' ' '); do
        case "$lr_es_part" in
            *-*)
                lr_es_from=${lr_es_part%-*}
                lr_es_to=${lr_es_part#*-}
                lr_es_k=$lr_es_from
                while [ "$lr_es_k" -le "$lr_es_to" ] 2>/dev/null; do
                    printf '%s\n' "$lr_es_k"
                    lr_es_k=$((lr_es_k + 1))
                done
                ;;
            *) printf '%s\n' "$lr_es_part" ;;
        esac
    done
}
numbered_menu() {
    lr_nm_file="$lr_tmp/numbered_menu.$$"
    cat >"$lr_nm_file"
    if [ ! -s "$lr_nm_file" ]; then
        rm -f "$lr_nm_file"
        return "$BACK_CODE"
    fi
    lr_nm_i=0
    while IFS= read -r lr_nm_line; do
        lr_nm_i=$((lr_nm_i + 1))
        if [ -n "$2" ]; then
            lr_nm_disp=$(printf '%s' "$lr_nm_line" | awk -F'\t' -v c="$2" '{n=split(c,f,","); out=""; for(i=1;i<=n;i++){out=out (i>1?" ":"") $(f[i])}; print out}')
        else
            lr_nm_disp="$lr_nm_line"
        fi
        printf '%3d) %s\n' "$lr_nm_i" "$lr_nm_disp" >&2
    done <"$lr_nm_file"
    if [ "$3" = "true" ]; then
        printf '%s (e.g. 1,3,5-7), b=back, q=quit: ' "$1" >&2
    else
        printf '%s (number), b=back, q=quit: ' "$1" >&2
    fi
    read -r lr_nm_choice </dev/tty
    case "$lr_nm_choice" in
        b | B)
            rm -f "$lr_nm_file"
            return "$BACK_CODE"
            ;;
        q | Q | "")
            rm -f "$lr_nm_file"
            quit_now
            ;;
        # Anything that isn't digits/commas/ranges would be handed straight
        # to sed as a script below - treat garbage as "back" instead.
        *[!0-9,-]*)
            rm -f "$lr_nm_file"
            return "$BACK_CODE"
            ;;
    esac
    if [ "$3" = "true" ]; then
        for lr_nm_n in $(expand_selection "$lr_nm_choice"); do
            sed -n "${lr_nm_n}p" "$lr_nm_file"
        done
    else
        sed -n "${lr_nm_choice}p" "$lr_nm_file"
    fi
    rm -f "$lr_nm_file"
}

### Prompts ###
prompt_to_continue() {
    if [ "$media_type" = "tv" ]; then
        continue_choice=$(printf "Next episode\nReplay episode\nSelect episode\nSelect season\nCopy stream URL\nCopy player command\nSearch\nQuit" | menu "Select: ")
    else
        continue_choice=$(printf "Replay\nCopy stream URL\nCopy player command\nSearch\nQuit" | menu "Select: ")
    fi
    rc=$?
    # Esc here means "up one level": back to the episode list for a show,
    # or just quit for a movie (there's no menu above it to return to).
    if [ "$rc" -eq "$BACK_CODE" ]; then
        if [ "$media_type" = "tv" ]; then continue_choice="Select episode"; else continue_choice="Quit"; fi
    fi
}
get_query() {
    rc=0
    if [ "$use_external_menu" = "false" ] && command -v fzf >/dev/null 2>&1; then
        # fzf as a search box: --print-query returns just the typed query,
        # --history gives up-arrow recall of past searches for free. /dev/null
        # stdin means zero items, so the query alone is what's printed.
        query=$(fzf --print-query --history "$data_dir/search_history" --reverse --header "enter: search  esc: quit" --prompt "Search Movie/TV Show: " < /dev/null)
        rc=$?
        query=$(printf '%s' "$query" | head -1)
    elif [ "$use_external_menu" = "false" ]; then
        printf "Search Movie/TV Show: "
        read -r query
    elif [ -n "$rofi_prompt_config" ]; then
        query=$(printf "" | rofi -kb-mode-next "" -kb-mode-previous "" -kb-custom-1 Shift+Left -theme "$rofi_prompt_config" -sort -dmenu -i -width 1500 -p "" -mesg "Search Movie/TV Show")
        rc=$?
        [ "$rc" -eq 1 ] && rc="$BACK_CODE"
    else
        query=$(printf "" | menu "Search Movie/TV Show")
        rc=$?
    fi
    # This is the root prompt - "back" and "cancel" both just mean quit, and
    # neither is an error worth a message.
    [ "$rc" -eq "$BACK_CODE" ] && exit 0
    [ "$rc" -gt 1 ] && exit 0
    [ -z "$query" ] && exit 0
}

### Searching / selecting ###
# A bad query re-prompts instead of exiting, so a typo doesn't kill the script.
# live_search - fzf with live-as-you-type results: each keystroke re-fetches
# results via "$0 --search {q}" (fzf cancels the previous reload on the next
# keystroke, so the leading sleep debounces). Returns the chosen media row
# (poster\tid\ttype\ttitle) and BACK_CODE/exit like menu().
live_search() {
    choice=$(fzf --expect=shift-left,esc --bind "shift-right:accept" \
        --bind "change:reload(sleep 0.25; sh '$0' --search '{q}' 2>/dev/null)" \
        --header "type to search  enter: play  esc: back  ctrl-c: quit" \
        --cycle --reverse --prompt "Search Movie/TV Show: " \
        --with-nth "4" --delimiter "\t" --history "$data_dir/search_history" \
        --preview "sh '$0' --tmdb-preview {3} {2} 2>/dev/null" --preview-window "right:45%:wrap" \
        < /dev/null)
    rc=$?
    case $choice in
        shift-left | shift-left"$nl"*)
            rc="$BACK_CODE"
            choice=${choice#shift-left}
            choice=${choice#"$nl"}
            ;;
        esc | esc"$nl"*)
            rc="$BACK_CODE"
            choice=""
            ;;
        "$nl"*) choice=${choice#"$nl"} ;;
        *) quit_now ;;
    esac
    printf '%s\n' "$choice"
    return "$rc"
}
choose_search() {
    # Live search only in fzf mode with no pre-set query; image preview and
    # rofi keep the two-step (query, then results-with-poster) flow.
    if [ "$live_search" = "true" ] && [ "$use_external_menu" = "false" ] && [ "$image_preview" != "true" ] \
        && command -v fzf >/dev/null 2>&1 && [ -z "$query" ]; then
        choice=$(live_search)
        rc=$?
        if [ "$rc" -eq "$BACK_CODE" ] || [ -z "$choice" ]; then
            exit 0
        fi
        image_link=$(printf '%s' "$choice" | cut -f1)
        media_id=$(printf '%s' "$choice" | cut -f2)
        media_type=$(printf '%s' "$choice" | cut -f3)
        title=$(printf '%s' "$choice" | cut -f4)
        if [ "$media_type" = "tv" ]; then
            STATE="SEASON"
        else
            keep_running="true"
            STATE="PLAY"
        fi
        return
    fi
    while [ -z "$response" ]; do
        [ -z "$query" ] && get_query
        response=$(tmdb_search "$query")
        [ -n "$response" ] && break
        notify "No results" "3000" "" "for \"$query\""
        query=""
    done
    STATE="MEDIA"
}
choose_media() {
    if [ "$image_preview" = "true" ]; then
        if [ "$use_external_menu" = "false" ] && [ "$use_ueberzugpp" = "true" ] && ! command -v ueberzugpp >/dev/null 2>&1; then
            notify "ueberzugpp not found, falling back to chafa"
            use_ueberzugpp="false"
        fi
        download_thumbnails "$response"
        select_desktop_entry ""
        rc=$?
        # select_desktop_entry only recovers id/title/type from the filename;
        # the poster URL (history field 8, discord presence) comes from the
        # id -> cover map download_thumbnails just wrote.
        image_link=$(awk -F'\t' -v id="$media_id" '$1 == id {print $2; exit}' "$tmp_dir/image_links" 2>/dev/null)
    else
        choice=$(printf '%s' "$response" | menu "Choose a Movie or TV Show: " "4" "sh '$0' --tmdb-preview {3} {2} 2>/dev/null")
        rc=$?
        image_link=$(printf '%s' "$choice" | cut -f1)
        media_id=$(printf '%s' "$choice" | cut -f2)
        media_type=$(printf '%s' "$choice" | cut -f3)
        title=$(printf '%s' "$choice" | cut -f4)
    fi

    if [ "$rc" -eq "$BACK_CODE" ]; then
        # A trending/recent listing IS the root - there's no search prompt
        # to fall back to, so back here just quits.
        [ -n "$listing" ] && exit 0
        STATE="SEARCH"
        response="" query="" choice=""
        return
    elif [ "$rc" -ne 0 ] && [ "$rc" -ne "$FORWARD_CODE" ]; then
        exit 0
    fi

    if [ "$media_type" = "tv" ]; then
        STATE="SEASON"
    else
        keep_running="true"
        STATE="PLAY"
    fi
}
choose_season() {
    row=$(tmdb_seasons "$media_id" | menu "$title > Season: " "1")
    rc=$?
    if [ "$rc" -eq "$BACK_CODE" ]; then
        STATE="MEDIA"
        return
    elif [ "$rc" -ne 0 ] && [ "$rc" -ne "$FORWARD_CODE" ]; then
        exit 0
    fi
    [ -z "$row" ] && exit 1
    season_title=$(printf '%s' "$row" | cut -f1)
    season=$(printf '%s' "$row" | cut -f2)
    STATE="EPISODE"
}
# Prefixes ✓ (watched) / ▶ (in progress) to episode rows for the show's
# current history resume point. History keeps one row per show, so only the
# season stored in history gets markers - earlier seasons aren't tracked
# (an honest limit of the data model, not a bug). Reads episode rows
# (num\ttitle\tdisplay) on stdin, emits the same shape with the marker
# prepended to the display column.
mark_watched() {
    lr_mw_row=""
    [ -s "$histfile" ] && lr_mw_row=$(awk -F'\t' -v id="$media_id" '$3 == "tv" && $4 == id { print; exit }' "$histfile")
    lr_mw_season=""
    lr_mw_episode=""
    lr_mw_pct=""
    if [ -n "$lr_mw_row" ]; then
        lr_mw_season=$(printf '%s' "$lr_mw_row" | cut -f5)
        lr_mw_episode=$(printf '%s' "$lr_mw_row" | cut -f6)
        lr_mw_pct=$(printf '%s' "$lr_mw_row" | cut -f9)
    fi
    while IFS="$(printf '\t')" read -r lr_mw_num lr_mw_title lr_mw_disp; do
        lr_mw_mark="  "
        if [ -n "$lr_mw_episode" ] && [ "$lr_mw_season" = "$season" ]; then
            if [ "$lr_mw_num" -lt "$lr_mw_episode" ] 2>/dev/null; then
                lr_mw_mark="✓ "
            elif [ "$lr_mw_num" -eq "$lr_mw_episode" ] 2>/dev/null; then
                if [ "${lr_mw_pct:-0}" -gt 90 ] 2>/dev/null; then lr_mw_mark="✓ "; else lr_mw_mark="▶ "; fi
            fi
        fi
        printf '%s\t%s\t%s%s\n' "$lr_mw_num" "$lr_mw_title" "$lr_mw_mark" "$lr_mw_disp"
    done
}
choose_episode() {
    lr_ce_episodes=$(tmdb_episodes "$media_id" "$season" | mark_watched)
    lr_ce_count=$(printf '%s\n' "$lr_ce_episodes" | grep -c .)

    # Downloading gets an explicit "whole season or just some" fork first,
    # instead of making people tab-select every episode by hand. "Select"
    # still allows picking several at once (tab in fzf, -multi-select in
    # rofi, "1,3,5-7" in the numbered fallback).
    if [ "$download" = "true" ] && [ "$lr_ce_count" -gt 1 ]; then
        lr_ce_scope=$(printf 'Select episode(s)\nDownload entire season (%s episodes)' "$lr_ce_count" | menu "$title > $season_title > ")
        rc=$?
        if [ "$rc" -eq "$BACK_CODE" ]; then
            STATE="SEASON"
            return
        elif [ "$rc" -ne 0 ] && [ "$rc" -ne "$FORWARD_CODE" ]; then
            exit 0
        fi
        case "$lr_ce_scope" in
            "Download entire season"*)
                download_episodes_parallel "$lr_ce_episodes"
                exit 0
                ;;
        esac
        menu_multi="true"
        rows=$(printf '%s' "$lr_ce_episodes" | menu "$title > $season_title > Episode(s) to download: " "3")
    else
        rows=$(printf '%s' "$lr_ce_episodes" | menu "$title > $season_title > Episode: " "3")
    fi
    rc=$?
    if [ "$rc" -eq "$BACK_CODE" ]; then
        STATE="SEASON"
        return
    elif [ "$rc" -ne 0 ] && [ "$rc" -ne "$FORWARD_CODE" ]; then
        exit 0
    fi
    [ -z "$rows" ] && exit 1

    if [ "$download" = "true" ] && [ "$(printf '%s\n' "$rows" | wc -l)" -gt 1 ]; then
        download_episodes_parallel "$rows"
        exit 0
    fi

    episode=$(printf '%s' "$rows" | cut -f1)
    episode_title=$(printf '%s' "$rows" | cut -f2)
    keep_running="true"
    STATE="PLAY"
}
# fetch_listing <trending|recent> [movie|tv]
# Bootstraps $response the same way choose_search() does, and marks the
# listing as the navigation root (see choose_media's BACK_CODE branch) since
# there's no search prompt underneath it to fall back to.
fetch_listing() {
    listing="$1"
    case "$1" in
        trending) response=$(tmdb_trending) ;;
        recent) response=$(tmdb_recent "$2") ;;
        top-rated) response=$(tmdb_top_rated "$2") ;;
        genre:*) response=$(tmdb_genre "${1#genre:}" "$2") ;;
        year:*) response=$(tmdb_year "${1#year:}" "$2") ;;
        *) : ;;
    esac
    [ -z "$response" ] && {
        notify "Error" "5000" "" "No results found"
        exit 1
    }
}
# choose_media_kind - one movie/tv ask for the type-dependent browse modes
# (top rated, genres). Sets $lr_kind to "movie"/"tv"/"".
choose_media_kind() {
    lr_kind=$(printf 'Movies\nTV shows' | menu "Type: ")
    rc=$?
    if [ "$rc" -eq "$BACK_CODE" ] || { [ "$rc" -ne 0 ] && [ "$rc" -ne "$FORWARD_CODE" ]; }; then
        lr_kind=""
        return
    fi
    case "$lr_kind" in
        Movies) lr_kind="movie" ;;
        "TV shows") lr_kind="tv" ;;
        *) lr_kind="" ;;
    esac
}
# genre_key <name> <movie|tv> - case-insensitive substring match of a
# genre name against the flat genre list, returns the "id-slug" key.
genre_key() {
    lr_gk_list="$MOVIE_GENRES"
    [ "$2" = "tv" ] && lr_gk_list="$TV_GENRES"
    printf '%s\n' "$lr_gk_list" | awk -F'=' -v q="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" '
        { if (index(tolower($2), q) > 0) { print $1; exit } }
    '
}
choose_genre() {
    choose_media_kind
    [ -z "$lr_kind" ] && { STATE="HOME"; return; }
    lr_genres="$MOVIE_GENRES"
    [ "$lr_kind" = "tv" ] && lr_genres="$TV_GENRES"
    lr_genre=$(printf '%s\n' "$lr_genres" | tr '=' '\t' | menu "Genre: " "2")
    rc=$?
    if [ "$rc" -eq "$BACK_CODE" ] || [ -z "$lr_genre" ]; then
        STATE="HOME"
        return
    elif [ "$rc" -ne 0 ] && [ "$rc" -ne "$FORWARD_CODE" ]; then
        exit 0
    fi
    fetch_listing "genre:$(printf '%s' "$lr_genre" | cut -f1)" "$lr_kind"
    STATE="MEDIA"
}
# choose_home - the default entry point (no query/flags): a hub that routes
# into continue/search/trending/now-playing/top-rated/genres instead of
# dropping the user straight into a bare search prompt.
choose_home() {
    lr_home_choice=$(printf 'Continue watching\nSearch\nTrending\nNow playing\nTop rated\nGenres\nQuit' | menu "lobster: ")
    rc=$?
    if [ "$rc" -eq "$BACK_CODE" ] || [ "$rc" -ne 0 ] || [ -z "$lr_home_choice" ]; then
        exit 0
    fi
    case "$lr_home_choice" in
        "Continue watching") lr_continue_back="home"; STATE="CONTINUE" ;;
        "Search") query="" response="" choice=""; STATE="SEARCH" ;;
        "Trending") fetch_listing trending; STATE="MEDIA" ;;
        "Now playing") fetch_listing recent movie; STATE="MEDIA" ;;
        "Top rated")
            choose_media_kind
            if [ -n "$lr_kind" ]; then fetch_listing top-rated "$lr_kind"; STATE="MEDIA"; else STATE="HOME"; fi
            ;;
        "Genres") choose_genre ;;
        "Quit" | "Exit") STATE="EXIT" ;;
    esac
}

### Image previews ###
# Downloads cover art for $1 (a cover\tid\ttype\ttitle[\tlabel] list), skipping
# whatever's already cached from a previous listing instead of wiping the
# whole cache over one miss. The optional 5th column is what the picker shows
# instead of the bare title (the continue list uses it for SxxEyy + progress).
download_thumbnails() {
    pids=""
    : >"$tmp_dir/image_set.tmp"
    while IFS="$(printf '\t')" read -r cover_url id type title label; do
        [ -z "$cover_url" ] && continue
        printf '%s\t%s\n' "$id" "$cover_url" >>"$tmp_dir/image_links" # for Discord presence lookup

        # No leading padding in the filename: fzf trims leading whitespace off
        # a {1} field, so a "  Title..." name came back unfindable and every
        # preview rendered blank. The picker hides the id via the label
        # column instead.
        poster_path="$images_cache_dir/$title ($type)  $id.jpg"
        printf '%s\t%s\n' "$title ($type)  $id.jpg" "${label:-$title ($type)}" >>"$tmp_dir/image_set.tmp"
        [ -f "$poster_path" ] && continue
        # A failed/challenge response saved as-is left a permanently-poisoned
        # ".jpg" that chafa/ueberzugpp choked on every run after (nothing
        # else ever cleaned it back out); tp_download_image checks the
        # JPEG magic bytes and removes the file instead of keeping a fake one.
        # TMDB's listing pages embed a small grid-thumbnail URL (~200px) -
        # good enough for the src attribute it was scraped from, blurry
        # blown up to fill a terminal cell grid. Same CDN, same filename,
        # just swap the size segment for a real poster width.
        tp_download_image "$(printf '%s' "$cover_url" | sed -E 's#(/t/p/)[^/]+/#\1w500/#')" "$poster_path" &
        pids="$pids $!"

        if [ "$use_external_menu" = "true" ]; then
            entry="$tmp_dir/applications/$id.desktop"
            # The padding spaces mean only the title is visible in the picker
            # while the id/type stay attached for parsing after selection.
            generate_desktop "$title ($type)  $id" "$poster_path" >"$entry" &
            pids="$pids $!"
        fi
    done <<EOF
$1
EOF
    for pid in $pids; do wait "$pid" 2>/dev/null; done
    # The picker lists exactly this set, not everything in the cache dir -
    # posters are kept across runs now, so a plain find would show every
    # title ever searched. Entries whose download failed are dropped here.
    : >"$tmp_dir/image_set"
    while IFS= read -r lr_dt_row; do # IFS= : titles have spaces
        lr_dt_file=${lr_dt_row%%"$(printf '\t')"*}
        [ -f "$images_cache_dir/$lr_dt_file" ] && printf '%s\n' "$lr_dt_row" >>"$tmp_dir/image_set"
    done <"$tmp_dir/image_set.tmp"
}
# Cover-art picker for fzf, defaulting to chafa; ueberzugpp is used instead
# when use_ueberzugpp=true (higher quality, but needs a terminal it supports).
image_preview_fzf() {
    if [ "$use_ueberzugpp" = "true" ]; then
        ub_pid_file="$tmp_dir.$$"
        if [ -z "$ueberzug_output" ]; then
            ueberzugpp layer --no-stdin --silent --use-escape-codes --pid-file "$ub_pid_file"
        else
            ueberzugpp layer -o "$ueberzug_output" --no-stdin --silent --use-escape-codes --pid-file "$ub_pid_file"
        fi
        ub_pid="$(cat "$ub_pid_file")"
        ub_socket="$ueberzugpp_tmp_dir/ueberzugpp-$ub_pid.socket"
        preview_cmd="ueberzugpp cmd -s $ub_socket -i fzfpreview -a add -x $ueberzug_x -y $ueberzug_y --max-width $ueberzug_max_width --max-height $ueberzug_max_height -f $images_cache_dir/{1}"
    else
        dep_check chafa
        # poster + details below it, done by re-running the script itself
        # (same reason tmdb_preview_text does - fzf's --preview is its own
        # process, no access to this script's shell functions). Sizing uses
        # fzf's own FZF_PREVIEW_COLUMNS/LINES, set on the preview process's
        # env - that's the actual pane size, unlike a guessed fixed value.
        preview_cmd="sh '$0' --image-preview-cell {1} '$images_cache_dir'"
    fi
    choice=$(fzf --bind "shift-right:accept" --expect=shift-left,esc --header "esc: back  ctrl-c: quit" --cycle -i -q "$1" --preview-window="$preview_window_size" --preview="$preview_cmd" --reverse --with-nth 2 -d '\t' <"$tmp_dir/image_set")
    rc=$?
    # Rows are "<poster filename>\t<label>"; only the filename carries the
    # id/type/title the caller parses back out.
    choice=$(printf '%s' "$choice" | cut -f1)
    case $choice in
        shift-left | shift-left"$nl"*)
            rc="$BACK_CODE"
            choice=${choice#shift-left}
            choice=${choice#"$nl"}
            ;;
        esc | esc"$nl"*)
            rc="$BACK_CODE"
            choice=""
            ;;
        "$nl"*) choice=${choice#"$nl"} ;;
        *) exit 0 ;;
    esac
    [ "$use_ueberzugpp" = "true" ] && ueberzugpp cmd -s "$ub_socket" -a exit
    return "$rc"
}
select_desktop_entry() {
    if [ "$use_external_menu" = "true" ]; then
        if [ -n "$image_config_path" ]; then
            rofi_out=$(rofi -show drun -drun-categories lobster -filter "$1" -show-icons -theme "$image_config_path")
        else
            rofi_out=$(rofi -show drun -drun-categories lobster -filter "$1" -show-icons)
        fi
        rc=$?
        choice=$(printf '%s' "$rofi_out" | sed -nE "s@.*/([0-9]*)\.desktop@\1@p")
        [ -z "$choice" ] && exit 0
        media_id=$(printf '%s' "$choice" | cut -d\  -f1)
        title=$(printf '%s' "$choice" | sed -nE "s@[0-9]* (.*) \((tv|movie)\)@\1@p")
        media_type=$(printf '%s' "$choice" | sed -nE "s@[0-9]* (.*) \((tv|movie)\)@\2@p")
    else
        image_preview_fzf "$1"
        rc=$?
        tput reset
        media_id=$(printf '%s' "$choice" | sed -nE 's@.* ([0-9]+)\.jpg@\1@p')
        title=$(printf '%s' "$choice" | sed -nE 's@^[[:space:]]*(.*) \((tv|movie)\)  [0-9]+\.jpg@\1@p')
        media_type=$(printf '%s' "$choice" | sed -nE 's@^[[:space:]]*(.*) \((tv|movie)\)  [0-9]+\.jpg@\2@p')
    fi
    return "$rc"
}

### Stream resolution ###
#   * cinezo            -> https://proxy1.flikhub.net  (direct mp4/mkv via proxy)
#   * vidlove / 111movies -> https://api.shows.st      (HLS master playlists)
# The remaining servers (vidup, videasy, vsembed) need a JS crypto step
#
#   resolve_stream <type> <tmdb_id> [season] [episode]
#     type is "movie" or "tv"
#   stdout (one line, tab-separated):
#     <video_url>\t<referer>\t<sub_url,sub_url,...>
#     referer and the subtitle list may both be empty.
#   Exit non-zero if nothing could be resolved.
#
# $quality, $subs_language and $no_subs are set as globals by the time this
# runs, in case your resolver wants to honor them.

# extract the first "key":"value" pair (value must not contain escaped quotes)
json_field() {
    printf '%s\n' "$1" | grep -oE "\"$2\":\"[^\"]*\"" | head -1 | sed "s/\"$2\":\"//; s/\"$//"
}

# penguplay/aiostreams (stremio addon) streams carry no "quality" field:
# resolution, size, source and audio language all live as free text in
# "name"/"description" (and, on older addons, "title").
#
# Emits ONE {"quality","url"} line - the winner - not every candidate, ranked
# by: closest to the requested height, then a single episode over a season
# pack, then an entry that declares a size over one that doesn't, then the
# addon's own order. Audio language is deliberately not ranked on.
# Why each of those: docs/implementation-notes.md.
penguplay_pairs() {
    printf '%s' "$1" |
        sed -E 's/\{"url": ?"/\n&/g' |
        awk -v t="${lr_target:-1080}" "$AWK_LIB"'
            {
                u = field($0, "url")
                if (u == "") next   # skips pengu'"'"'s urlless "support the project!" ad entry
                # "title" is the older shape of this field and still what
                # some addons emit - read all three rather than betting on one.
                meta = field($0, "name") " " field($0, "description") " " field($0, "title")
                h = height(meta)
                d = dist(h, t)
                pack = (meta ~ /[Ss][0-9]+[Ee][0-9]+ ?- ?[0-9]+/) ? 1 : 0
                nosize = (meta ~ /[0-9](\.[0-9]+)? ?[MG]B/) ? 0 : 1
                # best-first sort keys (distance, pack, nosize, original
                # order), then every url so a dead top pick can fall through
                # to the next candidate instead of being the only option.
                printf "%d\t%d\t%d\t%06d\t%d\t%s\n", d, pack, nosize, n, h, u
                n++
            }
        ' |
        sort -n -k1,1 -k2,2 -k3,3 -k4,4 |
        awk -F'\t' '{ printf "{\"quality\":\"%dp\",\"url\":\"%s\"}\n", $5, $6 }'
}

# Shared awk helpers for every {"quality":...,"url":...} block parser below
# (quality_candidates, rivestream_candidates, emit_json, penguplay_pairs).
# Concatenated into each awk program as its function prelude.
AWK_LIB='
    # value of "<key>":"..." in a line, by name - so an upstream field
    # reorder or an added key cannot silently zero out a backend.
    function field(line, key,   re, m) {
        re = "\"" key "\": ?\"[^\"]*\""
        if (!match(line, re)) return ""
        m = substr(line, RSTART, RLENGTH)
        sub(/^"[^"]*": ?"/, "", m)
        sub(/"$/, "", m)
        return m
    }
    # Height only from a real resolution token ("1080p", or a bare 3-4 digit
    # run), never every digit in the string - see docs/implementation-notes.md.
    # Some addons spell 4K out instead of giving a height. bare=1 also accepts
    # an unsuffixed digit run - only safe on a short quality label, never on
    # free text, where a year would read as a resolution.
    # An explicit "1080p" token wins over a "4K" mention: release names like
    # "Oldboy.4K.Restoration.1080p.BluRay" are 1080p files, and reading them
    # as 2160 put a 4K remux at the top of a 1080p request.
    function height(s, bare) {
        if (match(s, /[0-9]+[pP]/)) return substr(s, RSTART, RLENGTH - 1) + 0
        if (s ~ /4K|2160/) return 2160
        if (bare && match(s, /[0-9][0-9][0-9][0-9]?/)) return substr(s, RSTART, RLENGTH) + 0
        return 0
    }
    function dist(h, t) { return h > t ? h - t : t - h }
'
# The one per-source-block boundary every parser below keys off.
url_blocks() {
    grep -oE '\{[^{}]*"url": ?"[^"]*"[^{}]*\}'
}

# pick the best url from flikhub/shows.st/rivestream quality blocks, closest
# to $2 height. Blocks are matched by "url" alone (order/extra-fields
# agnostic) and fields pulled out by name in awk, so an upstream field
# reorder or an added key can't silently zero out a backend.
# emits av<TAB>url for every source block tied at the best quality match
# (closest to target height $2, audio-track index ascending on a tie).
# Normally one line; more than one only when a backend (videasy) lists
# several dub tracks as separate entries with identical quality labels and
# no language field to tell them apart - only the URL differs, e.g.
# ".../s1080p-v1-a1.m3u8" vs "...-a2.m3u8". resolve_stream uses that to offer
# a picker instead of guessing; pick_quality just takes the top line
# (a1 is conventionally the primary/original track).
quality_candidates() {
    printf '%s\n' "$1" | url_blocks | awk -v t="${2:-1080}" "$AWK_LIB"'
        {
            q = field($0, "quality"); u = field($0, "url")
            if (u == "") next
            h = height(q, 1); d = dist(h, t)
            av = 999
            if (match(u, /-a[0-9]+\./)) { seg = substr(u, RSTART, RLENGTH); gsub(/[^0-9]/, "", seg); av = seg + 0 }
            n++; U[n] = u; D[n] = d; H[n] = h; AV[n] = av
            if (n == 1 || d < bestd || (d == bestd && h > besth)) { bestd = d; besth = h }
        }
        END {
            for (i = 1; i <= n; i++) if (D[i] == bestd && H[i] == besth) print AV[i] "\t" U[i]
        }
    ' | sort -n -k1,1
}
pick_quality() {
    quality_candidates "$1" "$2" | head -1 | cut -f2
}

# One table for every language lookup in the script:
#   name | codes (first is the ISO 639-1 form) | display name
# The three readers below are the only places it's consulted. Anything not
# listed falls through as-is - mpv's own matching is lenient about codes, and
# a raw code is still a better track label than nothing.
LANGS='english|en,eng,eng-US,en-US|English
french|fr,fre,fra|French
spanish|es,spa|Spanish
german|de,ger,deu|German
italian|it,ita|Italian
japanese|ja,jpn|Japanese
portuguese|pt,por|Portuguese
russian|ru,rus|Russian
chinese|zh,chi,zho|Chinese
korean|ko,kor|Korean
arabic|ar,ara|Arabic
hindi|hi,hin|Hindi
polish|pl,pol|Polish
turkish|tr,tur|Turkish
dutch|nl,dut,nld|Dutch'

# lang_name <code> - ISO code -> display name, for labeling audio tracks.
lang_name() {
    case "$1" in "" | und) return ;; esac
    lr_ln_name=$(printf '%s\n' "$LANGS" | awk -F'|' -v c="$1" '
        BEGIN { c = tolower(c) }
        { n = split($2, a, ","); for (i = 1; i <= n; i++) if (tolower(a[i]) == c) { print $3; exit } }
    ')
    printf '%s' "${lr_ln_name:-$1}"
}

# lang_code <name> - free-text language name (as used by $audio_language /
# $subs_language) -> mpv --alang code list.
lang_code() {
    lr_lc_codes=$(printf '%s\n' "$LANGS" | awk -F'|' -v q="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" '$1 == q { print $2; exit }')
    printf '%s' "${lr_lc_codes:-$1}"
}

# lang_aliases <name> - space-separated strings a subtitle label may carry
# for that language (the name itself plus every code), for collect_subs.
lang_aliases() {
    lr_la_row=$(printf '%s\n' "$LANGS" | awk -F'|' -v q="$1" '$1 == q { print $1 " " $2; exit }')
    printf '%s' "${lr_la_row:-$1}" | tr ',' ' '
}

# Labels av<TAB>url rows (from quality_candidates - no language field
# available, only a bare quality+url) using ffprobe (soft dep, parallel
# probes) to read each stream's actual audio language. Falls back to
# "Track N" per entry when ffprobe is missing or a probe finds no tag.
# stdout: label<TAB>url, same row count and order as the input.
probe_audio_labels() {
    # Candidates are quality-sorted, so the cap keeps the best $max_audio_tracks
    # and drops the tail nobody would have picked - each dropped row is one
    # fewer ffprobe of a remote stream.
    lr_pa_urls="$1"
    [ "${max_audio_tracks:-5}" -gt 0 ] 2>/dev/null &&
        lr_pa_urls=$(printf '%s\n' "$1" | head -n "$max_audio_tracks")
    lr_pa_n=$(printf '%s\n' "$lr_pa_urls" | grep -c .)
    lr_pa_tmp="$lr_tmp/audio-labels.$$"
    : >"$lr_pa_tmp"
    if command -v ffprobe >/dev/null 2>&1; then
        status_note "Checking $lr_pa_n audio tracks…"
        lr_pa_pids=""
        lr_pa_i=0
        # shellcheck disable=SC2034 # lr_pa_av: candidates are already
        # av-sorted, lr_pa_i (not the raw index) is what labels correlate on
        while IFS="$(printf '\t')" read -r lr_pa_av lr_pa_url; do
            lr_pa_i=$((lr_pa_i + 1))
            (
                lr_pa_lang=$(ffprobe -v quiet -analyzeduration 2000000 -probesize 2000000 -select_streams a:0 \
                    -show_entries stream_tags=language -of default=nw=1:nk=1 "$lr_pa_url" 2>/dev/null | head -1)
                printf '%s\t%s\n' "$lr_pa_i" "$(lang_name "$lr_pa_lang")" >>"$lr_pa_tmp"
            ) &
            lr_pa_pids="$lr_pa_pids $!"
        done <<EOF
$lr_pa_urls
EOF
        for lr_pa_pid in $lr_pa_pids; do wait "$lr_pa_pid" 2>/dev/null; done
    fi
    clear_status

    lr_pa_i=0
    # shellcheck disable=SC2034 # lr_pa_av unused, see note above
    while IFS="$(printf '\t')" read -r lr_pa_av lr_pa_url; do
        lr_pa_i=$((lr_pa_i + 1))
        lr_pa_lang=$(awk -F'\t' -v i="$lr_pa_i" '$1==i{print $2}' "$lr_pa_tmp")
        if [ -n "$lr_pa_lang" ]; then
            printf '%s\t%s\n' "$lr_pa_lang" "$lr_pa_url"
        else
            printf '%s\t%s\n' "Track $lr_pa_i" "$lr_pa_url"
        fi
    done <<EOF
$lr_pa_urls
EOF
    rm -f "$lr_pa_tmp"
}

# pick_audio_candidates <label\turl rows> <preferred language>
# Drops rows matching $blocked_audio_languages (space-separated, permissive
# substring match), then picks the one URL mpv should play: an explicit match
# for $2, else "Default", else the first survivor. "Default" rows are never
# blocked - there's no evidence either way about what they are.
#
# Only one gets picked, never handed to mpv as extra --audio-file tracks:
# these are separate providers/hosts, not renditions of the same encode, and
# mirrors with different intros/padding desync badly. A stream that packs
# several dubs into one file is mpv's --alang's job - see play().
# stdout: the picked url
pick_audio_candidates() {
    lr_pac_lang=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')

    lr_pac_kept=$(printf '%s\n' "$1" | awk -F'\t' -v blocked="${blocked_audio_languages:-}" '
        BEGIN { n = split(tolower(blocked), b, " ") }
        {
            l = tolower($1)
            if (l == "default") { print; next }
            skip = 0
            for (i = 1; i <= n; i++) if (b[i] != "" && index(l, b[i]) > 0) { skip = 1; break }
            if (!skip) print
        }
    ')
    [ -z "$lr_pac_kept" ] && lr_pac_kept=$1

    lr_pac_primary=$(printf '%s\n' "$lr_pac_kept" | awk -F'\t' -v lang="$lr_pac_lang" '
        tolower($1) != "default" && index(tolower($1), lang) > 0 { print; exit }
    ' | cut -f2)
    [ -z "$lr_pac_primary" ] && lr_pac_primary=$(printf '%s\n' "$lr_pac_kept" | awk -F'\t' '
        tolower($1) == "default" { print; exit }
    ' | cut -f2)
    [ -z "$lr_pac_primary" ] && lr_pac_primary=$(printf '%s\n' "$lr_pac_kept" | head -1 | cut -f2)
    printf '%s' "$lr_pac_primary"
}

# pick the closest-resolution variant URL from a master m3u8 file
pick_variant() {
    f=$1; t=${2:-1080}
    best=""; bestd=999999; besth=0; cur_h=""
    while IFS= read -r line; do
        case "$line" in
            "#EXT-X-STREAM-INF"*)
                cur_h=$(printf '%s' "$line" | sed -n 's/.*RESOLUTION=[0-9]*x\([0-9]*\).*/\1/p')
                [ -z "$cur_h" ] && cur_h=0
                ;;
            http*)
                if [ -n "$cur_h" ]; then
                    d=$((cur_h - t)); [ "$d" -lt 0 ] && d=$((-d))
                    if [ -z "$best" ] || [ "$d" -lt "$bestd" ] || { [ "$d" -eq "$bestd" ] && [ "$cur_h" -gt "$besth" ]; }; then
                        bestd=$d; besth=$cur_h; best=$line
                    fi
                fi
                cur_h=""
                ;;
        esac
    done < "$f"
    printf '%s' "$best"
}

# collect_subs <json> <language name> - comma-separated subtitle urls
# whose label matches. Blocks are matched by "file" (or "url", for stremio-
# shaped objects) and fields pulled out by name, so field order is irrelevant.
# Language is read from "label", "lang" or "name" and matched against the name
# and its ISO 639-1/639-2 codes, so an opensubtitles-style "en"/"eng" matches
# "english" like a full-name label does. Matching is whole-token, not
# substring: "en" is a substring of "french", "german" and "slovenian".
collect_subs() {
    lr_lang=$2
    lr_pat=$(lang_aliases "$lr_lang" | tr '[:upper:]' '[:lower:]')
    printf '%s\n' "$1" | grep -oE '\{[^{}]*"(file|url)": ?"[^"]*"[^{}]*\}' \
        | while IFS= read -r s; do
        lbl=$(printf '%s' "$s" | sed -nE 's/.*"(label|lang|name)": ?"([^"]*)".*/\2/p' | tr '[:upper:]' '[:lower:]' | head -1)
        file=$(printf '%s' "$s" | sed -nE 's/.*"(file|url)": ?"([^"]*)".*/\2/p' | head -1)
        [ -z "$file" ] && continue
        # Both sides get every non-alphanumeric run collapsed to one space, so
        # an alias can only match a whole token: "English (SDH)" and "en-US"
        # still match english, "french" no longer does.
        lr_words=" $(printf '%s' "$lbl" | tr -c '[:alnum:]' ' ' | tr -s ' ') "
        lr_match=""
        for lr_alias in $lr_pat; do
            lr_alias=$(printf '%s' "$lr_alias" | tr -c '[:alnum:]' ' ' | tr -s ' ')
            case "$lr_words" in
                *" $lr_alias "*) lr_match=1; break ;;
            esac
        done
        [ -z "$lr_match" ] && continue
        printf '%s\n' "$(printf '%s' "$file" | sed 's/ /%20/g')"
    done | awk -v n="${max_subs:-5}" '!seen[$0]++ && (n <= 0 || ++kept <= n)' \
        | awk '{ if (NR==1) printf "%s", $0; else printf ",%s", $0 }'
}

# videasy (player.videasy.to) resolver. The /cdn/sources-with-title response is
# XOR-obfuscated with a custom keystream derived from the seed + mediaId, and
# the state needs 32-bit unsigned ops plus a sparse 61-word array, so this is
# delegated to a small Node snippet. Returns nothing (exit 1) if node is
# missing or the source has no playable stream.
#
# videasy_node <type> <id> <season> <episode>
#   stdout: {"sources":[{"quality","url"}...],"referer":...,"subtitles":[...]}
#   Quality-picking happens shell-side (pick_quality), so this one network
#   hit serves both a single playback pick and --json's full listing.
# Set debug=true to see this on stderr instead of discarding it. (Safe to
# exec here: this function only ever runs inside a $(...) subshell, so the fd
# redirect doesn't leak to the rest of the script.)
videasy_node() {
    command -v node >/dev/null 2>&1 || return 1
    [ "$debug" = "true" ] || exec 2>/dev/null
    node - "$1" "$2" "$3" "$4" <<'VIDEASY_EOF'
const [type,id,season,episode] = [process.argv[2],process.argv[3],process.argv[4],process.argv[5]];
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124 Safari/537.36';
const K = [1116352408,1899447441,3049323471,3921009573,961987163,1508970993,2453635748,2870763221,3624381080,310598401,607225278,1426881987,1925078388,2162078206,2614888103,3248222580];
const M = [109,118,109,49];
const w = e => { e >>>= 0; e ^= e >>> 16; e = Math.imul(e,2246822507) >>> 0; e ^= e >>> 13; e = Math.imul(e,3266489909) >>> 0; return (e ^= e >>> 16) >>> 0; };
const rl = (e,t) => { e >>>= 0; t &= 31; return t ? (e << t | e >>> 32-t) >>> 0 : e >>> 0; };
const fnv = s => { let t = 2166136261; for (let i = 0; i < s.length; i++) t = Math.imul(t ^ s.charCodeAt(i), 16777619) >>> 0; return w(t); };
const keygen = (seed, mid) => {
  let a = w((fnv(seed) ^ w(((Number(mid) >>> 0) ^ 2654435769) >>> 0)) >>> 0) >>> 0;
  const S = new Array(61);
  for (let e = 0; e < 8; e++) { const n = a % 61; a = rl((a + 2654435769) >>> 0, 7 + (7 & e)); S[n] = (a ^ w(a)) >>> 0; a = w((a + n) >>> 0); }
  return { S, acc: w((2779096485 ^ a) >>> 0) >>> 0 };
};
const step = (k, c) => {
  const S = k.S; let o = k.acc; const n = o % 61;
  const i = 0 - Number(n in S); const d = S[n] >>> 0; const s = o;
  const a = (d ^ Math.imul(2654435769, c + 1)) >>> 0;
  let l = (((s ^ a) >>> 0) | ((s & a & i) >>> 0)) >>> 0;
  l = (rl((l + o) >>> 0, 31 & n) ^ rl(o, 31 & Math.imul(n, 7))) >>> 0;
  o = w((l + 2654435769) >>> 0); S[n] = o >>> 0; k.acc = o; return o >>> 0;
};
const b64 = s => new Uint8Array(Buffer.from(s.replace(/-/g,'+').replace(/_/g,'/').padEnd(4*Math.ceil(s.length/4),'='), 'base64'));
const dec = (ct, seed, mid) => {
  const r = b64(ct); const k = keygen(seed, mid); const ks = new Uint8Array(r.length);
  let o = 0;
  for (let e = 0; e < r.length; ) { const t = step(k, o++); ks[e++] = 255 & t; if (e < r.length) ks[e++] = t >>> 8 & 255; if (e < r.length) ks[e++] = t >>> 16 & 255; if (e < r.length) ks[e++] = t >>> 24 & 255; }
  for (let e = 0; e < r.length; e++) r[e] ^= ks[e];
  for (let e = 0; e < 4; e++) if (r[e] !== M[e]) throw new Error('decrypt failed');
  return Buffer.from(r.subarray(4)).toString('utf8');
};
(async () => {
  const h = { 'User-Agent': UA };
  const seed = (await (await fetch('https://api.speedracelight.com/seed?mediaId=' + id, { headers: h, signal: AbortSignal.timeout(7000) })).json()).seed;
  const p = new URLSearchParams({ tmdbId: id, mediaType: type, seasonId: String(season), episodeId: String(episode), enc: '2', seed });
  const resp = await fetch('https://api.speedracelight.com/cdn/sources-with-title?' + p, { headers: h, signal: AbortSignal.timeout(7000) });
  if (!resp.ok) throw new Error('HTTP ' + resp.status);
  const j = JSON.parse(dec(await resp.text(), seed, id));
  const srcs = j.sources || [];
  if (!srcs.length) throw new Error('no sources');
  const subs = (j.subtitles || []).map(s => s.url || s.file).filter(Boolean);
  // dump: one payload serving both playback (best-pick, done shell-side by
  // pick_quality) and --json's full listing, so videasy is hit once.
  console.log(JSON.stringify({ sources: srcs.map(s => ({ quality: s.quality || '', url: s.url })), referer: 'https://player.videasy.to/', subtitles: subs }));
})().catch(e => { console.error('videasy: ' + e.message); process.exit(1); });
VIDEASY_EOF
}

# dump the raw videasy payload (sources+referer+subtitles as one JSON
# object); reused for both playback (shell picks best quality out of it) and
# --json's full listing, so videasy is only ever hit once per call site.
videasy_dump() {
    videasy_node "$1" "$2" "$3" "$4"
}

### Provider-list constants ###
# Sub-source order per backend. flikhub/showsst proxy several upstream
# scrapers behind one API; rivestream has its own set of scraper providers.
CINEZO_MOVIE_SOURCES="cinefreak moviebox"
CINEZO_TV_SOURCES="moviebox cinefreak"
VIDLOVE_SOURCES="ipcloud vidapi tcloud warden moviebox2 moviebox cinefreak"
RIVESTREAM_PROVIDERS="quasar apex pulse primevids citadel solstice horizon flowcast asiacloud hindicast guru"

# provider_url <kind> <source> <type> <id> <season> <episode>
# kind is flikhub (cinezo), showsst (vidlove), or rivestream.
provider_url() {
    case "$1" in
        flikhub)
            if [ "$3" = "tv" ]; then
                printf 'https://proxy1.flikhub.net/tv?id=%s&season=%s&episode=%s&mode=json&sources=%s&hevc=1' "$4" "$5" "$6" "$2"
            else
                printf 'https://proxy1.flikhub.net/movie?id=%s&mode=json&sources=%s&hevc=1' "$4" "$2"
            fi
            ;;
        showsst)
            if [ "$3" = "tv" ]; then
                printf 'https://api.shows.st/tv?id=%s&season=%s&episode=%s&mode=json&sources=%s' "$4" "$5" "$6" "$2"
            else
                printf 'https://api.shows.st/movie?id=%s&mode=json&sources=%s' "$4" "$2"
            fi
            ;;
        rivestream)
            lr_pu_url="https://scrapper.rivestream.app/api/provider?provider=$2&id=$4"
            [ "$3" = "tv" ] && lr_pu_url="$lr_pu_url&season=$5&episode=$6"
            case "$2" in primevids | citadel) lr_pu_url="$lr_pu_url&cb=$(( $(date +%s) / 3000 ))" ;; esac
            printf '%s' "$lr_pu_url"
            ;;
    esac
}
# curl a single upstream sub-source; stdout is raw JSON, empty on failure
provider_fetch() {
    curl -sS --connect-timeout 5 -m 8 -A "$lr_ua" -H "Accept: application/json" "$(provider_url "$@")" 2>/dev/null
}

# Some providers hand back a URL on a domain that has already gone dark
# (rotated CDN, dead mirror, DNS never resolves at all) - the "Now Playing"
# fires before mpv ever gets to it, so nothing else catches that. A cheap
# ranged GET (2 bytes) is enough to prove DNS/TCP/TLS actually work; curl's
# http_code comes back "000" only on a connection-level failure, regardless
# of what HTTP status the server itself answers with.
# $1 = url, $2 = optional referer
url_alive() {
    lr_ua_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 -m 6 -A "$lr_ua" \
        ${2:+-H "Referer: $2"} -r 0-1 "$1" 2>/dev/null)
    [ -n "$lr_ua_code" ] && [ "$lr_ua_code" != "000" ]
}

# quality-block JSON objects from $1 as {"quality","url","referer":$2}, comma
# joined (no brackets - caller wraps). Same order/extra-field-agnostic
# matching as pick_quality.
emit_json() {
    printf '%s\n' "$1" | url_blocks | awk -v ref="$2" "$AWK_LIB"'
        {
            q = field($0, "quality"); u = field($0, "url")
            if (u == "") next
            gsub(/\\/, "\\\\", q); gsub(/"/, "\\\"", q)
            gsub(/\\/, "\\\\", u); gsub(/"/, "\\\"", u)
            printf "%s{\"quality\":\"%s\",\"url\":\"%s\",\"referer\":\"%s\"}", (n++ ? "," : ""), q, u, ref
        }
    '
}

# Shared by cinezo (flikhub) and vidlove (showsst): both proxy several
# upstream sub-sources behind one API and return either direct-file quality
# blocks, or (showsst only) a master HLS playlist to pick a variant from.
# Reads $lr_target/$lr_lang (set by resolve_stream). stdout: url\treferer\tsubs
#   $1=kind $2=space-separated sub-sources $3=referer $4=try_hls_fallback
#   $5=type $6=id $7=season $8=episode
try_family() {
    lr_tf_kind=$1; lr_tf_sources=$2; lr_tf_referer=$3; lr_tf_hls=$4
    lr_tf_type=$5; lr_tf_id=$6; lr_tf_season=$7; lr_tf_episode=$8
    for lr_tf_src in $lr_tf_sources; do
        lr_tf_resp=$(provider_fetch "$lr_tf_kind" "$lr_tf_src" "$lr_tf_type" "$lr_tf_id" "$lr_tf_season" "$lr_tf_episode")
        [ -z "$lr_tf_resp" ] && continue
        case "$lr_tf_resp" in *'"source":null'*) continue ;; esac
        [ "$lr_tf_resp" != "${lr_tf_resp#*\"source\":\{}" ] || continue

        lr_tf_video=$(pick_quality "$lr_tf_resp" "$lr_target")
        if [ -n "$lr_tf_video" ]; then
            lr_tf_subs=$(collect_subs "$lr_tf_resp" "$lr_lang")
            printf '%s\t%s\t%s\n' "$lr_tf_video" "$lr_tf_referer" "$lr_tf_subs"
            return 0
        fi
        [ "$lr_tf_hls" != "true" ] && continue

        lr_tf_master=$(json_field "$lr_tf_resp" "url")
        [ -z "$lr_tf_master" ] && continue
        # $$ scopes this per-process: parallel episode downloads of the same
        # show/provider would otherwise race on the same filename.
        lr_tf_mfile="$lr_tmp/master-$lr_tf_id-$lr_tf_src.$$.m3u8"
        lr_tf_headers=$(curl -sS --connect-timeout 5 -m 8 -A "$lr_ua" -H "Referer: $lr_tf_referer" -D - -o "$lr_tf_mfile" "$lr_tf_master") || continue
        case "$(printf '%s' "$lr_tf_headers" | grep -i '^content-type:' | tr -d '\r')" in
            *mpegurl*) : ;;
            *) continue ;;
        esac
        lr_tf_video=$(pick_variant "$lr_tf_mfile" "$lr_target")
        [ -z "$lr_tf_video" ] && lr_tf_video=$lr_tf_master
        lr_tf_subs=$(collect_subs "$lr_tf_resp" "$lr_lang")
        printf '%s\t%s\t%s\n' "$lr_tf_video" "$lr_tf_referer" "$lr_tf_subs"
        return 0
    done
    return 1
}

# every quality-block entry across every sub-source of a family backend, as a
# JSON array. Used by --json; accumulates across all sub-sources rather than
# stopping at the first hit, so it surfaces every option available.
dump_family() {
    lr_df_kind=$1; lr_df_sources=$2; lr_df_referer=$3
    lr_df_type=$4; lr_df_id=$5; lr_df_season=$6; lr_df_episode=$7
    lr_df_out=""
    for lr_df_src in $lr_df_sources; do
        lr_df_resp=$(provider_fetch "$lr_df_kind" "$lr_df_src" "$lr_df_type" "$lr_df_id" "$lr_df_season" "$lr_df_episode")
        [ -z "$lr_df_resp" ] && continue
        case "$lr_df_resp" in *'"source":null'*) continue ;; esac
        [ "$lr_df_resp" != "${lr_df_resp#*\"source\":\{}" ] || continue
        lr_df_entries=$(emit_json "$lr_df_resp" "$lr_df_referer")
        [ -n "$lr_df_entries" ] && lr_df_out="$lr_df_out${lr_df_out:+,}$lr_df_entries"
    done
    [ -n "$lr_df_out" ] && printf '[%s]' "$lr_df_out" || printf '[]'
}

# rivestream (scrapper.rivestream.app): first playable source across its
# provider list. Reads $lr_lang. stdout: url\treferer\tsubs
# Fires every rivestream provider in parallel (same pattern as
# download_thumbnails' parallel curls) and returns their concatenated raw
# JSON. Was previously a serial loop that stopped at the first provider that
# answered - fast, but meant whichever provider happened to respond first won,
# with zero regard for what it actually served.
rivestream_fetch_all() {
    lr_rfa_tmp="$lr_tmp/rivestream-all.$$"
    : >"$lr_rfa_tmp"
    lr_rfa_pids=""
    for lr_rfa_p in $RIVESTREAM_PROVIDERS; do
        (
            lr_rfa_resp=$(provider_fetch rivestream "$lr_rfa_p" "$1" "$2" "$3" "$4")
            [ -n "$lr_rfa_resp" ] && printf '%s\n' "$lr_rfa_resp" >>"$lr_rfa_tmp"
        ) &
        lr_rfa_pids="$lr_rfa_pids $!"
    done
    for lr_rfa_pid in $lr_rfa_pids; do wait "$lr_rfa_pid" 2>/dev/null; done
    cat "$lr_rfa_tmp"
    rm -f "$lr_rfa_tmp"
}
# Groups every {quality,url,source} block across all providers' responses
# into label<TAB>url rows, one per distinct label (best quality within each).
# Some providers (citadel) embed a real language directly in the quality
# string, e.g. "720p | Hindi" - that becomes the label. Everything without
# that hint (most providers, e.g. plain "HLS") gets pooled into one "Default"
# group instead of one row per provider/mirror, so a title with six identical
# unlabeled sources doesn't turn into six meaningless choices - only genuine,
# evidenced language differences produce more than one row.
rivestream_candidates() {
    printf '%s\n' "$1" | url_blocks | awk -v t="${2:-1080}" "$AWK_LIB"'
        {
            q = field($0, "quality"); u = field($0, "url")
            if (u == "") next
            label = "Default"
            if (match(q, /\|[ ]*[A-Za-z ]+$/)) {
                label = substr(q, RSTART + 1, RLENGTH - 1)
                gsub(/^[ ]+|[ ]+$/, "", label)
            }
            h = height(q, 1); d = dist(h, t)
            if (!(label in seen) || d < bd[label] || (d == bd[label] && h > bh[label])) {
                bd[label] = d; bh[label] = h; burl[label] = u; seen[label] = 1
            }
        }
        END { for (k in seen) print k "\t" burl[k] }
    ' | sort
}
rivestream_try() {
    lr_rt_all=$(rivestream_fetch_all "$1" "$2" "$3" "$4")
    [ -z "$lr_rt_all" ] && return 1
    lr_rt_candidates=$(rivestream_candidates "$lr_rt_all" "$lr_target")
    [ -z "$lr_rt_candidates" ] && return 1
    lr_rt_video=$(pick_audio_candidates "$lr_rt_candidates" "${audio_language:-english}")
    [ -z "$lr_rt_video" ] && return 1
    lr_rt_subs=$(collect_subs "$lr_rt_all" "$lr_lang")
    printf '%s\t%s\t%s\n' "$lr_rt_video" "https://www.rivestream.app/" "$lr_rt_subs"
    return 0
}
# every {quality,url} rivestream returns across all its providers, as a JSON array
rivestream_dump() {
    lr_rd_all=$(rivestream_fetch_all "$1" "$2" "$3" "$4")
    if [ -z "$lr_rd_all" ]; then
        printf '[]'
        return
    fi
    lr_rd_entries=$(emit_json "$lr_rd_all" "https://www.rivestream.app/")
    [ -n "$lr_rd_entries" ] && printf '[%s]' "$lr_rd_entries" || printf '[]'
}

# subtitles-only lookup (flikhub first, shows.st fallback), used when a
# backend (videasy, rivestream) returns no subs of its own
subs_fallback() {
    for lr_sf_src in cinefreak moviebox; do
        lr_sf_resp=$(provider_fetch flikhub "$lr_sf_src" "$1" "$2" "$3" "$4")
        [ -z "$lr_sf_resp" ] && continue
        lr_sf_out=$(collect_subs "$lr_sf_resp" "$lr_lang")
        [ -n "$lr_sf_out" ] && { printf '%s' "$lr_sf_out"; return 0; }
    done
    lr_sf_resp=$(provider_fetch showsst moviebox "$1" "$2" "$3" "$4")
    [ -n "$lr_sf_resp" ] && collect_subs "$lr_sf_resp" "$lr_lang"
}

# resolve_stream_bg <type> <id> [season] [episode]
# Same contract as resolve_stream, but run as a background job and waited on
# instead of captured via $(...) - that's what makes Ctrl-C dependable, and
# the guarantee doesn't survive a command substitution, so this sets
# $lr_resolve_out itself and callers must invoke it as a bare statement (never
# "$(resolve_stream_bg ...)"). See docs/implementation-notes.md.
# Sets: $lr_resolve_out. Returns resolve_stream's exit status.
resolve_stream_bg() {
    lr_rsb_file="$tmp_dir/resolve-out.$$"
    resolve_stream "$@" >"$lr_rsb_file" &
    lr_resolve_pid=$!
    wait "$lr_resolve_pid"
    lr_rsb_rc=$?
    lr_resolve_pid=""
    lr_resolve_out=$(cat "$lr_rsb_file" 2>/dev/null)
    rm -f "$lr_rsb_file"
    return "$lr_rsb_rc"
}

# Writes which backend won, for the "Now Playing ... via <backend>" note.
# resolve_stream runs in a background subshell (via resolve_stream_bg), so a
# plain shell variable wouldn't propagate back out - a file keyed off $$
# (which a POSIX subshell inherits from its parent) is the cheap way out.
resolved() {
    printf '%s\n' "$1" >"$tmp_dir/resolved-via.$$"
}

# --- backends ---
# One function per scraped backend, all with the same contract: print
# "url<TAB>referer<TAB>subs" on stdout and return 0, or return 1 so the
# dispatcher tries the next name in $provider_order. Read the lr_type/lr_id/
# lr_season/lr_episode/lr_target globals resolve_stream() sets.
# Always called bare, never in $(...): status()'s backgrounded spinner
# inherits stdout and would hold a capture pipe open.
backend_videasy() {
    if ! command -v node >/dev/null 2>&1; then
        status_note "Videasy skipped — node not found"
        return 1
    fi
    status "Videasy"
    lr_vy_dump=$(videasy_dump "$lr_type" "$lr_id" "$lr_season" "$lr_episode")
    lr_vy_candidates=$(quality_candidates "$lr_vy_dump" "$lr_target")
    [ -z "$lr_vy_candidates" ] && return 1
    # More than one entry tied on quality means several dub tracks with no
    # other way to tell them apart - filter out ones that don't match
    # $audio_language/$blocked_audio_languages instead of silently landing
    # on whichever the API listed first.
    if [ "$(printf '%s\n' "$lr_vy_candidates" | grep -c .)" -gt 1 ]; then
        lr_video=$(pick_audio_candidates "$(probe_audio_labels "$lr_vy_candidates")" "${audio_language:-english}")
    else
        lr_video=$(printf '%s\n' "$lr_vy_candidates" | head -1 | cut -f2)
    fi
    [ -z "$lr_video" ] && return 1
    lr_referer=$(json_field "$lr_vy_dump" "referer")
    lr_subs=$(printf '%s' "$lr_vy_dump" | sed -n 's/.*"subtitles":\[\(.*\)\].*/\1/p' | tr -d '"')
    [ -z "$lr_subs" ] && lr_subs=$(subs_fallback "$lr_type" "$lr_id" "$lr_season" "$lr_episode")
    url_alive "$lr_video" "$lr_referer" || return 1
    printf '%s\t%s\t%s\n' "$lr_video" "$lr_referer" "$lr_subs"
    resolved "Videasy"
}

backend_rivestream() {
    status "Rivestream"
    lr_out=$(rivestream_try "$lr_type" "$lr_id" "$lr_season" "$lr_episode")
    [ -z "$lr_out" ] && return 1
    lr_video=$(printf '%s' "$lr_out" | cut -f1)
    lr_referer=$(printf '%s' "$lr_out" | cut -f2)
    lr_subs=$(printf '%s' "$lr_out" | cut -f3)
    [ -z "$lr_subs" ] && lr_subs=$(subs_fallback "$lr_type" "$lr_id" "$lr_season" "$lr_episode")
    url_alive "$lr_video" "$lr_referer" || return 1
    printf '%s\t%s\t%s\n' "$lr_video" "$lr_referer" "$lr_subs"
    resolved "Rivestream"
}

# cinezo via flikhub proxy (direct file only, no HLS fallback)
backend_cinezo() {
    status "Cinezo"
    if [ "$lr_type" = "tv" ]; then lr_cinezo_sources=$CINEZO_TV_SOURCES; else lr_cinezo_sources=$CINEZO_MOVIE_SOURCES; fi
    lr_out=$(try_family flikhub "$lr_cinezo_sources" "" false "$lr_type" "$lr_id" "$lr_season" "$lr_episode")
    [ -n "$lr_out" ] && url_alive "$(printf '%s' "$lr_out" | cut -f1)" "$(printf '%s' "$lr_out" | cut -f2)" || return 1
    printf '%s\n' "$lr_out"
    resolved "Cinezo"
}

# vidlove / 111movies via api.shows.st (direct file, HLS fallback)
backend_vidlove() {
    status "Vidlove"
    lr_out=$(try_family showsst "$VIDLOVE_SOURCES" "https://player.vidlove.cc/" true "$lr_type" "$lr_id" "$lr_season" "$lr_episode")
    [ -n "$lr_out" ] && url_alive "$(printf '%s' "$lr_out" | cut -f1)" "$(printf '%s' "$lr_out" | cut -f2)" || return 1
    printf '%s\n' "$lr_out"
    resolved "Vidlove"
}

resolve_stream() {
    lr_type=$1
    lr_id=$2
    lr_season=${3:-1}
    lr_episode=${4:-1}
    lr_quality=${quality:-1080}
    lr_lang=$(printf '%s' "${subs_language:-english}" | tr '[:upper:]' '[:lower:]')
    lr_target=$(printf '%s' "$lr_quality" | tr -cd '0-9')
    [ -z "$lr_target" ] && lr_target=1080
    case "$lr_quality" in
        *4k* | *4K* | *2160*) lr_target=2160 ;;
    esac
    lr_ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36"
    lr_provider=${provider:-}
    rm -f "$tmp_dir/resolved-via.$$"
    case "$lr_provider" in
        videasy | rivestream | cinezo | vidlove | "") : ;;
        penguplay)
            if [ -z "$penguplay_url" ]; then
                # stderr, not notify: resolve_stream runs backgrounded with
                # stdout redirected to a capture file, so notify would vanish.
                printf '%s\n' "Error: provider penguplay needs penguplay_url set in the config file (e.g. penguplay_url=\"https://pengu.uk/<your-token>/manifest.json\")" >&2
                exit 1
            fi
            ;;
        aiostreams)
            if [ -z "$aiostreams_url" ]; then
                printf '%s\n' "Error: provider aiostreams needs aiostreams_url set in the config file (e.g. aiostreams_url=\"https://.../manifest.json\")" >&2
                exit 1
            fi
            ;;
        *)
            notify "Error" "5000" "" "unknown --provider '$lr_provider' (expected videasy, rivestream, cinezo, vidlove, penguplay or aiostreams)"
            exit 1
            ;;
    esac

    # Try each backend in $provider_order (config, best-first) until one
    # answers; --provider pins a single name and ignores the order. A stremio
    # addon with no url configured is skipped silently - it isn't set up.
    # Unknown names only warn, so a config listing a retired or
    # not-yet-released backend still plays something.
    lr_order=$provider_order
    [ -n "$lr_provider" ] && lr_order=$lr_provider
    for lr_p in $lr_order; do
        case "$lr_p" in
            penguplay | aiostreams)
                eval "lr_sb_url=\${${lr_p}_url:-}"
                [ -z "$lr_sb_url" ] && continue
                case "$lr_p" in
                    penguplay) lr_sb_label=PenguPlay ;;
                    *) lr_sb_label=AIOStreams ;;
                esac
                if stremio_addon_stream "$lr_sb_label" "$lr_sb_url"; then
                    resolved "$lr_sb_label"
                    clear_status
                    return 0
                fi
                ;;
            videasy | rivestream | cinezo | vidlove)
                if "backend_$lr_p"; then
                    clear_status
                    return 0
                fi
                ;;
            *) printf '%s\n' "Warning: unknown provider '$lr_p' in provider_order, skipping" >&2 ;;
        esac
    done

    clear_status
    return 1
}

# Shared by any stremio-addon backend (penguplay, aiostreams, ...): resolves
# stream+subtitle URLs from a manifest base URL for the current $lr_type/
# $lr_id/$lr_season/$lr_episode/$lr_target. Prints video<TAB><TAB>subs and
# returns 0 on a live stream, 1 otherwise (caller just tries the next addon).
stremio_addon_stream() {
    lr_sb_label=$1
    lr_sb_url=$2
    status "$lr_sb_label"
    lr_sb_base=${lr_sb_url%/manifest.json}
    if [ "$lr_type" = "tv" ]; then lr_sb_media=series; else lr_sb_media=movie; fi
    if [ "$lr_sb_media" = "series" ]; then
        lr_sb_id="tmdb:$lr_id:$lr_season:$lr_episode"
    else
        lr_sb_id="tmdb:$lr_id"
    fi
    lr_sb_resp=$(curl -sS --connect-timeout 5 -m 45 -A "$lr_ua" -H "Accept: application/json" \
        "$lr_sb_base/stream/$lr_sb_media/$lr_sb_id.json" 2>/dev/null)
    lr_sb_pairs=$(penguplay_pairs "$lr_sb_resp")
    # Every ranked url, best first - saved so a dead top pick can fall through
    # to the next source instead of re-resolving and getting the same one.
    printf '%s\n' "$lr_sb_pairs" | sed -nE 's/.*"url":"([^"]*)".*/\1/p' >"$lr_tmp/sb-cands.$$"
    # Primary pick stays the original single-best (first ranked pair); the
    # full list above is only for the download retry's fallthrough.
    lr_sb_candidates=$(quality_candidates "$(printf '%s\n' "$lr_sb_pairs" | head -1)" "$lr_target")
    [ -z "$lr_sb_candidates" ] &&
        lr_sb_candidates=$(printf '%s' "$lr_sb_resp" | grep -oE '"url": ?"[^"]+"' | head -1 | cut -d'"' -f4)
    [ -z "$lr_sb_candidates" ] && return 1
    if [ "$(printf '%s\n' "$lr_sb_candidates" | grep -c .)" -gt 1 ]; then
        lr_video=$(pick_audio_candidates "$(probe_audio_labels "$lr_sb_candidates")" "${audio_language:-english}")
    else
        lr_video=$(printf '%s\n' "$lr_sb_candidates" | head -1 | cut -f2)
    fi
    [ -z "$lr_video" ] && return 1
    # subs fetch fans out in parallel with the alive-check: the addon
    # aggregates several subtitle backends server-side and can lag the
    # stream response. skipped entirely under -n.
    lr_sb_subs=""
    lr_sb_subs_file=""
    if [ "$no_subs" != "true" ]; then
        lr_sb_subs_file="$lr_tmp/sb-subs.$$"
        curl -sS --connect-timeout 5 -m 12 -A "$lr_ua" -H "Accept: application/json" \
            "$lr_sb_base/subtitles/$lr_sb_media/$lr_sb_id.json" >"$lr_sb_subs_file" 2>/dev/null &
        lr_sb_subs_pid=$!
    fi
    # No url_alive here. That ranged GET exists to filter stale scraped
    # mirrors, but this URL came from the addon's own JSON milliseconds ago.
    # Worse, the probe GET burns the single-use token on pengu.uk-style
    # signed links, so the real download then gets 410 Gone.
    if [ -n "$lr_sb_subs_file" ]; then
        wait "$lr_sb_subs_pid" 2>/dev/null
        lr_sb_subs=$(collect_subs "$(cat "$lr_sb_subs_file" 2>/dev/null)" "$lr_lang")
        rm -f "$lr_sb_subs_file"
        [ -z "$lr_sb_subs" ] && lr_sb_subs=$(subs_fallback "$lr_type" "$lr_id" "$lr_season" "$lr_episode")
    fi
    printf '%s\t%s\t%s\n' "$lr_video" "" "$lr_sb_subs" # to resolve_stream's real stdout, not a pipe
    return 0
}

### Playback ###
# Polls mpv's IPC socket for time-pos/duration every 2s and writes the latest
# pair to $tmp_dir/pos. Runs in the background alongside mpv; the caller kills
# it once mpv exits. save_progress() and update_discord_presence() both read
# that file, so there's one source of truth for "how far in are we".
# See docs/implementation-notes.md.
poll_position() {
    # Loop on mpv being alive, not on the socket existing: mpv needs a moment
    # to create it, and the old check exited on the first iteration - so $pos
    # stayed empty and every save landed as 0%.
    while kill -0 "$mpv_pid" 2>/dev/null; do
        [ -S "$lobster_socket" ] || { sleep 1; continue; }
        # -w 1 is not optional: mpv keeps the connection open after replying,
        # and nc without a timeout blocks forever waiting for it to close.
        reply=$(printf '{"command":["get_property","time-pos"]}\n{"command":["get_property","duration"]}\n' | nc -U -w 1 "$lobster_socket" 2>/dev/null)
        pos=$(printf '%s\n' "$reply" | sed -n '1s/.*"data":\([0-9.]*\).*/\1/p')
        dur=$(printf '%s\n' "$reply" | sed -n '2s/.*"data":\([0-9.]*\).*/\1/p')
        [ -n "$pos" ] && [ -n "$dur" ] && printf '%s %s\n' "$pos" "$dur" >"$tmp_dir/pos"
        sleep 2
    done
}
# player_command - prints a standalone, pasteable command that plays the
# current stream: referer header, subtitle files, title, URL. Also the base of
# the mpv invocation in play(), which appends IPC/watch-later bits on top.
player_command() {
    lr_pc_title=$(printf '%s' "$displayed_title" | sed "s/'/'\\\\''/g")
    case "$player" in
        vlc)
            lr_pc="vlc '$video_link' --meta-title '$lr_pc_title'"
            [ -n "$referer" ] && lr_pc="$lr_pc --http-referrer='$referer'"
            if [ "$no_subs" != "true" ] && [ -n "$subs_links" ]; then
                lr_pc="$lr_pc --input-slave='$(printf '%s' "$subs_links" | sed 's/https\\:/https:/g; s/:\([^\/]\)/#\1/g')'"
            fi
            ;;
        iina | celluloid)
            lr_pc="$player --mpv-force-media-title='$lr_pc_title'"
            [ "$no_subs" != "true" ] && [ -n "$subs_links" ] && lr_pc="$lr_pc --mpv-sub-files='$subs_links'"
            lr_pc="$lr_pc '$video_link'"
            ;;
        mpv | mpv.exe)
            lr_pc="$player"
            [ -n "$resume_from" ] && lr_pc="$lr_pc --start='$resume_from'"
            if [ "$no_subs" != "true" ] && [ -n "$subs_csv" ]; then
                old_ifs=$IFS; IFS=','
                for sub in $subs_csv; do
                    lr_pc="$lr_pc --sub-file='$sub'"
                done
                IFS=$old_ifs
            fi
            [ -n "$referer" ] && lr_pc="$lr_pc --http-header-fields='Referer: $referer'"
            # some HLS segments have no file extension; let ffmpeg accept them.
            lr_pc="$lr_pc --demuxer-lavf-o=allowed_extensions=ALL"
            # Only when the config actually asked for a language: forcing
            # --alang=en on a remux with nine audio tracks picks the first
            # English-tagged one, which is usually a commentary track. With
            # no --alang, mpv plays the file's own default track.
            [ "$audio_language_set" = "true" ] && lr_pc="$lr_pc --alang=$(lang_code "$audio_language")"
            lr_pc="$lr_pc --force-media-title='$lr_pc_title' '$video_link'"
            ;;
        *) lr_pc="$player '$video_link'" ;;
    esac
    printf '%s\n' "$lr_pc"
}
play() {
    case "$player" in
        iina | celluloid)
            if [ "$player" = "iina" ]; then
                if [ -n "$subs_links" ]; then
                    iina --no-stdin --keep-running --mpv-sub-files="$subs_links" --mpv-force-media-title="$displayed_title" "$video_link"
                else
                    iina --no-stdin --keep-running --mpv-force-media-title="$displayed_title" "$video_link"
                fi
            else
                if [ -n "$subs_links" ]; then
                    celluloid --mpv-sub-files="$subs_links" --mpv-force-media-title="$displayed_title" "$video_link" 2>/dev/null
                else
                    celluloid --mpv-force-media-title="$displayed_title" "$video_link" 2>/dev/null
                fi
            fi
            ;;
        vlc)
            vlc_subs_links=$(printf '%s' "$subs_links" | sed 's/https\\:/https:/g; s/:\([^\/]\)/#\1/g')
            vlc "$video_link" --meta-title "$displayed_title" ${referer:+--http-referrer="$referer"} --input-slave="$vlc_subs_links"
            ;;
        mpv | mpv.exe)
            player_cmd=$(player_command)
            # nc is a soft dependency: with it, position/duration come live off
            # mpv's IPC socket; without it, a per-episode watch_later dir.
            # See docs/implementation-notes.md.
            have_ipc="false"
            if command -v nc >/dev/null 2>&1; then
                rm -f "$lobster_socket"
                player_cmd="$player_cmd --input-ipc-server='$lobster_socket'"
                have_ipc="true"
                watchlater_subdir="$watchlater_dir"
            else
                watchlater_subdir="$watchlater_dir/$media_id-$season-$episode"
                mkdir -p "$watchlater_subdir"
            fi
            case "$(uname -s)" in
                MINGW* | *Msys) player_cmd="$player_cmd --write-filename-in-watch-later-config --save-position-on-quit --quiet" ;;
                *) player_cmd="$player_cmd --watch-later-directory='$watchlater_subdir' --write-filename-in-watch-later-config --save-position-on-quit --quiet" ;;
            esac
            # eval is needed here to correctly re-split the quoted argument string above.
            eval "$player_cmd" &
            mpv_pid=$!

            : >"$tmp_dir/pos"
            poll_pid=""
            if [ "$have_ipc" = "true" ]; then
                poll_position &
                poll_pid=$!
            fi
            [ "$discord_presence" = "true" ] && update_discord_presence &

            wait "$mpv_pid" 2>/dev/null
            [ -n "$poll_pid" ] && kill "$poll_pid" 2>/dev/null
            save_progress
            ;;
        mpv_android) nohup am start --user 0 -a android.intent.action.VIEW -d "$video_link" -n is.xyz.mpv/.MPVActivity -e "title" "$displayed_title" >/dev/null 2>&1 & ;;
        iSH)
            if [ -n "$subs_links" ]; then
                first_sub=$(printf '%s' "$subs_links" | sed 's/https\\:/https:/g; s/:\([^\/]\)/#\1/g')
            else
                first_sub=""
            fi
            printf '\e]8;;vlc-x-callback://x-callback-url/stream?url=%s&sub=%s\a~ Tap to open VLC ~\e]8;;\a\n' "$video_link" "$first_sub"
            sleep 5
            ;;
        *yncpla*) nohup syncplay "$video_link" -- --force-media-title="$displayed_title" >/dev/null 2>&1 & ;;
        *) "$player" "$video_link" ;;
    esac
}
save_progress() {
    if [ "$have_ipc" = "true" ]; then
        read -r position total_duration <"$tmp_dir/pos" 2>/dev/null
    else
        # No IPC: mpv's own watch_later file, scoped to one episode's dir so
        # the single file inside is unambiguous.
        position=$(sed -n 's/^start=//p' "$watchlater_subdir"/* 2>/dev/null | tail -1)
        total_duration=0
    fi
    position=${position%.*}
    total_duration=${total_duration%.*}
    progress=0
    if [ -n "$position" ] && [ "$position" -gt 0 ] 2>/dev/null; then
        # Duration is only known over IPC. Without it the resume point is
        # still good - only the percentage is unknown - so keep the position
        # instead of throwing the whole thing away as 00:00:00.
        [ -n "$total_duration" ] && [ "$total_duration" -gt 0 ] 2>/dev/null &&
            progress=$((position * 100 / total_duration))
        position=$(printf "%02d:%02d:%02d" $((position / 3600)) $((position / 60 % 60)) $((position % 60)))
        notify "Stopped at" "5000" "$images_cache_dir/$title ($media_type)  $media_id.jpg" "$position"
    else
        position="00:00:00"
    fi
}
# dest_dir - $download_dir/<Title>/<Season Title> for a tv episode (so
# a season's files land together instead of flat in one folder), or plain
# $download_dir for a movie. Echoes the path and makes sure it exists.
dest_dir() {
    if [ "$media_type" = "tv" ]; then
        lr_dd_title=$(printf '%s' "$title" | tr -d ":/'")
        lr_dd_season=$(printf '%s' "$season_title" | tr -d ":/'")
        lr_dd_dir="$download_dir/$lr_dd_title/$lr_dd_season"
    else
        lr_dd_dir=$download_dir
    fi
    mkdir -p "$lr_dd_dir"
    printf '%s' "$lr_dd_dir"
}

# download_video <url> <display_title> <dest_dir> [progress_file]
# Saves the resolved stream (plus any subtitle URLs in $subs_csv) as an mkv.
# Tries custom_downloader, aria2c, yt-dlp, ffmpeg, then mpv --stream-record;
# subtitle language tags are best-effort, since resolve_stream hands back URLs
# and not per-language labels. Full order/rationale:
# docs/implementation-notes.md.
# progress_file is only passed by the parallel batch downloader below - a
# plain single -d download prints straight to the terminal like before.
download_video() {
    # Easy override point: define a `custom_downloader` shell function (or
    # drop a `custom_downloader` script on PATH) in lobster_config.sh and
    # it wins over everything below, no other plumbing needed - dest dir,
    # season folder, filename sanitizing etc. are already handled above
    # this point. Signature: custom_downloader <url> <dest_file> <referer>
    # <subs_csv> [progress_file]. Example:
    #   custom_downloader() { wget -O "$2" "$1"; }
    if command -v custom_downloader >/dev/null 2>&1; then
        custom_downloader "$1" "$3/$(printf '%s' "$2" | tr -d ":/'").mkv" "$referer" "$subs_csv" "$4" && return 0
    fi
    # Strip filesystem-unsafe chars plus anything that would break out of the
    # single-quoted eval below (an apostrophe in a title used to blow up
    # ffmpeg's eval with "unexpected EOF").
    safe_title=$(printf '%s' "$2" | tr -d ":/'")
    lr_dv_prog=$4
    # $referer is a global set by whoever resolved the stream (loop(),
    # download_episodes_parallel()) - same convention as $subs_csv. Without it
    # these CDNs 403 or serve a decoy .jpg "segment".
    lr_dv_ref_hdr=""
    [ -n "$referer" ] && lr_dv_ref_hdr="Referer: $referer"
    # downloader=aria2c gets used verbatim for a plain (non-HLS) direct file
    # and no subs to mux - aria2c can't segment/remux .m3u8 playlists, so
    # anything else still goes through ffmpeg below.
    if [ "$downloader" = "aria2c" ] && [ -z "$subs_csv" ] && ! printf '%s' "$1" | grep -q '\.m3u8'; then
        if command -v aria2c >/dev/null 2>&1; then
            lr_dv_aria_hdr=""
            [ -n "$lr_dv_ref_hdr" ] && lr_dv_aria_hdr="--header=$lr_dv_ref_hdr"
            if [ -n "$lr_dv_prog" ]; then
                aria2c -x16 -s16 -k1M --summary-interval=1 $lr_dv_aria_hdr --dir="$3" --out="$safe_title.mp4" "$1" >"$lr_dv_prog" 2>&1
            else
                aria2c -x16 -s16 -k1M $lr_dv_aria_hdr --dir="$3" --out="$safe_title.mp4" "$1"
            fi
            return
        fi
        notify "aria2c not found" "5000" "" "falling back to ffmpeg"
    fi

    # yt-dlp, when installed, is generally the most robust option out of
    # all of these for oddball/obfuscated HLS sources - preferred over
    # plain ffmpeg whenever it's available (an explicit downloader=aria2c
    # above still wins for a plain direct file, that's a deliberate choice).
    if command -v yt-dlp >/dev/null 2>&1; then
        lr_dv_yt_hdr=""
        [ -n "$referer" ] && lr_dv_yt_hdr="--add-header Referer:$referer"
        lr_dv_yt_dest="$3/$safe_title.mkv"
        # -N/--concurrent-fragments: fetch segments in parallel, same "as
        # fast as possible" spirit as aria2c's -x16/-s16 above.
        if [ -n "$lr_dv_prog" ]; then
            # --progress-template gives a stable, greppable line (see
            # dl_percent); the "download:" prefix is a type selector and is
            # consumed, so the marker has to follow it. PYTHONUNBUFFERED stops
            # Python block-buffering the progress file into looking frozen.
            PYTHONUNBUFFERED=1 yt-dlp --no-warnings --newline -N 16 --concurrent-fragments 16 --merge-output-format mkv \
                --progress-template "download:lobster-pct:%(progress._percent_str)s" \
                $lr_dv_yt_hdr -o "$lr_dv_yt_dest" "$1" >"$lr_dv_prog" 2>&1
        else
            yt-dlp --no-warnings -N 16 --concurrent-fragments 16 --merge-output-format mkv \
                $lr_dv_yt_hdr -o "$lr_dv_yt_dest" "$1"
        fi
        if [ $? -eq 0 ]; then
            # yt-dlp doesn't know about $subs_csv, so drop them as sidecar
            # files - mpv/vlc auto-load a same-basename subtitle.
            if [ -n "$subs_csv" ] && [ "$no_subs" != "true" ]; then
                lr_dv_si=0
                old_ifs=$IFS
                IFS=','
                for sub in $subs_csv; do
                    lr_dv_si=$((lr_dv_si + 1))
                    curl -sS ${referer:+-H "Referer: $referer"} -o "$3/$safe_title.${subs_language}_$lr_dv_si.vtt" "$sub"
                done
                IFS=$old_ifs
            fi
            return 0
        fi
        # ffmpeg reuses this path via -progress, which truncates it on open -
        # keep yt-dlp's own failure output or every failure gets blamed on
        # ffmpeg.
        [ -n "$lr_dv_prog" ] && cp "$lr_dv_prog" "$lr_dv_prog.ytdlp-err" 2>/dev/null
        notify "yt-dlp failed" "5000" "" "falling back to ffmpeg"
    fi

    dest="$3/$safe_title.mkv"
    sub_inputs=""
    maps="-map 0:v -map 0:a"
    meta=""
    lr_dv_ffhdr=""
    [ -n "$lr_dv_ref_hdr" ] && lr_dv_ffhdr="-headers '$lr_dv_ref_hdr\r\n'"

    if [ -n "$subs_csv" ] && [ "$no_subs" != "true" ]; then
        i=0
        old_ifs=$IFS
        IFS=','
        for sub in $subs_csv; do
            i=$((i + 1))
            sub_inputs="$sub_inputs $lr_dv_ffhdr -i '$sub'"
            maps="$maps -map $i"
            meta="$meta -metadata:s:s:$((i - 1)) language=${subs_language}_$i"
        done
        IFS=$old_ifs
    fi

    lr_dv_stats="-stats"
    # ponytail: no % for ffmpeg episodes in batch mode - that needed an extra
    # ffprobe duration hit per episode against a request-quota'd host, for a
    # cosmetic number. Spinner only. See docs/implementation-notes.md.
    [ -n "$lr_dv_prog" ] && lr_dv_stats="-nostats -progress '$lr_dv_prog'"
    # In batch mode ffmpeg's error text (often a multi-hundred-char signed URL
    # per line) goes to a sibling .err file, so it can't stomp through the live
    # progress block. A plain single -d download still prints to the terminal.
    lr_dv_errredir=""
    [ -n "$lr_dv_prog" ] && lr_dv_errredir="2>>'$lr_dv_prog.err'"
    # shellcheck disable=SC2086
    eval ffmpeg -loglevel error $lr_dv_stats $lr_dv_ffhdr -i "'$1'" $sub_inputs $maps -c:v copy -c:a copy -c:s srt $meta "'$dest'" $lr_dv_errredir && return

    # ponytail: last resort for mirrors that disguise HLS segments with a
    # non-media extension, which ffmpeg's demuxer hard-rejects and mpv doesn't
    # care about. --stream-record copies without decoding, so it's not a
    # re-encode; no subtitle muxing on this path, and the output is MPEG-TS
    # wearing an .mkv name. See docs/implementation-notes.md.
    command -v mpv >/dev/null 2>&1 || return 1
    lr_dv_mpv_hdr=""
    [ -n "$lr_dv_ref_hdr" ] && lr_dv_mpv_hdr="--http-header-fields=$lr_dv_ref_hdr"
    mpv --no-config --really-quiet --untimed --vo=null --ao=null \
        $lr_dv_mpv_hdr "$1" --stream-record="$dest"
}

### History ###
# History rows are 9 tab-separated fields, movie and tv alike (season/
# episode/episode_title stay empty for movies; progress_pct is only read back
# for the continue list's progress bar). A fixed shape means lookups never
# have to guess the row layout the way the old regex-based picker did.
#   title \t position \t type \t tmdb_id \t season \t episode \t episode_title \t poster_url \t progress_pct
# Reads the history file and emits one row per entry, most recently watched
# first, with a ready-to-display first column (title · SxxEyy · progress bar)
# prepended to the raw 9 history fields. menu() shows only column 1; the
# caller re-parses the raw fields out of the returned row.
# All of it in awk, including the █/░ bar: `read` splits on IFS *whitespace*
# even when IFS is set to a single tab, so consecutive tabs collapse and every
# movie row (empty season/episode/episode_title) parsed one field short -
# the poster URL landed in $season and the percentage was always missing.
history_rows_for_menu() {
    [ -s "$histfile" ] || return 0
    # Rows are listed newest (appended last) first.
    awk -F'\t' 'BEGIN { OFS = "\t" }
        { a[NR] = $0 }
        END {
            for (i = NR; i >= 1; i--) {
                n = split(a[i], f, OFS)
                pct = (f[9] ~ /^[0-9]+$/) ? f[9] + 0 : 0
                if (pct > 100) pct = 100
                bar = ""
                for (j = 0; j < 10; j++) bar = bar (j < int(pct / 10) ? "█" : "░")
                if (f[3] == "tv")
                    disp = sprintf("%s  S%02dE%02d  %s %d%%  %s", f[1], f[5], f[6], bar, pct, f[2])
                else
                    disp = sprintf("%s  %s %d%%  %s", f[1], bar, pct, f[2])
                print disp, f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], pct
            }
        }' "$histfile"
}
# Parses a history_rows_for_menu (display-prepended) row back into the
# globals the rest of the script expects.
parse_history_row() {
    title=$(printf '%s' "$1" | cut -f2)
    resume_from=$(printf '%s' "$1" | cut -f3)
    media_type=$(printf '%s' "$1" | cut -f4)
    media_id=$(printf '%s' "$1" | cut -f5)
    season=$(printf '%s' "$1" | cut -f6)
    episode=$(printf '%s' "$1" | cut -f7)
    episode_title=$(printf '%s' "$1" | cut -f8)
    image_link=$(printf '%s' "$1" | cut -f9)
}
# Parses a raw histfile row (9 fields, no display prefix) - used by the
# image-preview continue path and --last, which read the file directly.
parse_history_raw() {
    title=$(printf '%s' "$1" | cut -f1)
    resume_from=$(printf '%s' "$1" | cut -f2)
    media_type=$(printf '%s' "$1" | cut -f3)
    media_id=$(printf '%s' "$1" | cut -f4)
    season=$(printf '%s' "$1" | cut -f5)
    episode=$(printf '%s' "$1" | cut -f6)
    episode_title=$(printf '%s' "$1" | cut -f7)
    image_link=$(printf '%s' "$1" | cut -f8)
}
history_check() {
    resume_from=""
    if [ -f "$histfile" ]; then
        resume_from=$(awk -F'\t' -v id="$media_id" -v type="$media_type" -v s="$season" -v e="$episode" \
            '$3 == type && $4 == id && $5 == s && $6 == e { print $2; exit }' "$histfile")
    fi
    poster="$images_cache_dir/$title ($media_type)  $media_id.jpg"
    if [ -n "$resume_from" ]; then
        notify "Resuming from" "5000" "$poster" "$resume_from"
    else
        notify "Now Playing" "5000" "$poster" "$displayed_title${lr_resolved_via:+ · via $lr_resolved_via}"
    fi
}
history_delete() {
    awk -F'\t' -v id="$media_id" -v type="$media_type" \
        '!($3 == type && $4 == id)' "$histfile" >"$histfile.tmp" && mv "$histfile.tmp" "$histfile"
}
# delete_history_row <menu-row> - removes one entry given a
# history_rows_for_menu row (type=field4, id=field5).
delete_history_row() {
    lr_dhr_type=$(printf '%s' "$1" | cut -f4)
    lr_dhr_id=$(printf '%s' "$1" | cut -f5)
    awk -F'\t' -v id="$lr_dhr_id" -v type="$lr_dhr_type" \
        '!($3 == type && $4 == id)' "$histfile" >"$histfile.tmp" && mv "$histfile.tmp" "$histfile"
}
history_upsert() {
    row=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
        "$title" "$position" "$media_type" "$media_id" "$season" "$episode" "$episode_title" "$image_link" "${progress:-0}")
    awk -F'\t' -v id="$media_id" -v type="$media_type" -v row="$row" '
        BEGIN { OFS = "\t" }
        { if ($3 == type && $4 == id) { print row; found = 1 } else { print } }
        END { if (!found) print row }
    ' "$histfile" >"$histfile.tmp" && mv "$histfile.tmp" "$histfile"
}
history_save() {
    [ -f "$histfile" ] || : >"$histfile"
    if [ "$media_type" = "tv" ] && [ "$progress" -gt 90 ]; then
        tmdb_next_episode
        if [ -n "$next_episode" ]; then
            episode_title=$(printf '%s' "$next_episode" | cut -f2)
            episode=$(printf '%s' "$next_episode" | cut -f1)
            position="00:00:00"
            progress=0
            history_upsert
            notify "Updated to next episode" "5000" "" "$episode_title"
        else
            history_delete
            notify "Completed" "5000" "" "$title"
        fi
    elif [ "$progress" -gt 90 ]; then
        history_delete
        notify "Removed from history" "5000" "" "$title"
    else
        history_upsert
        notify "Saved to history" "5000" "$images_cache_dir/$title ($media_type)  $media_id.jpg" "$title"
    fi
}
history_pick() {
    # Reset per call: this function is re-entered from the home menu, and a
    # stale warning would outlive the condition that set it.
    lr_hp_warn=""
    # lr_continue_back: "home" returns to the home menu on empty/back (set by
    # choose_home); anything else (the -c flag) exits like it always did.
    # Three distinct states so the continue prompt tells the truth: history
    # disabled, enabled-but-empty, or real entries to pick from.
    if [ "$history" != "true" ]; then
        lr_hp_warn="history is disabled - set history=true in the config to enable continue"
    elif [ ! -s "$histfile" ]; then
        lr_hp_warn="no history yet - watch something first"
    fi
    if [ -n "$lr_hp_warn" ]; then
        if [ "$lr_continue_back" = "home" ]; then
            # Shown as the picker prompt itself so it's actually visible (a
            # notify line gets wiped the moment the next picker takes over
            # the screen).
            printf 'Back\n' | menu "continue watching: $lr_hp_warn"
            STATE="HOME"
        else
            notify "History" "6000" "" "$lr_hp_warn"
            exit 1
        fi
        return
    fi
    if [ "$image_preview" = "true" ]; then
        test -d "$images_cache_dir" || mkdir -p "$images_cache_dir"
        if [ "$use_external_menu" = "true" ]; then
            mkdir -p "$tmp_dir/applications/"
            [ -L "$applications" ] || ln -sf "$tmp_dir/applications/" "$applications"
        fi
        # Same rows, same order and same labels as the text continue list -
        # column 1 there is already "title  SxxEyy  progress  position".
        thumb_input=$(history_rows_for_menu | awk -F'\t' 'BEGIN{OFS="\t"} $9 != "" {print $9, $5, $4, $2, $1}')
        download_thumbnails "$thumb_input"
        select_desktop_entry ""
        rc=$?
        if [ "$rc" -eq "$BACK_CODE" ] || [ -z "$choice" ]; then
            [ "$lr_continue_back" = "home" ] && { STATE="HOME"; return; }
            exit 0
        fi
        row=$(awk -F'\t' -v id="$media_id" -v type="$media_type" '$3 == type && $4 == id {print; exit}' "$histfile")
        [ -z "$row" ] && { [ "$lr_continue_back" = "home" ] && { STATE="HOME"; return; } || exit 0; }
        parse_history_raw "$row"
    else
        while :; do
            row=$(history_rows_for_menu | menu "Continue: " "1" "" "ctrl-d")
            rc=$?
            if [ "$rc" -eq "$DELETE_CODE" ] && [ -n "$row" ]; then
                delete_history_row "$row"
                [ -s "$histfile" ] || { [ "$lr_continue_back" = "home" ] && { STATE="HOME"; return; } || exit 0; }
                continue
            fi
            if [ "$rc" -eq "$BACK_CODE" ] || [ -z "$row" ]; then
                [ "$lr_continue_back" = "home" ] && { STATE="HOME"; return; }
                exit 0
            fi
            parse_history_row "$row"
            break
        done
    fi
    keep_running="true"
    STATE="PLAY"
}
# --last: resume the most recently watched entry directly, no picker.
history_last() {
    if [ "$history" != "true" ]; then
        notify "History" "6000" "" "history is disabled - set history=true in the config to enable continue"
        exit 1
    fi
    if [ ! -s "$histfile" ]; then
        notify "History" "6000" "" "no history yet - watch something first"
        exit 1
    fi
    parse_history_raw "$(tail -n 1 "$histfile")"
    keep_running="true"
    STATE="PLAY"
}
history_clear() {
    : >"$histfile"
    notify "History cleared"
    exit 0
}

### Discord rich presence ###
set_activity() {
    len=${#1}
    printf "\\001\\000\\000\\000"
    # Little-endian 4-byte length. Shift the *original* length each time and
    # mask to one byte - shifting an already-shifted $len accumulates
    # (0/8/24/48) and mangles every payload longer than 255 bytes.
    for i in 0 8 16 24; do
        # shellcheck disable=SC2059
        printf "\\$(printf "%03o" "$(((len >> i) & 255))")"
    done
    printf "%s" "$1"
}
update_rich_presence() {
    state=$1
    payload='{"cmd":"SET_ACTIVITY","args":{"pid":"786","activity":{"state":"'"$state"'","details":"'"$displayed_title"'","assets":{"large_image":"'"$image_link"'","large_text":"'"$title"'","small_image":"'"$small_image"'","small_text":"powered by lobster"}}},"nonce":"'"$(date)"'"}'
    if [ ! -e "$handshook" ]; then
        handshake='{"v":1,"client_id":"'$presence_client_id'"}'
        printf "\\000\\000\\000\\000\\$(printf "%03o" "${#handshake}")\\000\\000\\000%s" "$handshake" >"$presence"
        sleep 2
        touch "$handshook"
    fi
    set_activity "$payload" >"$presence"
}
update_discord_presence() {
    [ -z "$image_link" ] && image_link="$(awk -F'\t' -v id="$media_id" '$1 == id {print $2}' "$tmp_dir/image_links")"
    sleep 2
    # Reads the same $tmp_dir/pos file poll_position() writes, instead of
    # polling mpv's IPC socket a second time on its own cadence. Bounded by
    # mpv still running, so this can't outlive it the way the old unconditional
    # while-loop with no exit path in the no-socket branch could.
    while kill -0 "$mpv_pid" 2>/dev/null; do
        read -r pos dur <"$tmp_dir/pos" 2>/dev/null
        pos=${pos%.*}; dur=${dur%.*}
        if [ -n "$pos" ] && [ -n "$dur" ]; then
            cur=$(printf "%02d:%02d:%02d" $((pos / 3600)) $((pos % 3600 / 60)) $((pos % 60)))
            tot=$(printf "%02d:%02d:%02d" $((dur / 3600)) $((dur % 3600 / 60)) $((dur % 60)))
            update_rich_presence "$(printf "%s / %s" "$cur" "$tot")" &
        else
            update_rich_presence "Watching" &
        fi
        sleep 2
    done
    rpc_cleanup
}

### Self-update ###
update_script() {
    which_lobster="$(command -v lobster)"
    if [ -z "$which_lobster" ]; then
        notify "Can't find lobster in PATH"
        exit 1
    fi
    update=$(curl -s "https://raw.githubusercontent.com/justchokingaround/lobster/main/lobster.sh" || exit 1)
    update="$(printf '%s\n' "$update" | diff -u "$which_lobster" -)"
    if [ -z "$update" ]; then
        notify "Script is up to date :)"
    elif printf '%s\n' "$update" | patch "$which_lobster" -; then
        notify "Script has been updated!"
    else
        notify "Can't update for some reason!"
    fi
    exit 0
}

# spin_frame <n> - nth (mod 10) braille spinner frame, same set status()
# already uses for the "Resolving via ..." line, so the look matches.
spin_frame() {
    lr_sf_i=$((($1) % 10 + 1))
    set -- ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏
    eval "printf '%s' \"\${$lr_sf_i}\""
}

# dl_percent <progress_file> - best-effort percentage, auto-detecting
# which downloader wrote it: yt-dlp's --progress-template output
# ("lobster-pct: NN.N%") or aria2c's own summary line ("(NN%)"). ffmpeg has
# no percentage here on purpose - see download_video's note on the dropped
# duration probe. Empty output if nothing matches yet/at all - callers treat
# that as "unknown", not "0%".
# dl_fail_reason <progress_file> - a short (<=80 char), single-line hint
# for why an episode's download failed, pulled from ffmpeg's sibling .err
# file or a yt-dlp "ERROR:" line already captured in the progress file.
# Truncated hard: the whole point is not re-dumping a 300-char signed URL
# into the terminal, just enough to tell "403" from "rate limited" apart.
dl_fail_reason() {
    lr_dfr_line=""
    # yt-dlp's own reason first (see download_video's ytdlp-err copy) - it
    # tends to be the most specific (e.g. an actual "HTTP Error 429"), and
    # is what actually ran first if both it and ffmpeg were tried.
    [ -s "$1.ytdlp-err" ] && lr_dfr_line=$(grep -i '^ERROR:' "$1.ytdlp-err" | tail -1)
    # tail -1, not the first match: ffmpeg's most specific line (the actual
    # HTTP status/reason) is usually its last one, after the generic
    # "Error opening input: ..." lines above it.
    [ -z "$lr_dfr_line" ] && [ -s "$1.err" ] && lr_dfr_line=$(grep -i 'error\|forbidden\|denied\|[0-9][0-9][0-9]' "$1.err" | tail -1)
    [ -z "$lr_dfr_line" ] && [ -s "$1" ] && lr_dfr_line=$(grep -i '^ERROR:' "$1" | tail -1)
    printf '%s' "$lr_dfr_line" | cut -c1-80
}

dl_percent() {
    [ -s "$1" ] || return
    lr_dpc_tail=$(tail -c 2000 "$1" 2>/dev/null)
    case "$lr_dpc_tail" in
        *'lobster-pct:'*)
            # " 40.1%" - right-aligned, so allow the leading spaces, and
            # take the leading integer part of the figure.
            printf '%s' "$lr_dpc_tail" | grep -oE 'lobster-pct: *[0-9.]+%' | tail -1 | grep -oE '[0-9]+' | head -1
            ;;
        *'SIZE:'*'DL:'*)
            printf '%s' "$lr_dpc_tail" | grep -oE '\([0-9]+%\)' | tail -1 | tr -d '()%'
            ;;
    esac
}

# dl_line <label> <pct-or-empty> <spin-char-or-empty> <cols> <outcome>
# - one formatted, width-clamped status line for either a still-running
# episode (spinner + %) or one that has already FINISHED but hasn't had its
# official in-order turn to be flushed yet.
#
# That second case needs <outcome> (the contents of the episode's status
# file). It used to render a hardcoded "✔ ... (queued)" for it, which was
# wrong twice over: "queued" reads as "hasn't started" when the episode is
# in fact done, and an episode that FAILED still got a ✔ until the moment
# it flushed, then abruptly flipped to ✘. Show what actually happened.
# Clamping to terminal width
# is what makes multi-line cursor-up redraw safe: a wrapped line is exactly
# what broke the very first version of this feature. Truncating the fully
# color-coded string is byte/char based, not display-width based, so on a
# rare multi-byte boundary it may cut a hair short - never overflows though,
# which is the only thing that actually matters for the cursor math.
dl_line() {
    if [ -n "$3" ]; then
        if [ -n "$2" ]; then
            lr_dl_text=$(printf '\033[36m%s\033[0m %s \033[2m(%s%%)\033[0m' "$3" "$1" "$2")
        else
            lr_dl_text=$(printf '\033[36m%s\033[0m %s' "$3" "$1")
        fi
    elif [ "$5" != "ok" ]; then
        lr_dl_text=$(printf '\033[2m✘ %s (failed)\033[0m' "$1")
    else
        lr_dl_text=$(printf '\033[2m✔ %s (done)\033[0m' "$1")
    fi
    printf '%s' "$lr_dl_text" | cut -c "1-$4"
}

# render_downloads <manifest_file> - a season-progress header line plus
# one live line per still-in-flight episode, all redrawn together every
# ~150ms. The block only ever shrinks (rows leave from the top, strictly in
# manifest/episode order, once they're done AND every row above them is also
# done) - see the comment inline below for why that makes the cursor-up
# math safe despite episodes actually finishing in any order underneath.
render_downloads() {
    [ "$json_output" = "true" ] && lr_rd_quiet="true"
    [ "$use_external_menu" = "true" ] && lr_rd_quiet="true"
    [ "$lr_rd_quiet" = "true" ] && { wait; return; }
    lr_rd_manifest=$1
    lr_rd_total=$(wc -l <"$lr_rd_manifest" | tr -d ' ')
    lr_rd_cols=$(tput cols 2>/dev/null)
    case "$lr_rd_cols" in '' | *[!0-9]*) lr_rd_cols=80 ;; esac
    lr_rd_cols=$((lr_rd_cols - 1))
    [ "$lr_rd_cols" -lt 20 ] && lr_rd_cols=20

    # Rows only ever leave the live block from the top, in strict episode
    # order, once flushed to permanent scrollback below - so the block's
    # height (1 season-header line + one per still-unflushed episode) only
    # ever shrinks by exactly however many rows get flushed in a given
    # tick. That's what makes "cursor up by last frame's height, then
    # redraw this frame's (possibly smaller) height" always land correctly.
    lr_rd_next=1
    lr_rd_prev_h=0
    lr_rd_frame=0
    printf '\033[?25l' >&2
    while [ "$lr_rd_next" -le "$lr_rd_total" ]; do
        [ "$lr_rd_prev_h" -gt 0 ] && printf '\033[%dA' "$lr_rd_prev_h" >&2

        # Flush every contiguous already-finished row starting at the top
        # of the block - permanent scrolling lines, never touched again.
        while [ "$lr_rd_next" -le "$lr_rd_total" ]; do
            lr_rd_row=$(sed -n "${lr_rd_next}p" "$lr_rd_manifest")
            lr_rd_status=$(printf '%s' "$lr_rd_row" | cut -f3)
            [ -f "$lr_rd_status" ] || break
            lr_rd_label=$(printf '%s' "$lr_rd_row" | cut -f1)
            if [ "$(cat "$lr_rd_status")" = "ok" ]; then
                printf '\33[2K\r\033[1;32m✔\033[0m %s\n' "$lr_rd_label" >&2
            else
                lr_rd_reason=$(dl_fail_reason "$(printf '%s' "$lr_rd_row" | cut -f2)")
                if [ -n "$lr_rd_reason" ]; then
                    printf '\33[2K\r\033[1;31m✘\033[0m %s \033[2m(failed: %s)\033[0m\n' "$lr_rd_label" "$lr_rd_reason" >&2
                else
                    printf '\33[2K\r\033[1;31m✘\033[0m %s \033[2m(failed)\033[0m\n' "$lr_rd_label" >&2
                fi
            fi
            lr_rd_next=$((lr_rd_next + 1))
        done
        [ "$lr_rd_next" -gt "$lr_rd_total" ] && break

        # Season %: a finished episode counts as 100 (or 0 if it failed -
        # already stopped, no more progress coming), an in-flight one
        # counts its own known percent (0 if not known yet) - averaged
        # over every episode in the season, not just the ones done so far.
        lr_rd_sum=0
        while IFS= read -r lr_rd_r2; do
            [ -z "$lr_rd_r2" ] && continue
            lr_rd_p2=$(printf '%s' "$lr_rd_r2" | cut -f2)
            lr_rd_s2=$(printf '%s' "$lr_rd_r2" | cut -f3)
            if [ -f "$lr_rd_s2" ]; then
                [ "$(cat "$lr_rd_s2")" = "ok" ] && lr_rd_sum=$((lr_rd_sum + 100))
            else
                lr_rd_pct2=$(dl_percent "$lr_rd_p2")
                case "$lr_rd_pct2" in '' | *[!0-9]*) lr_rd_pct2=0 ;; esac
                lr_rd_sum=$((lr_rd_sum + lr_rd_pct2))
            fi
        done <"$lr_rd_manifest"
        lr_rd_season_pct=$((lr_rd_sum / lr_rd_total))
        lr_rd_char=$(spin_frame "$lr_rd_frame")
        printf '\33[2K\r\033[36m%s\033[0m \033[2mSeason\033[0m \033[1;36m%s%%\033[0m \033[2m| %s/%s done\033[0m\n' \
            "$lr_rd_char" "$lr_rd_season_pct" "$((lr_rd_next - 1))" "$lr_rd_total" >&2

        # One line per still-unflushed episode - already-finished-but-not-
        # yet-its-turn ones show a dim "queued" checkmark instead of a
        # spinner, so finishing out of order is still visible immediately.
        lr_rd_i=$lr_rd_next
        while [ "$lr_rd_i" -le "$lr_rd_total" ]; do
            lr_rd_row=$(sed -n "${lr_rd_i}p" "$lr_rd_manifest")
            lr_rd_label=$(printf '%s' "$lr_rd_row" | cut -f1)
            lr_rd_prog=$(printf '%s' "$lr_rd_row" | cut -f2)
            lr_rd_status=$(printf '%s' "$lr_rd_row" | cut -f3)
            if [ -f "$lr_rd_status" ]; then
                printf '\33[2K\r%s\n' "$(dl_line "$lr_rd_label" "" "" "$lr_rd_cols" "$(cat "$lr_rd_status" 2>/dev/null)")" >&2
            else
                lr_rd_pct=$(dl_percent "$lr_rd_prog")
                lr_rd_spin=$(spin_frame "$lr_rd_frame")
                printf '\33[2K\r%s\n' "$(dl_line "$lr_rd_label" "$lr_rd_pct" "$lr_rd_spin" "$lr_rd_cols")" >&2
            fi
            lr_rd_i=$((lr_rd_i + 1))
        done

        lr_rd_prev_h=$((1 + lr_rd_total - lr_rd_next + 1))
        lr_rd_frame=$((lr_rd_frame + 1))
        sleep 0.15
    done
    printf '\033[?25h' >&2
}

# download_episodes_parallel <episode-rows> - resolves+downloads every row
# at once (each in its own subshell so per-episode globals like $episode or
# $video_link don't race each other) and drives the animated table above
# while they run. Iterates via a redirected file, not a pipe, so the jobs
# stay children of *this* shell and the final `wait` actually waits on them.
# Capped by $download_concurrency and spaced by $download_pace (see below).
download_episodes_parallel() {
    lr_dp_rows_file="$tmp_dir/dl-rows.$$"
    printf '%s\n' "$1" >"$lr_dp_rows_file"
    # Saved before the positional params get repurposed as the pid window.
    lr_dp_is_retry=$2
    lr_dp_count=$(grep -c . "$lr_dp_rows_file")
    lr_dp_dest_dir=$(dest_dir)
    notify "Downloading" "5000" "" "$lr_dp_count episode(s) of $title to $lr_dp_dest_dir"
    lr_dp_quiet="false"
    [ "$json_output" = "true" ] && lr_dp_quiet="true"
    [ "$use_external_menu" = "true" ] && lr_dp_quiet="true"

    # Resolve+launch, one episode at a time, in order - not two separate
    # phases anymore. A download starts the moment ITS OWN resolve succeeds,
    # instead of waiting for every other episode to resolve first, so
    # episode 1 is already transferring while episode 2 is still being
    # looked up. Resolving itself still has to stay sequential though:
    # resolve_stream/try_family/etc. key scratch files off "$$", and
    # POSIX "$$" does NOT change inside a "(...) &" subshell of the same
    # process - only across a genuinely separate process - so resolving
    # several of these concurrently would silently corrupt each other's
    # temp files (an earlier version of this hit exactly that). Tried
    # spawning each resolve as its own real `sh $0 ...` process instead
    # (genuinely distinct $$, no collision) - technically worked, but N of
    # those run N full multi-provider probe sequences (their own curl/node
    # calls) at once, which hammered CPU/network for no real win on what's
    # just a small metadata lookup. Not worth it. Only the actual video
    # transfer below is parallel.
    # The manifest is built for EVERY episode up front, before a single one
    # starts, purely so the live display can be running the whole time. It
    # used to be appended to as each episode resolved, which meant the
    # renderer could only be started after the launch loop had finished -
    # and since that loop blocks on a full concurrency window, "after the
    # loop" is "after nearly every download already finished". The table
    # therefore had nothing left to animate and just dumped the final
    # ✔/✘ list, which is why a season download showed no progress at all.
    # Rows that haven't resolved yet simply have an empty progress file and
    # render as a spinner with no percentage.
    lr_dp_manifest="$tmp_dir/dl-manifest.$$"
    : >"$lr_dp_manifest"
    while IFS= read -r lr_dp_row; do
        [ -z "$lr_dp_row" ] && continue
        lr_dp_ep=$(printf '%s' "$lr_dp_row" | cut -f1)
        lr_dp_title=$(printf '%s' "$lr_dp_row" | cut -f2)
        lr_dp_prog="$tmp_dir/dlprog.$$.$lr_dp_ep"
        lr_dp_status="$tmp_dir/dlstatus.$$.$lr_dp_ep"
        : >"$lr_dp_prog"
        rm -f "$lr_dp_prog.err" "$lr_dp_prog.ytdlp-err" "$lr_dp_status"
        printf '%s\t%s\t%s\n' "Eps $lr_dp_ep: $lr_dp_title" "$lr_dp_prog" "$lr_dp_status" >>"$lr_dp_manifest"
    done <"$lr_dp_rows_file"

    # Renderer runs alongside the resolve+launch loop below, so it owns the
    # terminal for the whole run. That's also why the loop no longer prints
    # its own per-episode "→ Resolving"/"✔ resolved" lines: they scrolled
    # straight through the block the renderer was redrawing in place.
    # A resolve failure still shows up - it writes a status file, and the
    # renderer flushes it as a ✘ row like any other failure.
    lr_dp_render_pid=""
    if [ "$lr_dp_quiet" != "true" ]; then
        render_downloads "$lr_dp_manifest" &
        lr_dp_render_pid=$!
        # Mutes resolve_stream's own "Resolving via ..." spinner for the
        # duration - see status(). Restored once the table is finished.
        lr_no_status=true
    fi

    lr_dp_idx=0
    # $download_concurrency-wide sliding window of in-flight downloads,
    # tracked as this function's own positional params ($1 was already
    # consumed above, safe to repurpose). A provider CDN 4xx's/rate-limits
    # a burst of a dozen simultaneous connections - launching all of them
    # at once isn't "as fast as possible", it's just a fast way to get
    # throttled. Resolving stays uncapped/sequential regardless (see above).
    set --
    lr_dp_last_launch=0
    while IFS= read -r lr_dp_row; do
        [ -z "$lr_dp_row" ] && continue
        lr_dp_idx=$((lr_dp_idx + 1))
        lr_dp_ep=$(printf '%s' "$lr_dp_row" | cut -f1)
        lr_dp_title=$(printf '%s' "$lr_dp_row" | cut -f2)
        lr_dp_label="Eps $lr_dp_ep: $lr_dp_title"

        # $download_pace: don't even start the NEXT resolve (let alone its
        # download) until this much time has passed since the last one
        # started - a requests-per-time-window quota is about cumulative
        # rate, not concurrency, so the concurrency cap above can't fix it
        # on its own. One-second (whole-second `date`) resolution is coarse
        # but plenty for a several-second window like this.
        lr_dp_now=$(date +%s)
        lr_dp_since=$((lr_dp_now - lr_dp_last_launch))
        if [ "$lr_dp_since" -lt "$download_pace" ] 2>/dev/null; then
            sleep $((download_pace - lr_dp_since))
        fi
        lr_dp_last_launch=$(date +%s)

        if resolve_stream_bg "$media_type" "$media_id" "$season" "$lr_dp_ep"; then
            lr_dp_url=$(printf '%s' "$lr_resolve_out" | cut -f1)
            lr_dp_referer=$(printf '%s' "$lr_resolve_out" | cut -f2)
            lr_dp_subs=$(printf '%s' "$lr_resolve_out" | cut -f3)
        else
            lr_dp_url=""
        fi

        lr_dp_prog="$tmp_dir/dlprog.$$.$lr_dp_ep"
        lr_dp_status="$tmp_dir/dlstatus.$$.$lr_dp_ep"

        if [ -z "$lr_dp_url" ]; then
            echo fail >"$lr_dp_status"
            continue
        fi

        (
            episode_title=$lr_dp_title
            subs_csv=$lr_dp_subs
            referer=$lr_dp_referer
            displayed_title="$title - $season_title - Eps $(printf '%02d' "$lr_dp_ep" 2>/dev/null || printf '%s' "$lr_dp_ep") - $episode_title"
            if download_video "$lr_dp_url" "$displayed_title" "$lr_dp_dest_dir" "$lr_dp_prog"; then
                echo ok >"$lr_dp_status"
            else
                echo fail >"$lr_dp_status"
            fi
        ) &
        set -- "$@" "$!"
        if [ "$#" -ge "$download_concurrency" ]; then
            wait "$1" 2>/dev/null
            shift
        fi
    done <"$lr_dp_rows_file"

    # Plain `wait`: covers both the still-in-flight downloads and the
    # renderer, which exits on its own once every row has a status file.
    wait
    [ -n "$lr_dp_render_pid" ] && wait "$lr_dp_render_pid" 2>/dev/null
    lr_no_status=""

    # Heuristic, not a certainty: several failures in one batch run at
    # concurrency>1 often means the provider doesn't like simultaneous
    # connections (rate limit) or flatly disallows more than one active
    # stream at all (some token-based addons) - either way, sequential is
    # the fix, and it's a config value away instead of a debugging session.
    lr_dp_failed=0
    lr_dp_retry_rows=""
    while IFS= read -r lr_dp_r3; do
        [ -z "$lr_dp_r3" ] && continue
        lr_dp_s3=$(printf '%s' "$lr_dp_r3" | cut -f3)
        if [ -f "$lr_dp_s3" ] && [ "$(cat "$lr_dp_s3")" != "ok" ]; then
            lr_dp_failed=$((lr_dp_failed + 1))
            # Label is "Eps N: Title" - recover N to find the original row.
            lr_dp_ep3=$(printf '%s' "$lr_dp_r3" | cut -f1 | sed -n 's/^Eps \([0-9]*\):.*/\1/p')
            lr_dp_row3=$(awk -F'\t' -v e="$lr_dp_ep3" '$1 == e' "$lr_dp_rows_file")
            [ -n "$lr_dp_row3" ] && lr_dp_retry_rows="${lr_dp_retry_rows}${lr_dp_retry_rows:+$nl}${lr_dp_row3}"
        fi
    done <"$lr_dp_manifest"
    if [ "$lr_dp_failed" -gt 1 ] && [ "$download_concurrency" -gt 1 ]; then
        notify "Several downloads failed" "8000" "" "try download_concurrency=1 in the config - this provider may not allow simultaneous streams"
    fi

    rm -f "$lr_dp_manifest" "$lr_dp_rows_file"

    # One retry pass over whatever failed. These CDN links are signed and
    # single-use-ish, and a failure is very often a one-off 403/hiccup on
    # that specific link rather than anything wrong with the episode - a
    # retry re-resolves from scratch, so it gets a brand new URL (and
    # possibly a different source) instead of re-pulling the dead one.
    # Guarded by $lr_dp_is_retry so a genuinely dead provider can't recurse.
    if [ -n "$lr_dp_retry_rows" ] && [ -z "$lr_dp_is_retry" ]; then
        notify "Retrying" "5000" "" "$lr_dp_failed episode(s) failed, retrying once"
        download_episodes_parallel "$lr_dp_retry_rows" retry
    fi
    # Single -d is silent once it returns; batch has the live table, but a
    # desktop popup at the end is still useful if the terminal's behind other
    # windows.
    [ -z "$lr_dp_is_retry" ] && desktop_notify "Download finished" "8000" "$lr_dp_count episode(s) of $title"
}

### Main loop ###
loop() {
    while [ "$keep_running" = "true" ]; do
        if [ "$json_output" = "true" ]; then
            tmdb_detail_json
            exit 0
        fi

        if ! resolve_stream_bg "$media_type" "$media_id" "$season" "$episode"; then
            notify "Error" "5000" "" "resolve_stream could not find a playable link"
            exit 1
        fi
        stream=$lr_resolve_out
        video_link=$(printf '%s' "$stream" | cut -f1)
        referer=$(printf '%s' "$stream" | cut -f2)
        subs_csv=$(printf '%s' "$stream" | cut -f3)
        lr_resolved_via=""
        [ -f "$tmp_dir/resolved-via.$$" ] && lr_resolved_via=$(cat "$tmp_dir/resolved-via.$$")
        rm -f "$tmp_dir/resolved-via.$$"
        if [ -z "$video_link" ]; then
            notify "Error" "5000" "" "resolve_stream returned no video URL"
            exit 1
        fi

        if [ "$no_subs" = "true" ] || [ -z "$subs_csv" ]; then
            subs_links=""
        else
            subs_links=$(printf '%s' "$subs_csv" | tr ',' '\n' | sed -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
        fi

        displayed_title="$title"
        [ "$media_type" = "tv" ] && displayed_title="$title - $season_title - Eps $(printf '%02d' "$episode" 2>/dev/null || printf '%s' "$episode") - $episode_title"

        if [ "$download" = "true" ]; then
            notify "Downloading" "5000" "$images_cache_dir/$title ($media_type)  $media_id.jpg" "$displayed_title to $(dest_dir)"
            # Foreground: this used to be "&" followed by exit 0, which killed
            # the download the instant it started.
            if download_video "$video_link" "$displayed_title" "$(dest_dir)"; then
                desktop_notify "Download complete" "8000" "$displayed_title"
                exit 0
            fi
            # The addon returned many sources but resolve kept only the best
            # pick; when that pick is a dead/expired link, walk the rest of
            # the ranked list (stremio_addon_stream saved it) instead of
            # re-resolving and getting the same dead URL back.
            if [ -s "$lr_tmp/sb-cands.$$" ]; then
                while IFS= read -r lr_cand; do
                    [ -z "$lr_cand" ] && continue
                    [ "$lr_cand" = "$video_link" ] && continue
                    notify "Retrying" "5000" "" "trying next source for $displayed_title"
                    if download_video "$lr_cand" "$displayed_title" "$(dest_dir)"; then
                        desktop_notify "Download complete" "8000" "$displayed_title"
                        exit 0
                    fi
                done <"$lr_tmp/sb-cands.$$"
            fi
            # Last resort: re-resolve for a fresh link (covers backends that
            # return a single URL, where there's no saved list to walk).
            notify "Retrying" "5000" "" "re-resolving $displayed_title"
            resolve_stream_bg "$media_type" "$media_id" "$season" "$episode" || exit 1
            video_link=$(printf '%s' "$lr_resolve_out" | cut -f1)
            referer=$(printf '%s' "$lr_resolve_out" | cut -f2)
            subs_csv=$(printf '%s' "$lr_resolve_out" | cut -f3)
            [ -n "$video_link" ] || exit 1
            if download_video "$video_link" "$displayed_title" "$(dest_dir)"; then
                desktop_notify "Download complete" "8000" "$displayed_title"
                exit 0
            fi
            exit 1
        fi

        if [ "$discord_presence" = "true" ]; then
            [ -p "$presence" ] || mkfifo "$presence"
            rm -f "$handshook"
            tail -f "$presence" | nc -U "$discord_ipc" >"$ipclog" &
            update_rich_presence "00:00:00" &
        fi

        history_check
        # Captured before play/history_save: history_save mutates $episode/
        # $season/$progress when it rolls a finished episode forward, and the
        # binge check below needs the episode we actually just watched, not
        # the one history now points at.
        lr_watched_ep=$episode
        lr_watched_season=$season
        play
        lr_watched_progress=$progress
        [ "$history" = "true" ] && history_save

        # --binge: no menu, no 3s wait. Finished a tv episode -> straight to
        # the next one (or exit when the show is over); quit early or a movie
        # -> just exit.
        if [ "$binge" = "true" ]; then
            if [ "$media_type" = "tv" ] && [ "$lr_watched_progress" -gt 90 ] 2>/dev/null; then
                episode=$lr_watched_ep
                season=$lr_watched_season
                tmdb_next_episode
                if [ -n "$next_episode" ]; then
                    resume_from=""
                    episode_title=$(printf '%s' "$next_episode" | cut -f2)
                    episode=$(printf '%s' "$next_episode" | cut -f1)
                    notify "Next episode" "3000" "" "$episode_title"
                    continue
                fi
            fi
            exit 0
        fi

        # Auto-advance past a finished episode instead of always stopping at
        # the menu. `read -t` isn't POSIX, but is supported everywhere this
        # script actually runs (dash, busybox ash, bash); on a shell where
        # it isn't, read fails immediately and this just skips straight to
        # the next episode with no cancel window - a soft degradation, not
        # a hang.
        if [ "$media_type" = "tv" ] && [ "$progress" -gt 90 ] 2>/dev/null; then
            tmdb_next_episode
            if [ -n "$next_episode" ]; then
                printf '\033[1;34m→ %s  (3s… press Enter to stop)\033[0m' "$(printf '%s' "$next_episode" | cut -f2)" >&2
                # shellcheck disable=SC3045,SC2034 # -t is POSIX-undefined but
                # broadly supported (see comment above); lr_cancel's value is
                # never read, only whether read succeeded before the timeout
                if read -r -t 3 lr_cancel 2>/dev/null; then
                    printf '\33[2K\r' >&2
                    prompt_to_continue
                else
                    printf '\33[2K\r' >&2
                    resume_from=""
                    episode_title=$(printf '%s' "$next_episode" | cut -f2)
                    episode=$(printf '%s' "$next_episode" | cut -f1)
                    continue
                fi
            else
                prompt_to_continue
            fi
        else
            prompt_to_continue
        fi
        # The copy entries re-show the menu after copying instead of
        # re-resolving/replaying the video.
        while :; do
            case "$continue_choice" in
                "Copy stream URL") clipboard_copy "$video_link"; notify "Copied" "3000" "" "stream URL" ;;
                "Copy player command") clipboard_copy "$(player_command)"; notify "Copied" "3000" "" "player command" ;;
                *) break ;;
            esac
            prompt_to_continue
        done
        case "$continue_choice" in
            "Next episode")
                resume_from=""
                # history_save may have already rolled $episode forward when
                # history=true, so recompute from the episode we actually just
                # watched, not the one history now points at.
                episode=$lr_watched_ep
                season=$lr_watched_season
                tmdb_next_episode
                if [ -n "$next_episode" ]; then
                    episode_title=$(printf '%s' "$next_episode" | cut -f2)
                    episode=$(printf '%s' "$next_episode" | cut -f1)
                    notify "Watching the next episode" "5000" "" "$episode_title"
                else
                    notify "No more episodes" "5000" "" "$title"
                    exit 0
                fi
                ;;
            "Select episode") keep_running="false"; STATE="EPISODE" ;;
            "Select season") keep_running="false"; STATE="SEASON" ;;
            "Replay episode" | "Replay") resume_from="" ;;
            "Search")
                query="" response="" season="" episode="" episode_title="" title="" resume_from=""
                keep_running="false"
                STATE="SEARCH"
                ;;
            *) keep_running="false"; STATE="EXIT" ;;
        esac
    done
}
# main [starting-state] - defaults to SEARCH; callers that already have
# $response populated (a trending/recent listing) or are resuming a specific
# show (history_pick) pass their own starting state so they don't redo work
# or reset state that's already been set up.
main() {
    STATE="${1:-HOME}"
    while :; do
        case "$STATE" in
            HOME) choose_home ;;
            CONTINUE) history_pick ;;
            LAST) history_last ;;
            SEARCH) choose_search ;;
            MEDIA) choose_media ;;
            SEASON) choose_season ;;
            EPISODE) choose_episode ;;
            PLAY) loop ;;
            EXIT | *) break ;;
        esac
    done
}

### Argument parsing + dispatch ###
# parse_args "$@" - sets query and every flag-backed variable as a side
# effect; does not launch anything itself. Split out from run_main() so it
# can be exercised directly (see tests/smoke.sh) without also triggering a
# real search/playback run.
parse_args() {
    query=""
    action=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --)
                shift
                query="$*"
                break
                ;;
            # These are terminal actions, but deferred until every flag is
            # parsed (dispatched by run_main) rather than run immediately -
            # otherwise `lobster -c -i` and `lobster -i -c` would behave
            # differently depending on whether -i had been seen yet.
            -c | --continue) action="continue" && shift ;;
            --last) action="last" && shift ;;
            --binge) binge="true" && shift ;;
            --clear-history) action="clear" && shift ;;
            --discord | --discord-presence | --rpc | --presence) discord_presence="true" && shift ;;
            -d | --download)
                download="true"
                if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
                    download_dir="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            -e | --edit) action="edit" && shift ;;
            --config-regenerate) action="regen" && shift ;;
            -h | --help) usage && exit 0 ;;
            -i | --image-preview) image_preview="true" && shift ;;
            -j | --json) json_output="true" && shift ;;
            -l | --language)
                if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
                    subs_language="$2"
                    shift 2
                else
                    subs_language="english"
                    shift
                fi
                ;;
            --rofi | --external-menu) use_external_menu="true" && shift ;;
            --provider)
                if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
                    provider="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            -q | --quality)
                # shellcheck disable=SC2034 # read by the user's resolve_stream, not by this file
                if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
                    quality="$2"
                    shift 2
                else
                    quality="1080"
                    shift
                fi
                ;;
            -r | --recent)
                if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
                    recent="$2"
                    shift 2
                else
                    recent="movie"
                    shift
                fi
                ;;
            -s | --syncplay) player="syncplay" && shift ;;
            -t | --trending) trending="1" && shift ;;
            -T | --top-rated)
                if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
                    top_rated="$2"
                    shift 2
                else
                    top_rated="movie"
                    shift
                fi
                ;;
            --genre)
                if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
                    genre="$2"
                    shift 2
                    genre_type="movie"
                    if [ "$1" = "movie" ] || [ "$1" = "tv" ]; then genre_type="$1"; shift; fi
                else
                    genre=""
                    shift
                fi
                ;;
            --year)
                if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
                    year="$2"
                    shift 2
                    year_type="movie"
                    if [ "$1" = "movie" ] || [ "$1" = "tv" ]; then year_type="$1"; shift; fi
                else
                    year=""
                    shift
                fi
                ;;
            -u | -U | --update) action="update" && shift ;;
            -v | -V | --version)
                notify "lobster version: $LOBSTER_VERSION"
                exit 0
                ;;
            -x | --debug) debug="true" && shift ;;
            -n | --no-subs) no_subs="true" && shift ;;
            *) query="$query $1" && shift ;;
        esac
    done
    query="${query# }"
}

# run_main "$@" - the real entry point: resolves the player, parses argv,
# then dispatches into trending/recent/search.
run_main() {
    # mpv isn't always called "mpv": fall back across Windows/Android/iSH.
    if [ "$player" = "mpv" ] && ! command -v mpv >/dev/null 2>&1; then
        if command -v mpv.exe >/dev/null 2>&1; then
            player="mpv.exe"
        elif uname -a | grep -qi "android" 2>/dev/null; then
            player="mpv_android"
        elif uname -a | grep -qi "ish" 2>/dev/null; then
            player="iSH"
        else
            dep_check mpv.exe
        fi
    fi

    parse_args "$@"

    if [ "$image_preview" = "true" ]; then
        test -d "$images_cache_dir" || mkdir -p "$images_cache_dir"
        if [ "$use_external_menu" = "true" ]; then
            mkdir -p "$tmp_dir/applications/"
            [ -L "$applications" ] || ln -sf "$tmp_dir/applications/" "$applications"
        fi
    fi

    # Dispatched here (after every flag is parsed) rather than inline in
    # parse_args, so -c/-e/--clear-history/--update see the full flag set
    # (e.g. -i) regardless of where they appear on the command line.
    case "$action" in
        continue) lr_continue_back="exit"; main CONTINUE ;;
        last) main LAST ;;
        clear) history_clear ;;
        edit)
            [ -z "$lobster_editor" ] && lobster_editor="nano"
            "$lobster_editor" "$config_file"
            exit 0
            ;;
        regen)
            # The old file is kept, never merged: the template sets nothing,
            # so re-reading your own settings out of the .bak is a copy-paste,
            # not a migration.
            if [ -f "$config_file" ]; then
                mv "$config_file" "$config_file.bak" || exit 1
                printf 'moved your old config to %s\n' "$config_file.bak" >&2
            fi
            write_default_config "$config_file" || exit 1
            printf 'wrote a fresh template to %s\n' "$config_file" >&2
            exit 0
            ;;
        update) update_script ;;
    esac

    [ "$trending" = "1" ] && fetch_listing trending
    case "$recent" in
        movie | tv) fetch_listing recent "$recent" ;;
        *) : ;;
    esac
    case "$top_rated" in
        movie | tv) fetch_listing top-rated "$top_rated" ;;
        *) : ;;
    esac
    if [ -n "$genre" ]; then
        lr_gk=$(genre_key "$genre" "$genre_type")
        if [ -n "$lr_gk" ]; then
            fetch_listing "genre:$lr_gk" "$genre_type"
        else
            notify "Error" "5000" "" "unknown genre '$genre' for $genre_type"
            exit 1
        fi
    fi
    if [ -n "$year" ]; then
        case "$year" in
            *[!0-9]*) notify "Error" "5000" "" "invalid year '$year'"; exit 1 ;;
        esac
        fetch_listing "year:$year" "$year_type"
    fi

    if [ -n "$response" ]; then
        main MEDIA
    elif [ -n "$query" ]; then
        main SEARCH
    else
        main
    fi
}

### Entry point ###
# Skipped when LOBSTER_TEST is set, so tests/smoke.sh can source this file
# for its function definitions without triggering a real run.
if [ -z "$LOBSTER_TEST" ]; then
    # These helper invocations are separate `sh $0` processes fzf spawns per
    # keystroke. They must NOT run cleanup() on exit: it wipes $tmp_dir (the
    # poster manifest, the position file) and TERMs the whole process group,
    # i.e. the real lobster and fzf itself, while the picker is still open.
    case "$1" in
        --tmdb-preview | --image-preview-cell | --search) trap - EXIT INT TERM ;;
    esac
    # Hidden flag fzf's --preview shells out to (see menu()/choose_media());
    # bypasses configuration/dep_check since it only ever needs curl, and
    # exits before touching any of the normal search/playback state.
    if [ "$1" = "--tmdb-preview" ]; then
        shift
        tmdb_preview_text "$@"
        exit 0
    fi
    if [ "$1" = "--image-preview-cell" ]; then
        shift
        image_preview_cell "$@"
        exit 0
    fi
    # fzf live-search reload payload (see live_search()): prints tmdb_search
    # results for the query; bypasses configuration/dep_check like the
    # preview flags since it only needs curl.
    if [ "$1" = "--search" ]; then
        shift
        [ -z "$*" ] && exit 0
        tmdb_search "$*"
        exit 0
    fi

    # -x/--debug needs to be known before configuration()/dep_check run (it
    # decides whether output gets teed to $lobster_logfile below), so it's
    # pre-scanned here; run_main's own arg loop still parses it normally too.
    case " $* " in
        *' -x '* | *' --debug '*) debug="true" ;;
        *) : ;;
    esac

    configuration
    # fzf is preferred but not required - menu() falls back to a numbered
    # picker (numbered_menu) when it's missing.
    # awk is unconditional: parsing, history and the pickers all use it.
    dep_check grep sed curl awk
    [ "$use_external_menu" = "true" ] && dep_check rofi
    # nc is a soft dependency: without it, resume/duration fall back to
    # per-episode watch_later files instead of live IPC (see play()).

    if [ "$debug" = "true" ]; then
        set -x
        exec 3>&1 4>&2
        run_main "$@" 2>&1 | tee "$lobster_logfile" >&3 2>&4
        status=$?
        exec 1>&3 2>&4
        exit "$status"
    else
        run_main "$@"
    fi
fi
