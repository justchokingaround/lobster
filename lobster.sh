#!/usr/bin/env sh

LOBSTER_VERSION="4.3.2"

### General Variables ###
config_file="$HOME/.config/lobster/lobster_config.sh"
lobster_editor=${VISUAL:-${EDITOR}}
tmp_dir="${TMPDIR:-/tmp}/lobster" && mkdir -p "$tmp_dir"
lobster_socket="${TMPDIR:-/tmp}/lobster.sock" # Used by mpv (check the play_video function)
lobster_logfile="${TMPDIR:-/tmp}/lobster.log"
applications="$HOME/.local/share/applications/lobster" # Used for external menus (for now just rofi)
images_cache_dir="$tmp_dir/lobster-images"             # Used for storing downloaded images of movie covers

### Notifications ###
command -v notify-send >/dev/null 2>&1 && notify="true" || notify="false" # check if notify-send is installed
# send_notification [message] [timeout] [icon] [title]
send_notification() {
    [ "$json_output" = "true" ] && return
    if [ "$use_external_menu" = "false" ] || [ -z "$use_external_menu" ]; then
        [ -z "$4" ] && printf "\33[2K\r\033[1;34m%s\n\033[0m" "$1" && return
        [ -n "$4" ] && printf "\33[2K\r\033[1;34m%s - %s\n\033[0m" "$1" "$4" && return
    fi
    [ -z "$2" ] && timeout=3000 || timeout="$2" # default timeout is 3 seconds
    if [ "$notify" = "true" ]; then
        [ -z "$3" ] && notify-send "$1" "$4" -t "$timeout" -h string:x-dunst-stack-tag:vol # the -h string:x-dunst-stack-tag:vol is used for overriding previous notifications
        [ -n "$3" ] && notify-send "$1" "$4" -t "$timeout" -i "$3" -h string:x-dunst-stack-tag:vol
    fi
}

### HTML Decoding ###
command -v "hxunent" >/dev/null 2>&1 && hxunent="hxunent" || hxunent="tee /dev/null" # use hxunent if installed, else do nothing

### Discord Rich Presence Variables ###
# Note: experimental feature
presence_client_id="1239340948048187472" # Discord Client ID
# shellcheck disable=SC2154
discord_ipc="${XDG_RUNTIME_DIR}/discord-ipc-0" # Discord IPC Socket (Could also be discord-ipc-1 if using arRPC afaik)
handshook="$tmp_dir/handshook"                 # Indicates if the RPC handshake has been done
ipclog="$tmp_dir/ipclog"                       # Logs the RPC events
presence="$tmp_dir/presence"                   # Used by the rich presence function
small_image="https://www.pngarts.com/files/9/Juvenile-American-Lobster-PNG-Transparent-Image.png"

### OS Specific Variables ###
separator=':'             # default value
path_thing="\\"           # default value
sed='sed'                 # default value
ueberzugpp_tmp_dir="/tmp" # for some reason ueberzugpp only uses $TMPDIR on Darwin
# shellcheck disable=SC2249
case "$(uname -s)" in
    MINGW* | *Msys) separator=';' && path_thing='' ;;
    *arwin) sed="gsed" && ueberzugpp_tmp_dir="${TMPDIR:-/tmp}" ;;
esac

# Checks if any of the provided arguments are -e or --edit
# If so, it will edit the config file
# This was added for pure convenience (for me)
if printf "%s" "$*" | grep -qE "\-\-edit|\-e" 2>/dev/null; then
    #shellcheck disable=1090
    . "${config_file}"
    [ -z "$lobster_editor" ] && lobster_editor="nano"
    "$lobster_editor" "$config_file"
    exit 0
fi

### Cleanup Functions ###
rpc_cleanup() {
    pkill -f "nc -U $discord_ipc" >/dev/null
    pkill -f "tail -f $presence" >/dev/null
    rm "$handshook" "$ipclog" "$presence" >/dev/null
}
cleanup() {
    [ "$debug" != "true" ] && rm -rf "$tmp_dir"
    [ "$remove_tmp_lobster" = "true" ] && rm -rf "$tmp_dir"

    if [ "$image_preview" = "true" ] && [ "$use_external_menu" = "false" ] && [ "$use_ueberzugpp" = "true" ]; then
        killall ueberzugpp 2>/dev/null
        rm -f "$ueberzugpp_tmp_dir"/ueberzugpp-*
    fi
    set +x && exec 2>&-
}
trap cleanup EXIT INT TERM

### Help Function ###
usage() {
    printf "
  Usage: %s [options] [query]
  If a query is provided, it will be used to search for a Movie/TV Show

  Options:
    -c, --continue
      Continue watching from current history
    -d, --download [path]
      Downloads movie or episode that is selected (if no path is provided, it defaults to the current directory)
    --discord, --discord-presence, --rpc, --presence
      Enables discord rich presence (beta feature, but should work fine on Linux)
    -e, --edit
      Edit config file using an editor defined with lobster_editor in the config (\$EDITOR by default)
    -h, --help
      Show this help message and exit
    -i, --image-preview
      Shows image previews during media selection (requires chafa, you can optionally use ueberzugpp)
    -j, --json
      Outputs the json containing video links, subtitle links, referrers etc. to stdout
    -l, --language [language]
      Specify the subtitle language (if no language is provided, it defaults to english)
    --rofi, --external-menu
      Use rofi instead of fzf
    -p, --provider
      Specify the provider to watch from (if no provider is provided, it defaults to Vidcloud) (currently supported: Vidcloud, UpCloud)
    -q, --quality
      Specify the video quality (if no quality is provided, it defaults to 1080)
    -r, --recent [movies|tv]
      Lets you select from the most recent movies or tv shows (if no argument is provided, it defaults to movies)
    -s, --syncplay
      Use Syncplay to watch with friends
    -t, --trending
      Lets you select from the most popular movies and shows
    -u, -U, --update
      Update the script
    -v, -V, --version
      Show the version of the script
    -x, --debug
      Enable debug mode (prints out debug info to stdout and also saves it to \$TEMPDIR/lobster.log)

  Note:
    All arguments can be specified in the config file as well.
    If an argument is specified in both the config file and the command line, the command line argument will be used.

  Some example usages:
    ${0##*/} -i a silent voice --rofi
    ${0##*/} -l spanish -q 720 fight club -i -d
    ${0##*/} -l spanish blade runner --json

" "${0##*/}"
}

### Dependencies Check ###
dep_ch() {
    for dep; do
        if ! command -v "$dep" >/dev/null; then
            send_notification "Program \"$dep\" not found. Please install it."
            exit 1
        fi
    done
}

### Default Configuration ###
# this function is ran after the user's config file is "checked" (source'd)
configuration() {
    [ -n "$XDG_CONFIG_HOME" ] && config_dir="$XDG_CONFIG_HOME/lobster" || config_dir="$HOME/.config/lobster"
    [ -n "$XDG_DATA_HOME" ] && data_dir="$XDG_DATA_HOME/lobster" || data_dir="$HOME/.local/share/lobster"
    [ ! -d "$config_dir" ] && mkdir -p "$config_dir"
    [ ! -d "$data_dir" ] && mkdir -p "$data_dir"
    #shellcheck disable=1090
    [ -f "$config_file" ] && . "${config_file}" # source the user's config file
    [ -z "$base" ] && base="flixhq.to"
    [ -z "$player" ] && player="mpv"
    [ -z "$download_dir" ] && download_dir="$PWD"
    [ -z "$provider" ] && provider="Vidcloud"
    [ -z "$subs_language" ] && subs_language="english"
    subs_language="$(printf "%s" "$subs_language" | cut -c2-)"
    [ -z "$histfile" ] && histfile="$data_dir/lobster_history.txt" && mkdir -p "$(dirname "$histfile")"
    [ -z "$history" ] && history=false
    [ -z "$use_external_menu" ] && use_external_menu="false"
    [ -z "$image_preview" ] && image_preview="false"
    [ -z "$debug" ] && debug="false"
    [ -z "$preview_window_size" ] && preview_window_size=up:60%:wrap
    if [ -z "$use_ueberzugpp" ]; then
        use_ueberzugpp="false"
    elif [ "$use_ueberzugpp" = "true" ]; then
        [ -z "$ueberzug_x" ] && ueberzug_x=10
        [ -z "$ueberzug_y" ] && ueberzug_y=3
        [ -z "$ueberzug_max_width" ] && ueberzug_max_width=$(($(tput lines) / 2))
        [ -z "$ueberzug_max_height" ] && ueberzug_max_height=$(($(tput lines) / 2))
    fi
    [ -z "$chafa_dims" ] && chafa_dims=30x40
    [ -z "$remove_tmp_lobster" ] && remove_tmp_lobster="true"
    [ -z "$json_output" ] && json_output="false"
    [ -z "$discord_presence" ] && discord_presence="false"
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
        *) [ -z "$watchlater_dir" ] && watchlater_dir="$tmp_dir/watchlater" && mkdir -p "$watchlater_dir" ;;
    esac
}

# The reason I use additional file descriptors is because of the use of tee
# which when piped into would hijack the terminal, which was unwanted behavior
# since there are SSH use cases for mpv and since I wanted to have a logging mechanism
exec 3>&1 4>&2 1>"$lobster_logfile" 2>&1
{
    # check that the necessary programs are installed
    dep_ch "grep" "$sed" "curl" "fzf" || true
    if [ "$use_external_menu" = "true" ]; then
        dep_ch "rofi" || true
    fi
    if [ "$player" = "mpv" ]; then
        dep_ch "awk" "nc" || true
    fi

    ### Launchers stuff (rofi, fzf, etc.) ###
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
    # A launcher is a utility used to select an option from a list (fzf, rofi)
    # launcher [prompt] [columns-to-display]
    launcher() {
        case "$use_external_menu" in
            "true")
                [ -z "$2" ] && rofi -sort -dmenu -i -width 1500 -p "" -mesg "$1"
                [ -n "$2" ] && rofi -sort -dmenu -i -width 1500 -p "" -mesg "$1" -display-columns "$2"
                ;;
            *)
                [ -z "$2" ] && fzf --reverse --prompt "$1"
                [ -n "$2" ] && fzf --reverse --prompt "$1" --with-nth "$2" -d "\t"
                ;;
        esac
    }
    # helper function to be able to display only an "nth" column in fzf/rofi without altering the stdin
    nth() {
        stdin=$(cat -)
        [ -z "$stdin" ] && return 1
        prompt="$1"
        [ $# -ne 1 ] && shift
        line=$(printf "%s" "$stdin" | $sed -nE "s@^(.*)\t[0-9:]*\t[0-9]*\t(tv|movie)(.*)@\1 (\2)\t\3@p" | cut -f1-3,6,7 | tr '\t' '|' | launcher "$prompt" | cut -d "|" -f 1)
        [ -n "$line" ] && printf "%s" "$stdin" | $sed -nE "s@^$line\t(.*)@\1@p" || exit 1
    }

    ### User Prompts ###
    prompt_to_continue() {
        if [ "$media_type" = "tv" ]; then
            continue_choice=$(printf "Next episode\nReplay episode\nExit\nSearch" | launcher "Select: ")
        else
            continue_choice=$(printf "Exit\nSearch" | launcher "Select: ")
        fi
    }

    ### Searching/Selecting ###
    get_input() {
        if [ "$use_external_menu" = "false" ]; then
            printf "Search Movie/TV Show: " && read -r query
        else
            if [ -n "$rofi_prompt_config" ]; then
                query=$(printf "" | rofi -theme "$rofi_prompt_config" -sort -dmenu -i -width 1500 -p "" -mesg "Search Movie/TV Show")
            else
                query=$(printf "" | launcher "Search Movie/TV Show")
            fi
        fi
        [ -n "$query" ] && query=$(echo "$query" | tr ' ' '-')
        [ -z "$query" ] && send_notification "Error" "1000" "" "No query provided" && exit 1
    }
    search() {
        response=$(curl -s "https://${base}/search/$1" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
            $sed -nE "s@.*img data-src=\"([^\"]*)\".*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\1\t\3\t\2\t\4 [\5]@p")
        [ -z "$response" ] && send_notification "Error" "1000" "" "No results found" && exit 1
    }
    choose_episode() {
        if [ -z "$season_id" ]; then
            tmp_season_id=$(curl -s "https://${base}/ajax/v2/tv/seasons/${media_id}" | $sed -nE "s@.*href=\".*-([0-9]*)\">(.*)</a>@\2\t\1@p" | launcher "Select a season: " "1")
            [ -z "$tmp_season_id" ] && exit 1
            season_title=$(printf "%s" "$tmp_season_id" | cut -f1)
            season_id=$(printf "%s" "$tmp_season_id" | cut -f2)
            tmp_ep_id=$(curl -s "https://${base}/ajax/v2/season/episodes/${season_id}" | $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' |
                $sed -nE "s@.*data-id=\"([0-9]*)\".*title=\"([^\"]*)\">.*@\2\t\1@p" | $hxunent | launcher "Select an episode: " "1")
            [ -z "$tmp_ep_id" ] && exit 1
        fi
        [ -z "$episode_title" ] && episode_title=$(printf "%s" "$tmp_ep_id" | cut -f1)
        [ -z "$data_id" ] && data_id=$(printf "%s" "$tmp_ep_id" | cut -f2)
        episode_id=$(curl -s "https://${base}/ajax/v2/episode/servers/${data_id}" | $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' |
            $sed -nE "s@.*data-id=\"([0-9]*)\".*title=\"([^\"]*)\".*@\1\t\2@p" | grep "$provider" | cut -f1)
    }
    next_episode_exists() {
        episodes_list=$(curl -s "https://${base}/ajax/v2/season/episodes/${season_id}" | $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' |
            $sed -nE "s@.*data-id=\"([0-9]*)\".*title=\"([^\"]*)\">.*@\2\t\1@p" | $hxunent)
        next_episode=$(printf "%s" "$episodes_list" | $sed -n "/$data_id/{n;p;}")
        [ -n "$next_episode" ] && return
        tmp_season_id=$(curl -s "https://${base}/ajax/v2/tv/seasons/${media_id}" | $sed -n "/href=\".*-$season_id/{n;n;n;n;p;}" | $sed -nE "s@.*href=\".*-([0-9]*)\">(.*)</a>@\2\t\1@p")
        [ -z "$tmp_season_id" ] && return
        season_title=$(printf "%s" "$tmp_season_id" | cut -f1)
        season_id=$(printf "%s" "$tmp_season_id" | cut -f2)
        next_episode=$(curl -s "https://${base}/ajax/v2/season/episodes/${season_id}" | $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' |
            $sed -nE "s@.*data-id=\"([0-9]*)\".*title=\"([^\"]*)\">.*@\2\t\1@p" | $hxunent | head -1)
        [ -n "$next_episode" ] && return
    }

    ### Image Preview ###
    download_thumbnails() {
        echo "$1" >"$tmp_dir/image_links" # used for the discord rich presence thumbnail
        printf "%s\n" "$1" | while read -r cover_url id type title; do
            cover_url=$(printf "%s" "$cover_url" | sed -E 's/\/[[:digit:]]+x[[:digit:]]+\//\/1000x1000\//')
            curl -s -o "$images_cache_dir/  $title ($type)  $id.jpg" "$cover_url" &
            if [ "$use_external_menu" = "true" ]; then
                entry="$tmp_dir/applications/$id.desktop"
                # The reason for the spaces is so that only the title can be displayed when using rofi
                # or fzf, while still keeping the id and type in the string after it's selected
                generate_desktop "$title ($type)" "$images_cache_dir/  $title ($type)  $id.jpg" >"$entry" &
            fi
        done
        sleep "$2"
    }
    # defaults to chafa
    image_preview_fzf() {
        if [ "$use_ueberzugpp" = "true" ]; then
            UB_PID_FILE="$tmp_dir.$(uuidgen)"
            if [ -z "$ueberzug_output" ]; then
                ueberzugpp layer --no-stdin --silent --use-escape-codes --pid-file "$UB_PID_FILE"
            else
                ueberzugpp layer -o "$ueberzug_output" --no-stdin --silent --use-escape-codes --pid-file "$UB_PID_FILE"
            fi
            UB_PID="$(cat "$UB_PID_FILE")"
            LOBSTER_UEBERZUG_SOCKET="$ueberzugpp_tmp_dir/ueberzugpp-$UB_PID.socket"
            choice=$(find "$images_cache_dir" -type f -exec basename {} \; | fzf -i -q "$1" --cycle --preview-window="$preview_window_size" --preview="ueberzugpp cmd -s $LOBSTER_UEBERZUG_SOCKET -i fzfpreview -a add -x $ueberzug_x -y $ueberzug_y --max-width $ueberzug_max_width --max-height $ueberzug_max_height -f $images_cache_dir/{}" --reverse --with-nth 2 -d "  ")
            ueberzugpp cmd -s "$LOBSTER_UEBERZUG_SOCKET" -a exit
        else
            dep_ch "chafa" || true
            choice=$(find "$images_cache_dir" -type f -exec basename {} \; | fzf -i -q "$1" --cycle --preview-window="$preview_window_size" --preview="chafa -f sixels -s $chafa_dims $images_cache_dir/{}" --reverse --with-nth 2 -d "  ")
        fi
    }
    select_desktop_entry() {
        if [ "$use_external_menu" = "true" ]; then
            [ -n "$image_config_path" ] && choice=$(rofi -show drun -drun-categories lobster -filter "$1" -show-icons -theme "$image_config_path" | $sed -nE "s@.*/([0-9]*)\.desktop@\1@p") 2>/dev/null || choice=$(rofi -show drun -drun-categories lobster -filter "$1" -show-icons | $sed -nE "s@.*/([0-9]*)\.desktop@\1@p") 2>/dev/null
            media_id=$(printf "%s" "$choice" | cut -d\  -f1)
            title=$(printf "%s" "$choice" | $sed -nE "s@[0-9]* (.*) \((tv|movie)\)@\1@p")
            media_type=$(printf "%s" "$choice" | $sed -nE "s@[0-9]* (.*) \((tv|movie)\)@\2@p")
        else
            image_preview_fzf "$1"
            tput reset
            media_id=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\.jpg@\1@p")
            title=$(printf "%s" "$choice" | $sed -nE "s@[[:space:]]* (.*) \[.*\] \((tv|movie)\)  [0-9]*\.jpg@\1@p")
            media_type=$(printf "%s" "$choice" | $sed -nE "s@[[:space:]]* (.*) \[.*\] \((tv|movie)\)  [0-9]*\.jpg@\2@p")
        fi
    }

    ### Scraping/Decryption ###
    get_embed() {
        if [ "$media_type" = "movie" ]; then
            # request to get the episode id
            movie_page="https://${base}"$(curl -s "https://${base}/ajax/movie/episodes/${media_id}" |
                $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' | $sed -nE "s@.*href=\"([^\"]*)\"[[:space:]]*title=\"${provider}\".*@\1@p")
            episode_id=$(printf "%s" "$movie_page" | $sed -nE "s_.*-([0-9]*)\.([0-9]*)\$_\2_p")
        fi
        # request to get the embed
        embed_link=$(curl -s "https://${base}/ajax/sources/${episode_id}" | $sed -nE "s_.*\"link\":\"([^\"]*)\".*_\1_p")
        if [ -z "$embed_link" ]; then
            send_notification "Error" "Could not get embed link"
            exit 1
        fi
    }
    extract_from_json() {
        video_link=$(printf "%s" "$json_data" | tr '[' '\n' | $sed -nE 's@.*\"file\":\"(.*\.m3u8).*@\1@p' | head -1)
        [ -n "$quality" ] && video_link=$(printf "%s" "$video_link" | $sed -e "s|/playlist.m3u8|/$quality/index.m3u8|")

        [ "$json_output" = "true" ] && printf "%s\n" "$json_data" && exit 0
        subs_links=$(printf "%s" "$json_data" | tr "{}" "\n" | $sed -nE "s@.*\"file\":\"([^\"]*)\",\"label\":\"(.$subs_language)[,\"\ ].*@\1@p")
        subs_arg="--sub-file"
        num_subs=$(printf "%s" "$subs_links" | wc -l)
        if [ "$num_subs" -gt 0 ]; then
            subs_links=$(printf "%s" "$subs_links" | $sed -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
            subs_arg="--sub-files"
        fi
        [ -z "$subs_links" ] && send_notification "No subtitles found"
    }
    json_from_id() {
        # json_data=$(curl -s "http://localhost:8888/.netlify/functions/decrypt?id=${source_id}")
        json_data=$(curl -s "https://lobster-decryption.netlify.app/decrypt?id=${source_id}")
    }
    get_json() {
        # get the juicy links
        parse_embed=$(printf "%s" "$embed_link" | $sed -nE "s_(.*)/embed-(4|6)/(.*)\?z=\$_\1\t\2\t\3_p")
        _provider_link=$(printf "%s" "$parse_embed" | cut -f1)
        source_id=$(printf "%s" "$parse_embed" | cut -f3)
        _embed_type=$(printf "%s" "$parse_embed" | cut -f2)
        json_from_id
        if [ -n "$json_data" ]; then
            extract_from_json
        else
            send_notification "Error" "Could not get json data"
            exit 1
        fi
    }

    ### History ###
    check_history() {
        if [ ! -f "$histfile" ]; then
            [ "$image_preview" = "true" ] && send_notification "Now Playing" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$title"
            [ "$json_output" != "true" ] && send_notification "Now Playing" "5000" "" "$title"
            return
        fi
        case $media_type in
            movie)
                if grep -q "$media_id" "$histfile"; then
                    resume_from=$(grep "$media_id" "$histfile" | cut -f2)
                    send_notification "Resuming from" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$resume_from"
                else
                    send_notification "Now Playing" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$title"
                fi
                ;;
            tv)
                if grep -q "$media_id" "$histfile"; then
                    if grep -q "$episode_id" "$histfile"; then
                        [ -z "$resume_from" ] && resume_from=$($sed -nE "s@.*\t([0-9:]*)\t$media_id\ttv\t$season_id.*@\1@p" "$histfile")
                        send_notification "$season_title" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$episode_title"
                    fi
                else
                    send_notification "$season_title" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$episode_title"
                fi
                ;;
            *) send_notification "This media type is not supported" ;;

        esac
    }
    save_history() {
        case $media_type in
            movie)
                if [ "$progress" -gt "90" ]; then
                    $sed -i "/$media_id/d" "$histfile"
                    send_notification "Deleted from history" "5000" "" "$title"
                else
                    if grep -q -- "$media_id" "$histfile" 2>/dev/null; then
                        $sed -i "s|\t[0-9:]*\t$media_id|\t$position\t$media_id|1" "$histfile"
                        send_notification "Saved to history" "5000" "" "$title"
                    else
                        printf "%s\t%s\t%s\t%s\t%s\n" "$title" "$position" "$media_id" "$media_type" "$image_link" >>"$histfile"
                        send_notification "Saved to history" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$title"
                    fi
                fi
                ;;
            tv)
                if [ "$progress" -gt "90" ]; then
                    next_episode_exists
                    if [ -n "$next_episode" ]; then
                        episode_title=$(printf "%s" "$next_episode" | cut -f1)
                        data_id=$(printf "%s" "$next_episode" | cut -f2)
                        episode_id=$(curl -s "https://${base}/ajax/v2/episode/servers/${data_id}" | $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' |
                            $sed -nE "s@.*data-id=\"([0-9]*)\".*title=\"([^\"]*)\".*@\1\t\2@p" | grep "$provider" | cut -f1)
                        $sed -i "s|\t[0-9:]*\t[0-9]*\ttv\t[0-9]*\t[0-9]*.*\t.*\t[0-9]*|\t00:00:00\t$media_id\ttv\t$season_id\t$episode_id\t$season_title\t$episode_title\t$data_id|1" "$histfile"
                        send_notification "Updated to next episode" "5000" "" "$episode_title"
                    else
                        $sed -i "/$episode_id/d" "$histfile"
                        send_notification "Completed" "5000" "" "$title"
                    fi
                else
                    if grep -q -- "$media_id" "$histfile" 2>/dev/null; then
                        $sed -i "/$media_id/d" "$histfile"
                        send_notification "Deleted from history" "5000" "" "$title"
                    fi
                    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$title" "$position" "$media_id" "$media_type" \
                        "$season_id" "$episode_id" "$season_title" "$episode_title" "$data_id" "$image_link" >>"$histfile"
                    send_notification "Saved to history" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$title"
                fi
                ;;
            *) notify-send "Error" "Unknown media type" ;;
        esac
    }
    # TODO: Add image_preview support
    play_from_history() {
        [ ! -f "$histfile" ] && send_notification "No history file found" "5000" "" && exit 1
        [ "$watched_history" = 1 ] && exit 0
        watched_history=1
        choice=$($sed -n "1h;1!{x;H;};\${g;p;}" "$histfile" | nl -w 1 | nth "Choose an entry: ")
        [ -z "$choice" ] && exit 1
        media_type=$(printf "%s" "$choice" | cut -f4)
        title=$(printf "%s" "$choice" | cut -f1)
        resume_from=$(printf "%s" "$choice" | cut -f2)
        media_id=$(printf "%s" "$choice" | cut -f3)
        if [ "$media_type" = "tv" ]; then
            season_id=$(printf "%s" "$choice" | cut -f5)
            episode_id=$(printf "%s" "$choice" | cut -f6)
            season_title=$(printf "%s" "$choice" | cut -f7)
            episode_title=$(printf "%s" "$choice" | cut -f8)
            data_id=$(printf "%s" "$choice" | cut -f9)
            image_link=$(printf "%s" "$choice" | cut -f10)
            choose_episode
        fi
        keep_running="true" && loop
    }

    ### Discord Rich Presence ###
    set_activity() {
        len=${#1}
        printf "\\001\\000\\000\\000"
        for i in 0 8 16 24; do
            len=$((len >> i))
            #shellcheck disable=SC2059
            printf "\\$(printf "%03o" "$len")"
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

    ### Video Playback ###
    update_discord_presence() {
        total=$(printf "%02d:%02d:%02d" $((total_duration / 3600)) $((total_duration % 3600 / 60)) $((total_duration % 60)))

        [ -z "$image_link" ] && image_link="$(grep "$media_id" "$tmp_dir/image_links" | cut -f1)"
        sleep 2

        while :; do
            if command -v nc >/dev/null 2>&1 && [ -S "$lobster_socket" ] 2>/dev/null; then
                position=$(echo '{ "command": ["get_property", "time-pos"] }' | nc -U "$lobster_socket" 2>/dev/null | head -1)
                [ -z "$position" ] && break
                position=$(printf "%s" "$position" | sed -nE "s@.*\"data\":([0-9]*)\..*@\1@p")
                position=$(printf "%02d:%02d:%02d" $((position / 3600)) $((position % 3600 / 60)) $((position % 60)))
                update_rich_presence "$(printf "%s / %s" "$position" "$total")" &
            else
                # Fallback method if nc or Unix domain sockets are not available
                sleep 5
                update_rich_presence "Watching" &
            fi
            sleep 0.5
        done

        rpc_cleanup
    }
    save_progress() {
        position=$(cat "$watchlater_dir/"* 2>/dev/null | grep -A1 "$video_link" | $sed -nE "s@start=([0-9.]*)@\1@p" | cut -d'.' -f1)
        if [ -n "$position" ]; then
            progress=$((position * 100 / total_duration))
            position=$(printf "%02d:%02d:%02d" $((position / 3600)) $((position / 60 % 60)) $((position % 60)))
            send_notification "Stopped at" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$position"
        fi
    }
    play_video() {
        [ "$media_type" = "tv" ] && displayed_title="$title - $season_title - $episode_title" || displayed_title="$title"
        case $player in
            iina | celluloid)
                if [ -n "$subs_links" ]; then
                    [ "$player" = "iina" ] && iina --no-stdin --keep-running --mpv-sub-files="$subs_links" --mpv-force-media-title="$displayed_title" "$video_link"
                    [ "$player" = "celluloid" ] && celluloid --mpv-sub-files="$subs_links" --mpv-force-media-title="$displayed_title" "$video_link" 2>/dev/null
                else
                    [ "$player" = "iina" ] && iina --no-stdin --keep-running --mpv-force-media-title="$displayed_title" "$video_link"
                    [ "$player" = "celluloid" ] && celluloid --mpv-force-media-title="$displayed_title" "$video_link" 2>/dev/null
                fi
                ;;
            vlc)
                vlc_subs_links=$(printf "%s" "$subs_links" | sed 's/https\\:/https:/g; s/:\([^\/]\)/#\1/g')
                vlc "$video_link" --meta-title "$displayed_title" --input-slave="$vlc_subs_links"
                ;;
            mpv | mpv.exe)
                [ -z "$continue_choice" ] && check_history
                player_cmd="$player"
                [ -n "$resume_from" ] && player_cmd="$player_cmd --start='$resume_from'"
                [ -n "$subs_links" ] && player_cmd="$player_cmd $subs_arg='$subs_links'"
                player_cmd="$player_cmd --force-media-title='$displayed_title' '$video_link'"
                case "$(uname -s)" in
                    MINGW* | *Msys) player_cmd="$player_cmd --write-filename-in-watch-later-config --save-position-on-quit --quiet" ;;
                    *) player_cmd="$player_cmd --watch-later-dir='$watchlater_dir' --write-filename-in-watch-later-config --save-position-on-quit --quiet" ;;
                esac

                # Check if the system supports Unix domain sockets
                if command -v nc >/dev/null 2>&1 && [ -S "$lobster_socket" ] 2>/dev/null; then
                    player_cmd="$player_cmd --input-ipc-server='$lobster_socket'"
                fi

                # Use eval to properly handle spaces in the command
                eval "$player_cmd" >&3 &

                if [ -z "$quality" ]; then
                    link=$(printf "%s" "$video_link" | $sed "s/\/playlist.m3u8/\/1080\/index.m3u8/g")
                else
                    link=$video_link
                fi

                content=$(curl -s "$link")
                durations=$(printf "%s" "$content" | grep -oE 'EXTINF:[0-9.]+,' | cut -d':' -f2 | tr -d ',')
                total_duration=$(printf "%s" "$durations" | xargs echo | awk '{for(i=1;i<=NF;i++)sum+=$i} END {print sum}' | cut -d'.' -f1)

                [ "$discord_presence" = "true" ] && update_discord_presence
                wait
                save_progress
                ;;
            mpv_android) nohup am start --user 0 -a android.intent.action.VIEW -d "$video_link" -n is.xyz.mpv/.MPVActivity -e "title" "$displayed_title" >/dev/null 2>&1 & ;;
            *yncpla*) nohup "syncplay" "$video_link" -- --force-media-title="${displayed_title}" >/dev/null 2>&1 & ;;
            *) $player "$video_link" ;;
        esac
    }

    ### Misc ###
    update_script() {
        which_lobster="$(command -v lobster)"
        [ -z "$which_lobster" ] && send_notification "Can't find lobster in PATH"
        [ -z "$which_lobster" ] && exit 1
        update=$(curl -s "https://raw.githubusercontent.com/justchokingaround/lobster/main/lobster.sh" || exit 1)
        update="$(printf '%s\n' "$update" | diff -u "$which_lobster" -)"
        if [ -z "$update" ]; then
            send_notification "Script is up to date :)"
        else
            if printf '%s\n' "$update" | patch "$which_lobster" -; then
                send_notification "Script has been updated!"
            else
                send_notification "Can't update for some reason!"
            fi
        fi
        exit 0
    }
    # download_video [url] [title] [download_dir] [json_data] [thumbnail_file (only when image_preview is enabled)]
    download_video() {
        title="$(printf "%s" "$2" | tr -d ':/')"
        dir="${3}/${title}"
        # ik this is dumb idc
        language=$(printf "%s" "$4" | sed -nE "s@.*\"file\":\"[^\"]*\".*\"label\":\"(.$subs_language)[,\"\ ].*@\1@p")
        num_subs="$(printf "%s" "$subs_links" | sed 's/:\([^\/]\)/\n\\1/g' | wc -l)"
        ffmpeg_subs_links=$(printf "%s" "$subs_links" | sed 's/:\([^\/]\)/\nh/g; s/\\:/:/g' | while read -r sub_link; do
            printf " -i %s" "$sub_link"
        done)
        sub_ops="$ffmpeg_subs_links -map 0:v -map 0:a"
        if [ "$num_subs" -eq 0 ]; then
            sub_ops=" -i $subs_links -map 0:v -map 0:a -map 1"
            ffmpeg_meta="-metadata:s:s:0 language=$language"
        else
            i=1
            for i in $(seq 1 "$num_subs"); do
                ffmpeg_maps="$ffmpeg_maps -map $i"
                ffmpeg_meta="$ffmpeg_meta -metadata:s:s:$((i - 1)) language=$(printf "%s_%s" "$language" "$i")"
                i=$((i + 1))
            done
        fi

        sub_ops="$sub_ops $ffmpeg_maps -c:v copy -c:a copy -c:s srt $ffmpeg_meta"
        # shellcheck disable=SC2086
        ffmpeg -loglevel error -stats -i "$1" $sub_ops -c copy "$dir.mkv"
    }
    choose_from_trending_or_recent() {
        path=$1
        section=$2
        if [ "$path" = "home" ]; then
            response=$(curl -s "https://${base}/${path}" | $sed -n "/id=\"${section}\"/,/class=\"block_area block_area_home section-id-02\"/p" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
                $sed -nE "s@.*img data-src=\"([^\"]*)\".*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\1\t\3\t\2\t\4 [\5]@p" | $hxunent)
        else
            response=$(curl -s "https://${base}/${path}" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
                $sed -nE "s@.*img data-src=\"([^\"]*)\".*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\1\t\3\t\2\t\4 [\5]@p" | $hxunent)
        fi
        main
    }

    ### Main ###
    loop() {
        while [ "$keep_running" = "true" ]; do
            get_embed
            [ -z "$embed_link" ] && exit 1
            get_json
            [ -z "$video_link" ] && exit 1
            if [ "$download" = "true" ]; then
                if [ "$media_type" = "movie" ]; then
                    if [ "$image_preview" = "true" ]; then
                        download_video "$video_link" "$title" "$download_dir" "$json_data" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" &
                        send_notification "Finished downloading" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$title"
                    else
                        download_video "$video_link" "$title" "$download_dir" "$json_data" &
                        send_notification "Finished downloading" "5000" "" "$title"
                    fi
                else
                    if [ "$image_preview" = "true" ]; then
                        download_video "$video_link" "$title - $season_title - $episode_title" "$download_dir" "$json_data" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" &
                        send_notification "Finished downloading" "5000" "$images_cache_dir/  $title - $season_title - $episode_title ($media_type)  $media_id.jpg" "$title - $season_title - $episode_title"
                    else
                        download_video "$video_link" "$title - $season_title - $episode_title" "$download_dir" "$json_data" &
                        send_notification "Finished downloading" "5000" "" "$title - $season_title - $episode_title"
                    fi
                fi
                exit
            fi
            if [ "$discord_presence" = "true" ]; then
                [ -p "$presence" ] || mkfifo "$presence"
                rm -f "$handshook" >/dev/null
                tail -f "$presence" | nc -U "$discord_ipc" >"$ipclog" &
                update_rich_presence "00:00:00" &
            fi
            play_video
            if [ -n "$position" ] && [ "$history" = "true" ]; then
                save_history
            fi
            prompt_to_continue
            case "$continue_choice" in
                "Next episode")
                    resume_from=""
                    next_episode_exists
                    if [ -n "$next_episode" ]; then
                        episode_title=$(printf "%s" "$next_episode" | cut -f1)
                        data_id=$(printf "%s" "$next_episode" | cut -f2)
                        episode_id=$(curl -s "https://${base}/ajax/v2/episode/servers/${data_id}" | $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' | $sed -nE "s@.*data-id=\"([0-9]*)\".*title=\"([^\"]*)\".*@\1\t\2@p" | grep "$provider" | cut -f1)
                        send_notification "Watching the next episode" "5000" "" "$episode_title"
                    else
                        send_notification "No more episodes" "5000" "" "$title"
                        exit 0
                    fi
                    continue
                    ;;
                "Replay episode")
                    resume_from=""
                    continue
                    ;;
                "Search")
                    rm -f "$images_cache_dir"/*
                    query=""
                    response=""
                    season_id=""
                    episode_id=""
                    episode_title=""
                    title=""
                    data_id=""
                    resume_from=""
                    main
                    ;;
                *) keep_running="false" && exit ;;
            esac
        done
    }
    main() {
        if [ -z "$response" ]; then
            [ -z "$query" ] && get_input
            search "$query"
            [ -z "$response" ] && exit 1
        fi
        if [ "$image_preview" = "true" ]; then
            if [ "$use_external_menu" = "false" ] && [ "$use_ueberzugpp" = "true" ]; then
                command -v "ueberzugpp" >/dev/null || send_notification "Please install ueberzugpp if you want to use it for image previews"
                use_ueberzugpp="false"
            fi
            download_thumbnails "$response" "3"
            select_desktop_entry ""
        else
            if [ "$use_external_menu" = "true" ]; then
                choice=$(printf "%s" "$response" | rofi -dmenu -i -p "" -mesg "Choose a Movie or TV Show" -display-columns 4)
            else
                choice=$(printf "%s" "$response" | fzf --reverse --with-nth 4 -d "\t" --header "Choose a Movie or TV Show")
            fi
            image_link=$(printf "%s" "$choice" | cut -f1)
            media_id=$(printf "%s" "$choice" | cut -f2)
            title=$(printf "%s" "$choice" | $sed -nE "s@.* *(tv|movie)[[:space:]]*(.*) \[.*\]@\2@p")
            media_type=$(printf "%s" "$choice" | $sed -nE "s@.* *(tv|movie)[[:space:]]*(.*) \[.*\]@\1@p")
        fi
        [ "$media_type" = "tv" ] && choose_episode
        keep_running="true"
        loop
    }

    configuration

    # Edge case for Windows and Android, just exits with dep_ch's error message if it can't find mpv.exe or not on Android either
    if [ "$player" = "mpv" ] && ! command -v mpv >/dev/null; then
        if command -v mpv.exe >/dev/null; then
            player="mpv.exe"
        elif uname -a | grep -q "ndroid" 2>/dev/null; then
            player="mpv_android"
        else
            dep_ch mpv.exe
        fi
    fi

    [ "$debug" = "true" ] && set -x
    query=""
    # Command line arguments parsing
    while [ $# -gt 0 ]; do
        case "$1" in
            --)
                shift
                query="$*"
                break
                ;;
            # TODO: don't immediately exit if --continue is passed, since this ignores other arguments as soon as -c or --continue is found
            -c | --continue) play_from_history && exit ;;
            --discord | --discord-presence | --rpc | --presence) discord_presence="true" && shift ;;
            -d | --download)
                download="true"
                if [ -n "$download_dir" ]; then
                    shift
                else
                    download_dir="$2"
                    if [ -z "$download_dir" ]; then
                        download_dir="$PWD"
                        shift
                    else
                        if [ "${download_dir#-}" != "$download_dir" ]; then
                            download_dir="$PWD"
                            shift
                        else
                            shift 2
                        fi
                    fi
                fi
                ;;
            -h | --help) usage && exit 0 ;;
            -i | --image-preview) image_preview="true" && shift ;;
            -j | --json) json_output="true" && shift ;;
            -l | --language)
                subs_language="$2"
                if [ -z "$subs_language" ]; then
                    subs_language="english"
                    shift
                else
                    if [ "${subs_language#-}" != "$subs_language" ]; then
                        subs_language="english"
                        shift
                    else
                        subs_language="$(echo "$subs_language" | cut -c2-)"
                        shift 2
                    fi
                fi
                ;;
            --rofi | --external-menu) use_external_menu="true" && shift ;;
            -p | --provider)
                provider="$2"
                if [ -z "$provider" ]; then
                    provider="Vidcloud"
                    shift
                else
                    if [ "${provider#-}" != "$provider" ]; then
                        provider="Vidcloud"
                        shift
                    else
                        shift 2
                    fi
                fi
                ;;
            -q | --quality)
                quality="$2"
                if [ -z "$quality" ]; then
                    quality="1080"
                    shift
                else
                    if [ "${quality#-}" != "$quality" ]; then
                        quality="1080"
                        shift
                    else
                        shift 2
                    fi
                fi
                ;;
            -r | --recent)
                recent="$2"
                if [ -z "$recent" ]; then
                    recent="movie"
                    shift
                else
                    if [ "${recent#-}" != "$recent" ]; then
                        recent="movie"
                        shift
                    else
                        shift 2
                    fi
                fi
                ;;
            -s | --syncplay) player="syncplay" && shift ;;
            -t | --trending) trending="1" && shift ;;
            -u | -U | --update) update_script ;;
            -v | -V | --version) send_notification "Lobster Version: $LOBSTER_VERSION" && exit 0 ;;
            -x | --debug)
                set -x
                debug="true"
                shift
                ;;
            *)
                if [ "${1#-}" != "$1" ]; then
                    query="$query $1"
                else
                    query="$query $1"
                fi
                shift
                ;;
        esac
    done
    query="$(printf "%s" "$query" | tr ' ' '-' | $sed "s/^-//g")"
    if [ "$image_preview" = "true" ]; then
        test -d "$images_cache_dir" || mkdir -p "$images_cache_dir"
        if [ "$use_external_menu" = "true" ]; then
            mkdir -p "$tmp_dir/applications/"
            [ ! -L "$applications" ] && ln -sf "$tmp_dir/applications/" "$applications"
        fi
    fi
    [ -z "$provider" ] && provider="Vidcloud"
    [ "$trending" = "1" ] && choose_from_trending_or_recent "home" "trending-movies"
    [ "$recent" = "movie" ] && choose_from_trending_or_recent "movie" ""
    [ "$recent" = "tv" ] && choose_from_trending_or_recent "tv-show" ""

    main

} 2>&1 | tee "$lobster_logfile" >&3 2>&4
exec 1>&3 2>&4
