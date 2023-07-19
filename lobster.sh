#!/bin/sh

LOBSTER_VERSION="4.0.8"

config_file="$HOME/.config/lobster/lobster_config.txt"
lobster_editor=${VISUAL:-${EDITOR}}
base_helper_url="https://9anime.eltik.net"
fmovies_provider="Vidstream"

if [ "$1" = "--edit" ] || [ "$1" = "-e" ]; then
    if [ -f "$config_file" ]; then
        #shellcheck disable=1090
        . "${config_file}"
        [ -z "$lobster_editor" ] && lobster_editor="vim"
        "$lobster_editor" "$config_file"
    else
        printf "No configuration file found. Would you like to generate a default one? [y/N] " && read -r generate
        case "$generate" in
            "Yes" | "yes" | "y" | "Y")
                [ ! -d "$HOME/.config/lobster" ] && mkdir -p "$HOME/.config/lobster"
                printf "Getting the latest example config from github...\n"
                curl -s "https://raw.githubusercontent.com/justchokingaround/lobster/main/examples/lobster_config.txt" -o "$config_file"
                printf "New config generated!\n"
                #shellcheck disable=1090
                . "${config_file}"
                [ -z "$lobster_editor" ] && lobster_editor="vim"
                "$lobster_editor" "$config_file"
                ;;
            *) exit 0 ;;
        esac
    fi
    exit 0
fi

if [ "$1" = "--clear-history" ] || [ "$1" = "--delete-history" ]; then
    while true; do
        printf "This will delete your lobster history. Are you sure? [Y/n] "
        read -r choice
        case $choice in
            [Yy]* | "")
                #shellcheck disable=1090
                [ -f "$config_file" ] && . "$config_file"
                [ -z "$histfile" ] && histfile="$HOME/.local/share/lobster/lobster_history.txt"
                rm "$histfile"
                echo "History deleted."
                exit 0
                ;;
            [Nn]*)
                return 1
                ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
fi

cleanup() {
    [ "$debug" != 1 ] && rm -rf /tmp/lobster/ 2>/dev/null
    [ "$remove_tmp_lobster" = 1 ] && rm -rf /tmp/lobster/ 2>/dev/null
    if [ "$image_preview" = "1" ] && [ "$use_external_menu" = "0" ]; then
        killall ueberzugpp 2>/dev/null
        rm /tmp/ueberzugpp-* 2>/dev/null
    fi
    set +x && exec 2>&-
}
trap cleanup EXIT INT TERM

{
    applications="$HOME/.local/share/applications/lobster"
    images_cache_dir="/tmp/lobster/lobster-images"
    tmp_position="/tmp/lobster_position"
    case "$(uname -s)" in
        MINGW* | *Msys) separator=';' && path_thing='' && sed="sed" ;;
        *arwin) sed="gsed" ;;
        *) separator=':' && path_thing="\\" && sed="sed" ;;
    esac

    command -v notify-send >/dev/null 2>&1 && notify="true" || notify="false"
    send_notification() {
        [ "$json_output" = "1" ] && return
        if [ "$use_external_menu" = "0" ] || [ "$use_external_menu" = "" ]; then
            [ -z "$4" ] && printf "\33[2K\r\033[1;34m%s\n\033[0m" "$1" && return
            [ -n "$4" ] && printf "\33[2K\r\033[1;34m%s - %s\n\033[0m" "$1" "$4" && return
        fi
        [ -z "$2" ] && timeout=3000 || timeout="$2"
        if [ "$notify" = "true" ]; then
            [ -z "$3" ] && notify-send "$1" "$4" -t "$timeout" -h string:x-dunst-stack-tag:vol
            [ -n "$3" ] && notify-send "$1" "$4" -t "$timeout" -i "$3" -h string:x-dunst-stack-tag:vol
        fi
    }
    if command -v "hxunent" >/dev/null; then
        hxunent="hxunent"
    else
        hxunent="tee /dev/null"
    fi
    dep_ch() {
        for dep; do
            command -v "$dep" >/dev/null || send_notification "Program \"$dep\" not found. Please install it."
            command -v "$dep" >/dev/null || exit 1
        done
    }
    dep_ch "grep" "$sed" "curl" "fzf" "mpv" || true
    if [ "$use_external_menu" = "1" ]; then
        dep_ch "rofi" || true
    fi

    configuration() {
        [ -n "$XDG_CONFIG_HOME" ] && config_dir="$XDG_CONFIG_HOME/lobster" || config_dir="$HOME/.config/lobster"
        [ -n "$XDG_DATA_HOME" ] && data_dir="$XDG_DATA_HOME/lobster" || data_dir="$HOME/.local/share/lobster"
        [ ! -d "$config_dir" ] && mkdir -p "$config_dir"
        [ ! -d "$data_dir" ] && mkdir -p "$data_dir"
        #shellcheck disable=1090
        [ -f "$config_file" ] && . "${config_file}"
        [ -z "$base" ] && base="flixhq.to"
        [ -z "$player" ] && player="mpv"
        [ -z "$download_dir" ] && download_dir="$PWD"
        [ -z "$provider" ] && provider="UpCloud"
        [ -z "$history" ] && history=0
        [ -z "$subs_language" ] && subs_language="english"
        subs_language="$(printf "%s" "$subs_language" | cut -c2-)"
        [ -z "$histfile" ] && histfile="$data_dir/lobster_history.txt" && mkdir -p "$(dirname "$histfile")"
        [ -z "$use_external_menu" ] && use_external_menu="0"
        [ -z "$image_preview" ] && image_preview="0"
        [ -z "$debug" ] && debug=0
        [ -z "$preview_window_size" ] && preview_window_size=up:60%:wrap
        [ -z "$ueberzug_x" ] && ueberzug_x=10
        [ -z "$ueberzug_y" ] && ueberzug_y=3
        [ -z "$ueberzug_max_width" ] && ueberzug_max_width=$(($(tput lines) / 2))
        [ -z "$ueberzug_max_height" ] && ueberzug_max_height=$(($(tput lines) / 2))
        [ -z "$remove_tmp_lobster" ] && remove_tmp_lobster=1
        [ -z "$json_output" ] && json_output=0
    }

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

    launcher() {
        case "$use_external_menu" in
            1)
                [ -z "$2" ] && rofi -sort -dmenu -i -width 1500 -p "" -mesg "$1"
                [ -n "$2" ] && rofi -sort -dmenu -i -width 1500 -p "" -mesg "$1" -display-columns "$2"
                ;;
            *)
                [ -z "$2" ] && fzf --cycle --reverse --prompt "$1"
                [ -n "$2" ] && fzf --cycle --reverse --prompt "$1" --with-nth "$2" -d "\t"
                ;;
        esac
    }

    nth() {
        stdin=$(cat -)
        [ -z "$stdin" ] && return 1
        prompt="$1"
        [ $# -ne 1 ] && shift
        line=$(printf "%s" "$stdin" | $sed -nE "s@^(.*)\t[0-9:]*\t[0-9a-z/-]*\t(tv|movie|series|cartoons|films)(.*)@\1 (\2)\t\3@p" | cut -f1-3,6,7 | tr '\t' '|' | launcher "$prompt" | cut -d "|" -f 1)
        [ -n "$line" ] && printf "%s" "$stdin" | $sed -nE "s@^$line\t(.*)@\1@p" || exit 1
    }

    prompt_to_continue() {
        if [ "$media_type" = "tv" ] || [ "$media_type" = "series" ] || [ "$media_type" = "cartoons" ]; then
            continue_choice=$(printf "Next episode\nReplay episode\nChange quality\nExit\nSearch" | launcher "Select: ")
        else
            continue_choice=$(printf "Exit\nSearch" | launcher "Select: ")
        fi
    }

    usage() {
        printf "
  Usage: %s [options] [query]
  If a query is provided, it will be used to search for a Movie/TV Show

  Options:
    -c, --continue
      Continue watching from current history
    --clear-history, --delete-history
      Deletes history
    -d, --download [path]
      Downloads movie or episode that is selected (if no path is provided, it defaults to the current directory)
    -e, --edit
      Edit config file using an editor defined with lobster_editor in the config (\$EDITOR by default)
    -h, --help
      Show this help message and exit
    -i, --image-preview
      Shows image previews during media selection (requires ueberzugpp to be installed to work with fzf)
    -j, --json
      Outputs the json containing video links, subtitle links, referrers etc. to stdout
    -l, --language [language]
      Specify the subtitle language (if no language is provided, it defaults to english)
    --rofi, --dmenu, --external-menu
      Use rofi instead of fzf
    -p, --provider
      Specify the provider to watch from (if no provider is provided, it defaults to UpCloud) (currently supported: Upcloud, Vidcloud)
    -q, --quality
      Specify the video quality (if no quality is provided, it defaults to 1080)
    --quiet
      Suppress the output from mpv when playing a video
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
      Enable debug mode (prints out debug info to stdout and also saves it to /tmp/lobster.log)

  Note: 
    All arguments can be specified in the config file as well.
    If an argument is specified in both the config file and the command line, the command line argument will be used.

  Some example usages:
    ${0##*/} -i a silent voice --rofi
    ${0##*/} -l spanish -q 720 fight club -i -d
    ${0##*/} -l spanish blade runner --json

" "${0##*/}"
    }

    get_input() {
        if [ "$use_external_menu" = "0" ]; then
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

    download_thumbnails() {
        printf "%s\n" "$1" | while read -r cover_url id type title; do
            cover_url=$(printf "%s" "$cover_url" | sed -E 's/\/[[:digit:]]+x[[:digit:]]+\//\/1000x1000\//')
            curl -s -o "$images_cache_dir/  $title ($type)  $id.jpg" "$cover_url" &
            if [ "$use_external_menu" = "1" ]; then
                entry=/tmp/lobster/applications/"$id.desktop"
                generate_desktop "$title ($type)" "$images_cache_dir/  $title ($type)  $id.jpg" >"$entry" &
            fi
        done
        sleep "$2"
    }

    image_preview_fzf() {
        UB_PID_FILE="/tmp/lobster/.$(uuidgen)"
        if [ -z "$ueberzug_output" ]; then
            ueberzugpp layer --no-stdin --silent --use-escape-codes --pid-file "$UB_PID_FILE"
        else
            ueberzugpp layer -o "$ueberzug_output" --no-stdin --silent --use-escape-codes --pid-file "$UB_PID_FILE"
        fi
        UB_PID="$(cat "$UB_PID_FILE")"
        LOBSTER_UEBERZUG_SOCKET=/tmp/ueberzugpp-"$UB_PID".socket
        choice=$(find "$images_cache_dir" -type f -printf "%f\n" | fzf -i -q "$1" --cycle --preview-window="$preview_window_size" --preview="ueberzugpp cmd -s $LOBSTER_UEBERZUG_SOCKET -i fzfpreview -a add -x $ueberzug_x -y $ueberzug_y --max-width $ueberzug_max_width --max-height $ueberzug_max_height -f $images_cache_dir/{}" --reverse --with-nth 2 -d "  ")
        ueberzugpp cmd -s "$LOBSTER_UEBERZUG_SOCKET" -a exit
    }

    select_desktop_entry() {
        if [ "$use_external_menu" = "1" ]; then
            [ -n "$image_config_path" ] && choice=$(rofi -show drun -drun-categories lobster -filter "$1" -show-icons -theme "$image_config_path" | $sed -nE "s@.*/([0-9]*)\.desktop@\1@p") 2>/dev/null || choice=$(rofi -show drun -drun-categories lobster -filter "$1" -show-icons | $sed -nE "s@.*/([0-9]*)\.desktop@\1@p") 2>/dev/null
            media_id=$(printf "%s" "$choice" | cut -d\  -f1)
            title=$(printf "%s" "$choice" | $sed -nE "s@[0-9]* (.*) \((tv|movie)\)@\1@p")
            media_type=$(printf "%s" "$choice" | $sed -nE "s@[0-9]* (.*) \((tv|movie)\)@\2@p")
        else
            image_preview_fzf "$1"
            media_id=$(printf "%s" "$choice" | $sed -nE "s@.* ([0-9]*)\.jpg@\1@p")
            title=$(printf "%s" "$choice" | $sed -nE "s@[[:space:]]* (.*) \[.*\] \((tv|movie)\)  [0-9]*\.jpg@\1@p")
            media_type=$(printf "%s" "$choice" | $sed -nE "s@[[:space:]]* (.*) \[.*\] \((tv|movie)\)  [0-9]*\.jpg@\2@p")
        fi
    }

    hdrezka_data_and_translation_id() {
        data_id=$(printf "%s" "$media_id" | $sed -nE "s@[a-z]*/([0-9]*)-.*@\1@p")
        case "$media_type" in
            series | cartoons)
                default_translator_id=$(curl -s "https://${base}/${media_type}/$(printf "%s" "$media_id" | tr '=' '/').html" -A "uwu" --compressed |
                    sed -nE "s@.*initCDNSeriesEvents\(${data_id}\, ([0-9]*)\,.*@\1@p")
                ;;
            films)
                default_translator_id=$(curl -s "https://${base}/${media_type}/$(printf "%s" "$media_id" | tr '=' '/').html" -A "uwu" --compressed |
                    sed -nE "s@.*initCDNMoviesEvents\(${data_id}\, ([0-9]*)\,.*@\1@p")
                ;;
        esac
        translations=$(curl -s "https://${base}/${media_type}/$(printf "%s" "$media_id" | tr '=' '/').html" -A "uwu" --compressed |
            sed 's/b-translator__item/\n/g' | sed -nE "s@.*data-translator_id=\"([0-9]*)\"[^>]*>(.*)</li.*@\2\t\1@p" |
            sed 's/<img title="\([^\"]*\)" .*>\(.*\)/(\1)\2/;s/^\(.*\)<\/li><\/ul> <\/div>.*\t\([0-9]*\)/\1\t\2/')
        if [ -z "$translations" ]; then
            translator_id=$default_translator_id
        else
            if [ "$use_external_menu" = "1" ]; then
                translator_id=$(printf "%s" "$translations" | rofi -dmenu -p "" -mesg "Choose a translation" -display-columns 1 | cut -f2)
            else
                translator_id=$(printf "%s" "$translations" | fzf --cycle --reverse --with-nth 1 -d "\t" --header "Choose a translation" | cut -f2)
            fi
        fi
    }

    search() {
        case "$base" in
            "hdrezka.website")
                request=$(curl --max-time 10 -s "https://${base}/search/?do=search&subaction=search&q=${query}" -A "uwu" --compressed)
                status=$?
                if [ "$status" -eq 28 ]; then
                    send_notification "Request timed out"
                    exit 1
                fi
                if [ "$image_preview" = 1 ]; then
                    response=$(printf "%s" "$request" | sed "s/<img/\n/g" | sed -nE "s@.*src=\"([^\"]*)\".*<a href=\"https://hdrezka\.website/(.*)/(.*)/(.*)\.html\">([^<]*)</a> <div>([0-9]*).*@\1\t\3=\4\t\2\t\5 [\6]@p" | $hxunent)

                else
                    response=$(printf "%s" "$request" | sed "s/<img/\n/g" | sed -nE "s@.*src=\"[^\"]*\".*<a href=\"https://hdrezka\.website/(.*)/(.*)/(.*)\.html\">([^<]*)</a> <div>([0-9]*).*@\4 (\1) [\5]\t\2/\3@p" | $hxunent)
                fi
                ;;
            "flixhq.to")
                request=$(curl --max-time 10 -s "https://${base}/search/$query")
                status=$?
                if [ "$status" -eq 28 ]; then
                    send_notification "Request timed out"
                    exit 1
                fi
                if [ "$image_preview" = 1 ]; then
                    response=$(printf "%s" "$request" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
                        $sed -nE "s@.*img data-src=\"([^\"]*)\".*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\1\t\3\t\2\t\4 [\5]@p" | $hxunent)
                else
                    response=$(printf "%s" "$request" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
                        $sed -nE "s@.*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\3 (\1) [\4]\t\2@p" | $hxunent)
                fi
                ;;
            "fmovies.taxi")
                request=$(curl --max-time 10 -s "https://${base}/filter?keyword=$query")
                status=$?
                if [ "$status" -eq 28 ]; then
                    send_notification "Request timed out"
                    exit 1
                fi
                echo "$response"
                if [ "$image_preview" = 1 ]; then
                    notify-send "TODO"
                    exit
                else
                    response=$(printf "%s" "$request" | $sed ':a;N;$!ba;s/\n//g;s/class="item"/\n/g' |
                        $sed -nE "s@.*<span>([0-9]*)<\/span>.*class=\"type\">([^<]*)<.*href=\"([^\"]*)\">([^<]*)<.*@\4 (\2) [\1]\t\3@p" | $sed \$d | $hxunent)
                fi
                ;;
        esac
        [ -z "$response" ] && send_notification "Error" "1000" "" "No results found" && exit 1
    }

    choose_episode() {
        case "$base" in
            "flixhq.to")
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
                ;;
            "hdrezka.website")
                hdrezka_data_and_translation_id
                if [ -z "$season_id" ]; then
                    tmp_season_id=$(curl -s "https://${base}/${media_type}/${media_id}.html" -A "uwu" --compressed | $sed "s/<li/\n/g" |
                        $sed -nE "s@.*data-tab_id=\"([0-9]*)\">([^<]*)</li>.*@\2\t\1@p" | $hxunent | launcher "Select a season: " "1")
                    [ -z "$tmp_season_id" ] && exit 1
                    season_title=$(printf "%s" "$tmp_season_id" | cut -f1)
                    season_id=$(printf "%s" "$tmp_season_id" | cut -f2)
                    episode_id=$(curl -s -X POST "https://${base}/ajax/get_cdn_series/" -A "uwu" --data-raw "id=${data_id}&translator_id=${translator_id}&season=${season_id}&action=get_episodes" --compressed |
                        $sed "s/\\\//g;s/cdn_url/\n/g" |
                        $sed -nE "s@.*data-season_id=\"${season_id}\" data-episode_id=\"([0-9]*)\".*@\1@p" | $hxunent | launcher "Select an episode: " "1")
                    [ -z "$episode_id" ] && exit 1
                fi
                [ -z "$episode_title" ] && episode_title=$episode_id
                ;;
        esac
    }

    get_embed() {
        if [ "$media_type" = "movie" ]; then
            # request to get the episode id
            movie_page="https://${base}"$(curl -s "https://${base}/ajax/movie/episodes/${media_id}" |
                tr -d "\n" | $sed -nE "s_.*href=\"([^\"]*)\".*$provider.*_\1_p")
            episode_id=$(printf "%s" "$movie_page" | $sed -nE "s_.*-([0-9]*)\.([0-9]*)\$_\2_p")
        fi
        # request to get the embed
        embed_link=$(curl -s "https://flixhq.to/ajax/sources/${episode_id}" | $sed -nE "s_.*\"link\":\"([^\"]*)\".*_\1_p")
        if [ -z "$embed_link" ]; then
            send_notification "Error" "Could not get embed link"
            exit 1
        fi
    }

    extract_from_json() {
        case "$base" in
            "flixhq.to")
                json_key="file"
                encrypted=$(printf "%s" "$json_data" | tr "{}" "\n" | $sed -nE "s_.*\"${json_key}\":\"([^\"]*)\".*_\1_p" | grep "\.m3u8")
                if [ -n "$encrypted" ]; then
                    video_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | $sed -nE "s_.*\"${json_key}\":\"([^\"]*)\".*_\1_p" | head -1)
                else
                    json_key="sources"
                    encrypted=$(printf "%s" "$json_data" | tr "{}" "\n" | $sed -nE "s_.*\"${json_key}\":\"([^\"]*)\".*_\1_p")
                    key="$(curl -s "https://github.com/enimax-anime/key/blob/e${embed_type}/key.txt" | $sed -nE "s@.*\"rawBlob\":\"([^\"]*)\",.*@\1@p")"
                    encrypted_video_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | $sed -nE "s_.*\"sources\":\"([^\"]*)\".*_\1_p" | head -1)
                    # ty @CoolnsX for helping me with figuring out how to implement aes in openssl
                    video_link=$(printf "%s" "$encrypted_video_link" | base64 -d |
                        openssl enc -aes-256-cbc -d -md md5 -k "$key" 2>/dev/null | $sed -nE "s_.*\"${json_key}\":\"([^\"]*)\".*_\1_p")
                    json_data=$(printf "%s" "$json_data" | $sed -e "s|${encrypted_video_link}|${video_link}|")
                fi
                [ -n "$quality" ] && video_link=$(printf "%s" "$video_link" | $sed -e "s|/playlist.m3u8|/$quality/index.m3u8|")

                [ "$json_output" = "1" ] && printf "%s\n" "$json_data" && exit 0
                case "$json_key" in
                    file) subs_links=$(printf "%s" "$json_data" | tr "{}" "\n" | $sed -nE "s@\"${json_key}\":\"([^\"]*)\",\"label\":\"(.$subs_language)[,\"\ ].*@\1@p") ;;
                    sources) subs_links=$(printf "%s" "$json_data" | tr "{}" "\n" | $sed -nE "s@.*\"file\":\"([^\"]*)\",\"label\":\"(.$subs_language)[,\"\ ].*@\1@p") ;;
                esac
                subs_arg="--sub-file"
                num_subs=$(printf "%s" "$subs_links" | wc -l)
                if [ "$num_subs" -gt 0 ]; then
                    subs_links=$(printf "%s" "$subs_links" | $sed -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
                    subs_arg="--sub-files"
                fi
                [ -z "$subs_links" ] && send_notification "No subtitles found"
                ;;
            "hdrezka.website")
                encrypted_video_link=$(printf "%s" "$json_data" | sed -nE "s@.*\"url\":\"([^\"]*)\".*@\1@p" | sed "s/\\\//g" | cut -c'3-' | sed 's|//_//||g')
                # the part below is pain
                subs_links=$(printf "%s" "$json_data" | sed -nE "s@.*\"subtitle\":\"([^\"]*)\".*@\1@p" |
                    sed -e 's/\[[^]]*\]//g' -e 's/,/\n/g' -e 's/\\//g' -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
                subs_arg="--sub-files=$subs_links"

                # ty @CoolnsX for helping me out with the decryption
                table='ISE=,IUA=,IV4=,ISM=,ISQ=,QCE=,QEA=,QF4=,QCM=,QCQ=,XiE=,XkA=,Xl4=,XiM=,XiQ=,IyE=,I0A=,I14=,IyM=,IyQ=,JCE=,JEA=,JF4=,JCM=,JCQ=,ISEh,ISFA,ISFe,ISEj,ISEk,IUAh,IUBA,IUBe,IUAj,IUAk,IV4h,IV5A,IV5e,IV4j,IV4k,ISMh,ISNA,ISNe,ISMj,ISMk,ISQh,ISRA,ISRe,ISQj,ISQk,QCEh,QCFA,QCFe,QCEj,QCEk,QEAh,QEBA,QEBe,QEAj,QEAk,QF4h,QF5A,QF5e,QF4j,QF4k,QCMh,QCNA,QCNe,QCMj,QCMk,QCQh,QCRA,QCRe,QCQj,QCQk,XiEh,XiFA,XiFe,XiEj,XiEk,XkAh,XkBA,XkBe,XkAj,XkAk,Xl4h,Xl5A,Xl5e,Xl4j,Xl4k,XiMh,XiNA,XiNe,XiMj,XiMk,XiQh,XiRA,XiRe,XiQj,XiQk,IyEh,IyFA,IyFe,IyEj,IyEk,I0Ah,I0BA,I0Be,I0Aj,I0Ak,I14h,I15A,I15e,I14j,I14k,IyMh,IyNA,IyNe,IyMj,IyMk,IyQh,IyRA,IyRe,IyQj,IyQk,JCEh,JCFA,JCFe,JCEj,JCEk,JEAh,JEBA,JEBe,JEAj,JEAk,JF4h,JF5A,JF5e,JF4j,JF4k,JCMh,JCNA,JCNe,JCMj,JCMk,JCQh,JCRA,JCRe,JCQj,JCQk'

                for i in $(printf "%s" "$table" | tr ',' '\n'); do
                    encrypted_video_link=$(printf "%s" "$encrypted_video_link" | sed "s/$i//g")
                done

                video_links=$(printf "%s" "$encrypted_video_link" | sed 's/_//g' | base64 -d | tr ',' '\n' | sed -nE "s@\[([^\]*)\](.*)@\"\1\":\"\2\",@p")
                video_links_json=$(printf "%s" "$video_links" | tr -d '\n' | sed "s/,$//g")
                json_data=$(printf "%s" "$json_data" | $sed -E "s@\"url\":\"[^\"]*\"@\"url\":\{$video_links_json\}@")
                [ "$json_output" = "1" ] && printf "%s\n" "$json_data" && exit 0

                if [ -n "$quality" ]; then
                    video_link=$(printf "%s" "$video_links" | sed -nE "s@\"${quality}.*\":\".* or ([^\"]*)\".*@\1@p" | tail -1)
                else
                    video_link=$(printf "%s" "$video_links" | sed -nE "s@\".*\":\".* or ([^\"]*)\".*@\1@p" | tail -1)
                fi
                ;;
        esac
    }

    fmovies_helper() {
        curl -s "$base_helper_url/$1?query=$2&apikey=jerry" | $sed -nE "s@.*\"$3\":\"([^\"]*)\".*@\1@p"
    }

    get_json() {
        case "$base" in
            "flixhq.to")
                # get the juicy links
                parse_embed=$(printf "%s" "$embed_link" | $sed -nE "s_(.*)/embed-(4|6)/(.*)\?z=\$_\1\t\2\t\3_p")
                provider_link=$(printf "%s" "$parse_embed" | cut -f1)
                source_id=$(printf "%s" "$parse_embed" | cut -f3)
                embed_type=$(printf "%s" "$parse_embed" | cut -f2)
                json_data=$(curl -s "${provider_link}/ajax/embed-${embed_type}/getSources?id=${source_id}" -H "X-Requested-With: XMLHttpRequest")
                [ -n "$json_data" ] && extract_from_json
                ;;
            "hdrezka.website")
                case "$media_type" in
                    series | cartoons) json_data=$(curl -s -X POST "https://${base}/ajax/get_cdn_series/" -A "uwu" --data-raw "id=${data_id}&translator_id=${translator_id}&season=${season_id}&episode=${episode_id}&action=get_stream" --compressed) ;;
                    films)
                        hdrezka_data_and_translation_id
                        json_data=$(curl -s -X POST "https://${base}/ajax/get_cdn_series/" -A "uwu" --data-raw "id=${data_id}&translator_id=${translator_id}&action=get_movie" --compressed)
                        ;;
                esac
                [ -n "$json_data" ] && extract_from_json
                ;;
            "fmovies.taxi")
                case "$media_type" in
                    MOVIE)
                        reconstruct_id=$(printf "%s" "$media_id" | sed "s@=@/@g")
                        url="https://${base}${reconstruct_id}"
                        data_id=$(curl -s "$url" | sed -nE "s@.*data-id=\"([0-9]*)\" data-url.*@\1@p")

                        ep_list_vrf=$(fmovies_helper "fmovies-vrf" "$data_id" "url")
                        # ep_data_id=$(curl -s "https://fmovies.taxi/ajax/episode/list/$data_id?vrf=$ep_list_vrf" | sed "s/</\n/g;s/\\\//g" | sed -nE "s@.*data-id=\"([^\"]*)\".*@\1@p" | sed -n ${episode_number}p)
                        ep_data_id=$(curl -s "https://fmovies.taxi/ajax/episode/list/$data_id?vrf=$ep_list_vrf" | sed "s/</\n/g;s/\\\//g" | sed -nE "s@.*data-id=\"([^\"]*)\".*@\1@p" | sed -n ${episode_number}p)

                        server_list_vrf=$(fmovies_helper "fmovies-vrf" "$ep_data_id" "url")

                        provider_id=$(curl -s "https://fmovies.taxi/ajax/server/list/$ep_data_id?vrf=$server_list_vrf" | sed 's/li>/\n/g;s/\\//g' | sed -nE 's@.*data-link-id="([^"]*)".*Vidstream.*@\1@p')
                        provider_vrf=$(fmovies_helper "fmovies-vrf" "$provider_id" "url")

                        encrypted_provider_url=$(curl -s "https://fmovies.taxi/ajax/server/$provider_id?vrf=$provider_vrf" | sed "s/\\\//g" | sed -nE "s@.*\{\"url\":\"([^\"]*)\".*@\1@p")
                        provider_embed=$(fmovies_helper "fmovies-decrypt" "$encrypted_provider_url" "url")
                        provider_query=$(printf "%s" "$provider_embed" | sed -nE "s@.*/e/(.*)@\1@p")

                        case "$fmovies_provider" in
                            "Vidstream")
                                raw_url=$(fmovies_helper "rawvizcloud" "$provider_query" "rawURL")
                                json_data=$(curl -s "$raw_url" -e "$provider_embed" | sed "s/\\\//g")
                                ;;
                            "MyCloud")
                                raw_url=$(fmovies_helper "rawmcloud" "$provider_query" "rawURL")
                                json_data=$(curl -s "$raw_url" -e "$provider_embed" | sed "s/\\\//g")
                                ;;
                        esac
                        [ "$json_output" = "1" ] && printf "%s\n" "$json_data" && exit 0
                        video_link=$(printf "%s" "$json_data" | sed -nE "s@.*\"file\":\"([^\"]*)\".*@\1@p")
                        ;;
                esac
                ;;
        esac
    }

    check_history() {
        if [ ! -f "$histfile" ]; then
            [ "$image_preview" = "1" ] && send_notification "Now Playing" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$title"
            [ "$json_output" != "1" ] && send_notification "Now Playing" "5000" "" "$title"
            return
        fi
        case $media_type in
            movie | films | MOVIE)
                if grep -q "$media_id" "$histfile"; then
                    resume_from=$(grep "$media_id" "$histfile" | cut -f2)
                    send_notification "$episode_title" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$resume_from"
                else
                    send_notification "Now Playing" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$title"
                fi
                ;;
            tv | series | cartoons)
                if grep -q "$media_id" "$histfile"; then
                    if grep -q "$episode_id" "$histfile"; then
                        [ -z "$resume_from" ] && resume_from=$($sed -nE "s@.*\t([0-9:]*)\t${media_id}\t${media_type}\t${season_id}.*@\1@p" "$histfile")
                        send_notification "Ep: $episode_title" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$resume_from"
                    fi
                else
                    send_notification "Now Playing" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$displayed_title"
                fi
                ;;
            *) send_notification "This media type is not supported" ;;

        esac
    }

    play_video() {
        if [ "$media_type" = "tv" ] || [ "$media_type" = "series" ] || [ "$media_type" = "cartoons" ]; then
            displayed_title="$title - $season_title - $episode_title"
        else
            displayed_title="$title"
        fi
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
                vlc "$video_link" --meta-title "$displayed_title"
                ;;
            mpv)
                [ -z "$continue_choice" ] && check_history
                if [ "$history" = 1 ]; then
                    if [ -n "$subs_links" ]; then
                        if [ -n "$resume_from" ]; then
                            mpv --start="$resume_from" "$subs_arg"="$subs_links" --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error "$video_link" 2>&1 | tee "$tmp_position"
                        else
                            mpv "$subs_arg"="$subs_links" --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error "$video_link" 2>&1 | tee "$tmp_position"
                        fi
                    else
                        if [ -n "$resume_from" ]; then
                            mpv --start="$resume_from" --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error "$video_link" 2>&1 | tee "$tmp_position"
                        else
                            mpv --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error "$video_link" 2>&1 | tee "$tmp_position"
                        fi
                    fi

                    position=$($sed -nE "s@.*AV: ([0-9:]*) / ([0-9:]*) \(([0-9]*)%\).*@\1@p" "$tmp_position" | tail -1)
                    progress=$($sed -nE "s@.*AV: ([0-9:]*) / ([0-9:]*) \(([0-9]*)%\).*@\3@p" "$tmp_position" | tail -1)
                    [ -n "$position" ] && send_notification "Stopped at" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$position"

                else
                    if [ -n "$subs_links" ]; then
                        if [ "$quiet_output" = 1 ]; then
                            [ -z "$resume_from" ] && mpv "$subs_arg"="$subs_links" --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error "$video_link" >/dev/null 2>&1
                            [ -n "$resume_from" ] && mpv "$subs_arg"="$subs_links" --start="$resume_from" --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error "$video_link" >/dev/null 2>&1
                        else
                            [ -z "$resume_from" ] && mpv "$subs_arg"="$subs_links" --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error "$video_link"
                            [ -n "$resume_from" ] && mpv "$subs_arg"="$subs_links" --start="$resume_from" --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error "$video_link"
                        fi
                    else
                        if [ "$quiet_output" = 1 ]; then
                            [ -z "$resume_from" ] && mpv --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error "$video_link" >/dev/null 2>&1
                            [ -n "$resume_from" ] && mpv --start="$resume_from" --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error "$video_link" >/dev/null 2>&1
                        else
                            [ -z "$resume_from" ] && mpv --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error "$video_link"
                            [ -n "$resume_from" ] && mpv --start="$resume_from" --force-media-title="$displayed_title" --msg-level=ffmpeg/demuxer=error "$video_link"
                        fi
                    fi
                fi
                ;;
            *yncpla*) nohup "syncplay" "$video_link" -- --force-media-title="${displayed_title}" >/dev/null 2>&1 & ;;
            *) $player "$video_link" ;;
        esac
    }

    next_episode_exists() {
        case "$base" in
            "flixhq.to")
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
                ;;
            "hdrezka.website")

                next_episode=$(curl -s -X POST "https://${base}/ajax/get_cdn_series/" -A "uwu" --data-raw "id=${data_id}&translator_id=${translator_id}&season=${season_id}&action=get_episodes" --compressed |
                    $sed "s/\\\//g;s/cdn_url/\n/g" |
                    $sed -nE "s@.*data-season_id=\"${season_id}\" data-episode_id=\"([0-9]*)\".*@\1@p" | sed -n "$((episode_id + 1))p")
                [ -n "$next_episode" ] && return

                tmp_season_id=$(curl -s "https://${base}/${media_type}/${media_id}.html" -A "uwu" --compressed | $sed "s/<li/\n/g" |
                    $sed -nE "s@.*data-tab_id=\"([0-9]*)\">([^<]*)</li>.*@\2\t\1@p" | sed -n "$((season_id + 1))p")
                if [ -z "$tmp_season_id" ]; then
                    notify-send "TODO"
                    exit 1
                fi
                season_title=$(printf "%s" "$tmp_season_id" | cut -f1)
                season_id=$(printf "%s" "$tmp_season_id" | cut -f2)
                next_episode=$(curl -s -X POST "https://${base}/ajax/get_cdn_series/" -A "uwu" --data-raw "id=${data_id}&translator_id=${translator_id}&season=${season_id}&action=get_episodes" --compressed |
                    $sed "s/\\\//g;s/cdn_url/\n/g" |
                    $sed -nE "s@.*data-season_id=\"${season_id}\" data-episode_id=\"([0-9]*)\".*@\1@p" | head -1)
                [ -n "$next_episode" ] && return

                exit 1
                ;;
        esac
    }

    save_history() {
        case $media_type in
            movie)
                if [ "$progress" -gt "90" ]; then
                    $sed -i "/${media_id}\tmovie/d" "$histfile"
                    send_notification "Deleted from history" "5000" "" "$title"
                else
                    if grep -q -- "$media_id" "$histfile" 2>/dev/null; then
                        $sed -i "s|\t[0-9:]*\t$media_id|\t$position\t$media_id|1" "$histfile"
                    else
                        printf "%s\t%s\t%s\t%s\n" "$title" "$position" "$media_id" "$media_type" >>"$histfile"
                    fi
                fi
                ;;
            MOVIE)
                notify-send "TODO"
                ;;
            tv)
                if [ "$progress" -gt 90 ]; then
                    next_episode_exists
                    if [ -n "$next_episode" ]; then
                        episode_title=$(printf "%s" "$next_episode" | cut -f1)
                        data_id=$(printf "%s" "$next_episode" | cut -f2)
                        episode_id=$(curl -s "https://${base}/ajax/v2/episode/servers/${data_id}" | $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' | $sed -nE "s@.*data-id=\"([0-9]*)\".*title=\"([^\"]*)\".*@\1\t\2@p" | grep "$provider" | cut -f1)
                        if grep -q -- "$media_id" "$histfile" 2>/dev/null; then
                            $sed -i "s|\t[0-9:]*\t[0-9]*\ttv\t[0-9]*\t[0-9]*.*\t.*\t[0-9]*|\t00:00:00\t$media_id\ttv\t$season_id\t$episode_id\t$season_title\t$episode_title\t$data_id|1" "$histfile"
                            send_notification "Updated to next episode" "5000" "" "$episode_title"
                        else
                            printf "%s\t00:00:00\t%s\ttv\t%s\t%s\t%s\t%s\t%s\n" "$title" "$media_id" "$season_id" "$episode_id" "$season_title" "$episode_title" "$data_id" >>"$histfile"
                            send_notification "Added to history" "5000" "" "$episode_title"
                        fi
                    else
                        $sed -i "/${media_id}\ttv/d" "$histfile"
                        send_notification "Completed" "5000" "" "$title"
                    fi
                else
                    if grep -q -- "$media_id" "$histfile" 2>/dev/null; then
                        $sed -i "/${media_id}\ttv/d" "$histfile"
                    fi
                    printf "%s\t%s\t%s\ttv\t%s\t%s\t%s\t%s\t%s\n" "$title" "$position" "$media_id" "$season_id" "$episode_id" "$season_title" "$episode_title" "$data_id" >>"$histfile"
                fi
                ;;
            series | cartoons)
                if [ "$progress" -gt 90 ]; then
                    next_episode_exists
                    if [ -n "$next_episode" ]; then
                        [ -z "$episode_title" ] && episode_title=$episode_id
                        if grep -q -- "$media_id" "$histfile" 2>/dev/null; then
                            # TODO: check that this behavior is consistent with how flixhq handles this
                            $sed -i "s|\t[0-9:]*\t[a-zA-Z0-9/-]*\t[a-z]*\t[0-9]*\t[0-9]*\t[0-9]*.*\t.*\t[0-9a-z/-]*\t[0-9]*|\t00:00:00\t$media_id\t$media_type\t$season_id\t$next_episode\t$season_title\t$next_episode\t$data_id\t$translator_id|1" "$histfile"
                            send_notification "Updated progress to next episode" "5000" "" "$episode_id"
                        else
                            printf "%s\t00:00:00\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$title" "$media_id" "$media_type" "$season_id" "$next_episode" "$season_title" "$next_episode" "$data_id" "$translator_id" >>"$histfile"
                            send_notification "Added to history" "5000" "" "$episode_title"
                        fi
                    else
                        tmp_media_id=$(printf "%s" "$media_id" | sed -nE "s@.*/(.*)@\1@p")
                        $sed -i "/${tmp_media_id}\t$media_type/d" "$histfile"
                        send_notification "Completed" "5000" "" "$title"
                    fi
                else
                    if grep -q -- "$media_id" "$histfile" 2>/dev/null; then
                        tmp_media_id=$(printf "%s" "$media_id" | sed -nE "s@.*/(.*)@\1@p")
                        $sed -i "/${tmp_media_id}\t$media_type/d" "$histfile"
                    fi
                    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$title" "$position" "$media_id" "$media_type" "$season_id" "$episode_id" "$season_title" "$episode_title" "$data_id" "$translator_id" >>"$histfile"
                fi
                ;;
            *) notify-send "Error" "Unknown media type" ;;
        esac
    }

    download_video() {
        ffmpeg -loglevel error -stats -i "$1" -c copy "$3/$2".mp4

    }
    loop() {
        while [ "$keep_running" = "true" ]; do
            case "$base" in
                "flixhq.to") get_embed ;;
            esac
            if [ "$base" = "flixhq.to" ] && [ -z "$embed_link" ]; then
                exit 1
            fi
            get_json
            [ -z "$video_link" ] && exit 1
            if [ "$download" = "1" ]; then
                if [ "$media_type" = "movie" ]; then
                    if [ "$image_preview" = 1 ]; then
                        download_video "$video_link" "$title" "$download_dir" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" || exit 1
                        send_notification "Finished downloading" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$title"
                    else
                        download_video "$video_link" "$title" "$download_dir" || exit 1
                        send_notification "Finished downloading" "5000" "" "$title"
                    fi
                else
                    if [ "$image_preview" = 1 ]; then
                        download_video "$video_link" "$title - $season_title - $episode_title" "$download_dir" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" || exit 1
                        send_notification "Finished downloading" "5000" "$images_cache_dir/  $title - $season_title - $episode_title ($media_type)  $media_id.jpg" "$title - $season_title - $episode_title"
                    else
                        download_video "$video_link" "$title - $season_title - $episode_title" "$download_dir" || exit 1
                        send_notification "Finished downloading" "5000" "" "$title - $season_title - $episode_title"
                    fi
                fi
                exit
            fi
            play_video && wait
            [ "$history" = 1 ] && save_history
            prompt_to_continue
            case "$continue_choice" in
                "Next episode")
                    resume_from=""
                    [ "$history" = 0 ] && next_episode_exists
                    if [ -n "$next_episode" ]; then
                        case "$base" in
                            "flixhq.to")
                                episode_title=$(printf "%s" "$next_episode" | cut -f1)
                                data_id=$(printf "%s" "$next_episode" | cut -f2)
                                episode_id=$(curl -s "https://${base}/ajax/v2/episode/servers/${data_id}" | $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' | $sed -nE "s@.*data-id=\"([0-9]*)\".*title=\"([^\"]*)\".*@\1\t\2@p" | grep "$provider" | cut -f1)
                                send_notification "Watching the next episode" "5000" "" "$episode_title"
                                ;;
                            "hdrezka.website")
                                episode_title=$(printf "%s" "$next_episode" | cut -f1)
                                episode_id=$(printf "%s" "$next_episode" | cut -f2)
                                send_notification "Watching the next episode" "5000" "" "$episode_title"
                                ;;
                        esac
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
                "Change quality")
                    quality=$(printf "1080\n720\n480\n360" | launcher "Please select a quality: ")
                    continue
                    ;;
                "Search")
                    rm "$images_cache_dir"/*
                    rm "$tmp_position" 2>/dev/null
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
        if [ "$image_preview" = "1" ]; then
            if [ "$use_external_menu" = "0" ]; then
                command -v "ueberzugpp" >/dev/null || send_notification "Please install ueberzugpp if you want to use image preview with fzf"
            fi
            download_thumbnails "$response" "3"
            select_desktop_entry ""
        else
            [ "$use_external_menu" = "1" ] && choice=$(printf "%s" "$response" | rofi -dmenu -p "" -mesg "Choose a Movie or TV Show" -display-columns 1)
            [ "$use_external_menu" = "0" ] && choice=$(printf "%s" "$response" | fzf --cycle --reverse --with-nth 1 -d "\t" --header "Choose a Movie or TV Show")
            case "$base" in
                "flixhq.to")
                    title=$(printf "%s" "$choice" | $sed -nE "s@(.*) \((movie|tv)\).*@\1@p")
                    media_type=$(printf "%s" "$choice" | $sed -nE "s@(.*) \((movie|tv)\).*@\2@p")
                    media_id=$(printf "%s" "$choice" | cut -f2)
                    ;;
                "hdrezka.website")
                    title=$(printf "%s" "$choice" | $sed -nE "s@(.*) \((films|series|cartoons)\).*@\1@p")
                    media_type=$(printf "%s" "$choice" | $sed -nE "s@(.*) \((films|series|cartoons)\).*@\2@p")
                    media_id=$(printf "%s" "$choice" | cut -f2)
                    ;;
                "fmovies.taxi")
                    title=$(printf "%s" "$choice" | $sed -nE "s@(.*) \((MOVIE)\).*@\1@p")
                    media_type=$(printf "%s" "$choice" | $sed -nE "s@(.*) \((MOVIE)\).*@\2@p")
                    media_id=$(printf "%s" "$choice" | cut -f2 | sed "s@/@=@g")
                    ;;
            esac
        fi
        if [ "$media_type" = "tv" ] || [ "$media_type" = "cartoons" ] || [ "$media_type" = "series" ]; then
            choose_episode
        fi
        keep_running="true"
        loop
    }

    play_from_history() {
        [ ! -f "$histfile" ] && send_notification "No history file found" "5000" "" && exit 1
        [ "$watched_history" = 1 ] && exit 0
        watched_history=1
        choice=$($sed -n "1h;1!{x;H;};\${g;p;}" "$histfile" | nl -w 1 | nth "Choose an entry:")
        [ -z "$choice" ] && exit 1
        media_type=$(printf "%s" "$choice" | cut -f4)
        title=$(printf "%s" "$choice" | cut -f1)
        resume_from=$(printf "%s" "$choice" | cut -f2)
        if [ "$media_type" = "tv" ] || [ "$media_type" = "series" ] || [ "$media_type" = "cartoons" ]; then
            media_id=$(printf "%s" "$choice" | cut -f3)
            season_id=$(printf "%s" "$choice" | cut -f5)
            episode_id=$(printf "%s" "$choice" | cut -f6)
            season_title=$(printf "%s" "$choice" | cut -f7)
            episode_title=$(printf "%s" "$choice" | cut -f8)
        fi
        case "$media_type" in
            tv)
                data_id=$(printf "%s" "$choice" | cut -f9)
                choose_episode
                ;;
            series)
                base="hdrezka.website"
                data_id=$(printf "%s" "$choice" | cut -f9)
                translator_id=$(printf "%s" "$choice" | cut -f10)
                ;;
        esac
        keep_running="true" && loop
    }

    # TODO: remove code duplication
    choose_from_trending() {
        if [ "$image_preview" = "1" ]; then
            response=$(curl -s "https://${base}/home" | $sed -n '/id="trending-movies"/,/class="block_area block_area_home section-id-02"/p' | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
                $sed -nE "s@.*img data-src=\"([^\"]*)\".*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\1\t\3\t\2\t\4 [\5]@p" | $hxunent)
        else
            response=$(curl -s "https://${base}/home" | $sed -n '/id="trending-movies"/,/id="trending-tv"/p' | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
                $sed -nE "s@.*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\3 (\1) [\4]\t\2@p" | $hxunent)
        fi
        main
    }

    choose_from_recent_movie() {
        if [ "$image_preview" = "1" ]; then
            response=$(curl -s "https://${base}/movie" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
                $sed -nE "s@.*img data-src=\"([^\"]*)\".*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\1\t\3\t\2\t\4 [\5]@p" | $hxunent)
        else
            response=$(curl -s "https://${base}/movie" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
                $sed -nE "s@.*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\3 (\1) [\4]\t\2@p" | $hxunent)
        fi
        main
    }

    choose_from_recent_tv() {
        if [ "$image_preview" = "1" ]; then
            response=$(curl -s "https://${base}/tv-show" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
                $sed -nE "s@.*img data-src=\"([^\"]*)\".*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\1\t\3\t\2\t\4 [\5]@p" | $hxunent)
        else
            response=$(curl -s "https://${base}/tv-show" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
                $sed -nE "s@.*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\3 (\1) [\4]\t\2@p" | $hxunent)
        fi
        main
    }

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

    configuration
    [ "$debug" = 1 ] && set -x
    query=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --)
                shift
                query="$*"
                break
                ;;
            -c | --continue)
                play_from_history && exit
                ;;
            -d | --download)
                download="1"
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
            -h | --help)
                usage && exit 0
                ;;
            -i | --image-preview)
                image_preview="1"
                shift
                ;;
            -j | --json)
                json_output="1"
                shift
                ;;
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
            --rofi | --dmenu | --external-menu)
                use_external_menu=1
                shift
                ;;
            -p | --provider)
                provider="$2"
                if [ -z "$provider" ]; then
                    provider="UpCloud"
                    shift
                else
                    if [ "${provider#-}" != "$provider" ]; then
                        provider="UpCloud"
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
            --quiet)
                quiet_output="1"
                shift
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
            -s | --syncplay)
                player="syncplay"
                shift
                ;;
            -t | --trending)
                trending="1"
                shift
                ;;
            -u | -U | --update)
                update_script
                ;;
            -v | -V | --version)
                send_notification "Lobster Version: $LOBSTER_VERSION" && exit 0
                ;;
            -w | --website)
                base="$2"
                if [ -z "$base" ]; then
                    base="flixhq.to"
                    shift
                else
                    if [ "${base#-}" != "$base" ]; then
                        base="flixhq.to"
                        shift
                    else
                        shift 2
                    fi
                fi
                ;;
            -x | --debug)
                set -x
                debug=1
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
    case "$base" in
        "hdrezka") base="hdrezka.website" ;;
        "fmovies") base="fmovies.taxi" ;;
        *) base="flixhq.to" ;;
    esac
    case "$base" in
        "flixhq.to") query="$(printf "%s" "$query" | tr ' ' '-' | $sed "s/^-//g")" ;;
        "hdrezka.website" | "fmovies.taxi") query="$(printf "%s" "$query" | tr ' ' '+' | $sed "s/^+//g")" ;;
    esac
    if [ "$image_preview" = 1 ]; then
        test -d "$images_cache_dir" || mkdir -p "$images_cache_dir"
        if [ "$use_external_menu" = 1 ]; then
            mkdir -p "/tmp/lobster/applications/"
            [ ! -L "$applications" ] && ln -sf "/tmp/lobster/applications/" "$applications"
        fi
    fi
    [ -z "$provider" ] && provider="UpCloud"
    [ "$trending" = "1" ] && choose_from_trending
    [ "$recent" = "movie" ] && choose_from_recent_movie
    [ "$recent" = "tv" ] && choose_from_recent_tv

    main
} 2>&1 | tee /tmp/lobster.log 2>/dev/null
