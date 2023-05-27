#!/bin/sh

LOBSTER_VERSION="3.9.9"

config_file="$HOME/.config/lobster/lobster_config.txt"
lobster_editor=${VISUAL:-${EDITOR:-vim}}
case "$(uname -s)" in
MINGW* | *Msys) separator=';' && path_thing='' ;;
*arwin) sed="gsed" ;;
*) separator=':' && path_thing="\\" && sed="sed" ;;
esac

command -v notify-send >/dev/null 2>&1 && notify="true" || notify="false"
command -v socat >/dev/null 2>&1 && socat_exists="true" || socat_exists="false"
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
command -v "hxunent" >/dev/null || send_notification "Please install html-xml-utils\n"
dep_ch() {
  for dep; do
    command -v "$dep" >/dev/null || send_notification "Program \"$dep\" not found. Please install it."
    command -v "$dep" >/dev/null || exit 1
  done
}
dep_ch "grep" "$sed" "curl" "fzf" "mpv" "socat" || true
if [ "$use_external_menu" = "1" ]; then
  dep_ch "rofi" || true
fi

cleanup() {
  rm -rf "$images_cache_dir"
  rm -rf $applications_dir/*
  rm "$tmp_position" 2>/dev/null
}
trap cleanup EXIT INT TERM

configuration() {
  [ -n "$XDG_CONFIG_HOME" ] && config_dir="$XDG_CONFIG_HOME/lobster" || config_dir="$HOME/.config/lobster"
  [ -n "$XDG_DATA_HOME" ] && data_dir="$XDG_DATA_HOME/lobster" || data_dir="$HOME/.local/share/lobster"
  [ ! -d "$config_dir" ] && mkdir -p "$config_dir"
  [ ! -d "$data_dir" ] && mkdir -p "$data_dir"
  #shellcheck disable=1090
  [ -f "$config_file" ] && . "${config_file}"
  export X=$(($(tput cols) - 35))
  export Y=$(($(tput lines) / 6))
  [ -z "$base" ] && base="flixhq.to"
  [ -z "$player" ] && player="mpv"
  [ -z "$provider" ] && provider="UpCloud"
  [ -z "$history" ] && history=0
  [ -z "$subs_language" ] && subs_language="english"
  subs_language="$(printf "%s" "$subs_language" | cut -c2-)"
  [ -z "$histfile" ] && histfile="$data_dir/lobster_history.txt" && mkdir -p "$(dirname "$histfile")"
  [ -z "$use_external_menu" ] && use_external_menu="0"
  [ -z "$image_preview" ] && image_preview="0"
  [ -z "$images_cache_dir" ] && images_cache_dir="/tmp/lobster-images"
  [ -z "$applications_dir" ] && applications_dir="$HOME/.local/share/applications/lobster"
  [ -z "$tmp_position" ] && tmp_position="/tmp/lobster_position"
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
  0)
    [ -z "$2" ] && fzf --reverse --prompt "$1"
    [ -n "$2" ] && fzf --reverse --prompt "$1" --with-nth "$2" -d "\t"
    ;;
  1)
    [ -z "$2" ] && rofi -sort -dmenu -i -width 1500 -p "" -mesg "$1"
    [ -n "$2" ] && rofi -sort -dmenu -i -width 1500 -p "" -mesg "$1" -display-columns "$2"
    ;;
  esac
}

nth() {
  stdin=$(cat -)
  [ -z "$stdin" ] && return 1
  prompt="$1"
  [ $# -ne 1 ] && shift
  line=$(printf "%s" "$stdin" | $sed -nE "s@^(.*)\t[0-9:]*\t[0-9]*\t(tv|movie)(.*)@\1 (\2)\t\3@p" | cut -f1-3,6,7 --output-delimiter "|" | launcher "$prompt" | cut -d "|" -f 1)
  [ -n "$line" ] && printf "%s" "$stdin" | $sed -nE "s@^$line\t(.*)@\1@p" || exit 1
}

prompt_to_continue() {
  if [ "$media_type" = "tv" ]; then
    continue_choice=$(printf "Yes\nExit\nSearch" | launcher "Continue? ")
  else
    continue_choice=$(printf "Search\nExit" | launcher "Continue? ")
  fi
}

usage() {
  printf "
  Usage: %s [options] [query]
  If a query is provided, it will be used to search for a Movie/TV Show

  Options:

    -c, --continue
      Continue watching from current history
    -d, --download
      Downloads movie or episode that is selected
    -h, --help
      Show this help message and exit
    -e, --edit
      Edit config file using an editor defined with lobster_editor in the config (\$EDITOR by default)
    -p, --provider
      Specify the provider to watch from (default: Vidcloud) (currently supported: Vidcloud)
    -j, --json
      Outputs the json containing video links, subtitle links, referrers etc. to stdout
    -q, --quality
      Specify the video quality (default: 1080)
    --rofi, --dmenu, --external-menu
      Use rofi instead of fzf
    -t, --trending
      Lets you select from the most popular movies
    -r, --recent
      Lets you select from the most recent movies
    -i, --image-preview
      Shows image previews during media selection (requires ueberzugpp to be installed to work with fzf)
    -l, --language
      Specify the subtitle language
    -s, --syncplay
      Use Syncplay to watch with friends
    -u, -U, --update
      Update the script
    -v, -V, --version
      Show the version of the script

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
    query=$(printf "" | launcher "Search Movie/TV Show")
  fi
  [ -n "$query" ] && query=$(echo "$query" | tr ' ' '-')
  [ -z "$query" ] && send_notification "Error" "1000" "" "No query provided" && exit 1
}

download_thumbnails() {
  printf "%s\n" "$1" | while read -r cover_url id type title; do
    curl -s -o "$images_cache_dir/  $title ($type)  $id.jpg" "$cover_url" &
    if [ "$use_external_menu" = "1" ]; then
      entry="$applications_dir"/"$id.desktop"
      generate_desktop "$title ($type)" "$images_cache_dir/  $title ($type)  $id.jpg" >"$entry" &
    fi
  done
  wait && sleep "$2"
}

image_preview_fzf() {
  UB_PID_FILE="/tmp/.$(uuidgen)"
  ueberzugpp layer --no-stdin --silent --use-escape-codes --pid-file "$UB_PID_FILE"
  UB_PID="$(cat "$UB_PID_FILE")"
  export SOCKET=/tmp/ueberzugpp-"$UB_PID".socket
  choice=$(ls "$images_cache_dir"/* | fzf -i -q "$1" --print-query --preview='ueberzugpp cmd -s $SOCKET -i fzfpreview -a add -x $X -y $Y --max-width $FZF_PREVIEW_COLUMNS --max-height $FZF_PREVIEW_LINES -f {}' --reverse --with-nth 2 -d "  " --preview-window=30%)
  ueberzugpp cmd -s "$SOCKET" -a exit
}

select_desktop_entry() {
  if [ "$use_external_menu" = "1" ]; then
    [ -n "$image_config_path" ] && choice=$(rofi -show drun -drun-categories lobster -filter "$1" -show-icons -config "$image_config_path" | $sed -nE "s@.*/([0-9]*)\.desktop@\1@p") 2>/dev/null || choice=$(rofi -show drun -drun-categories lobster -filter "$1" -show-icons | $sed -nE "s@.*/([0-9]*)\.desktop@\1@p") 2>/dev/null
    media_id=$(printf "%s" "$choice" | cut -d\  -f1)
    title=$(printf "%s" "$choice" | $sed -nE "s@[0-9]* (.*) \((tv|movie)\)@\1@p")
    media_type=$(printf "%s" "$choice" | $sed -nE "s@[0-9]* (.*) \((tv|movie)\)@\2@p")
  else
    image_preview_fzf "$1"
    media_id=$(printf "%s" "$choice" | $sed -nE "s@.*\/  .*  ([0-9]*)\.jpg@\1@p")
    title=$(printf "%s" "$choice" | $sed -nE "s@.*\/  (.*) \[.*\] \((tv|movie)\)  [0-9]*\.jpg@\1@p")
    media_type=$(printf "%s" "$choice" | $sed -nE "s@.*\/  (.*) \[.*\] \((tv|movie)\)  [0-9]*\.jpg@\2@p")
  fi
}

search() {
  [ "$image_preview" = "1" ] && response=$(curl -s "https://${base}/search/$query" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
    $sed -nE "s@.*img data-src=\"([^\"]*)\".*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\1\t\3\t\2\t\4 [\5]@p" | hxunent)
  [ "$image_preview" = "0" ] && response=$(curl -s "https://${base}/search/$query" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
    $sed -nE "s@.*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\3 (\1) [\4]\t\2@p" | hxunent)
}

choose_episode() {
  if [ -z "$season_id" ]; then
    tmp_season_id=$(curl -s "https://${base}/ajax/v2/tv/seasons/${media_id}" | $sed -nE "s@.*href=\".*-([0-9]*)\">(.*)</a>@\2\t\1@p" | launcher "Select a season: " "1")
    [ -z "$tmp_season_id" ] && exit 1
    season_title=$(printf "%s" "$tmp_season_id" | cut -f1)
    season_id=$(printf "%s" "$tmp_season_id" | cut -f2)
    tmp_ep_id=$(curl -s "https://${base}/ajax/v2/season/episodes/${season_id}" | $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' |
      $sed -nE "s@.*data-id=\"([0-9]*)\".*title=\"([^\"]*)\">.*@\2\t\1@p" | hxunent | launcher "Select an episode: " "1")
    [ -z "$tmp_ep_id" ] && exit 1
  fi
  [ -z "$episode_title" ] && episode_title=$(printf "%s" "$tmp_ep_id" | cut -f1)
  [ -z "$data_id" ] && data_id=$(printf "%s" "$tmp_ep_id" | cut -f2)
  episode_id=$(curl -s "https://${base}/ajax/v2/episode/servers/${data_id}" | $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' |
    $sed -nE "s@.*data-id=\"([0-9]*)\".*title=\"([^\"]*)\".*@\1\t\2@p" | grep "$provider" | cut -f1)
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
}

extract_from_json() {
  encrypted=$(printf "%s" "$json_data" | tr "{}" "\n" | $sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p" | grep "\.m3u8")
  if [ -n "$encrypted" ]; then
    video_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | $sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p" | head -1)
  else
    key="$(curl -s "https://github.com/enimax-anime/key/blob/e${embed_type}/key.txt" | $sed -nE "s_.*js-file-line\">(.*)<.*_\1_p")"
    encrypted_video_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | $sed -nE "s_.*\"sources\":\"([^\"]*)\".*_\1_p" | head -1)
    video_link=$(printf "%s" "$encrypted_video_link" | base64 -d |
      openssl enc -aes-256-cbc -d -md md5 -k "$key" 2>/dev/null | $sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p")
    json_data=$(printf "%s" "$json_data" | $sed -e "s|${encrypted_video_link}|${video_link}|")
  fi
  [ -n "$quality" ] && video_link=$(printf "%s" "$video_link" | $sed -e "s|/playlist.m3u8|/$quality/index.m3u8|")

  [ "$json_output" = "1" ] && printf "%s\n" "$json_data" && exit 0
  subs_links=$(printf "%s" "$json_data" | tr "{}" "\n" | $sed -nE "s@\"file\":\"([^\"]*)\",\"label\":\"(.$subs_language)[,\"\ ].*@\1@p")
  subs_arg="--sub-file"
  [ $(printf "%s" "$subs_links" | wc -l) -gt 0 ] && subs_links=$(printf "%s" "$subs_links" | $sed -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//") && subs_arg="--sub-files=$subs_links"
  [ -z "$subs_links" ] && send_notification "No subtitles found"
}

get_json() {
  # get the juicy links
  parse_embed=$(printf "%s" "$embed_link" | $sed -nE "s_(.*)/embed-(4|6)/(.*)\?z=\$_\1\t\2\t\3_p")
  provider_link=$(printf "%s" "$parse_embed" | cut -f1)
  source_id=$(printf "%s" "$parse_embed" | cut -f3)
  embed_type=$(printf "%s" "$parse_embed" | cut -f2)
  json_data=$(curl -s "${provider_link}/ajax/embed-${embed_type}/getSources?id=${source_id}" -H "X-Requested-With: XMLHttpRequest")
  [ -n "$json_data" ] && extract_from_json
}

check_history() {
  [ -f "$histfile" ] || return
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
  esac
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
    vlc "$video_link" --meta-title "$displayed_title"
    ;;
  mpv)
    [ -z "$continue_choice" ] && check_history
    if [ "$history" = 1 ]; then
      if [ -n "$subs_links" ]; then
        if [ -n "$resume_from" ]; then
          nohup mpv --start="$resume_from" "$subs_arg"="$subs_links" --force-media-title="$displayed_title" --input-ipc-server=/tmp/mpvsocket "$video_link" >/dev/null 2>&1 &
        else
          nohup mpv --sub-file="$subs_links" --force-media-title="$displayed_title" --input-ipc-server=/tmp/mpvsocket "$video_link" >/dev/null 2>&1 &
        fi
      else
        if [ -n "$resume_from" ]; then
          nohup mpv --start="$resume_from" --force-media-title="$displayed_title" --input-ipc-server=/tmp/mpvsocket "$video_link" >/dev/null 2>&1 &
        else
          nohup mpv --force-media-title="$displayed_title" --input-ipc-server=/tmp/mpvsocket "$video_link" >/dev/null 2>&1 &
        fi
      fi
      if [ "$socat_exists" = "true" ]; then
        PID=$!
        while ! ps -p $PID >/dev/null; do
          sleep 0.1
        done
        sleep 2

        while ps -p $PID >/dev/null; do
          position=$(echo '{ "command": ["get_property", "time-pos"] }' | socat - /tmp/mpvsocket | $sed -nE "s@.*\"data\":([0-9\.]*),.*@\1@p")
          [ "$position" != "" ] && printf "%s\n" "$position" >>"$tmp_position"
          progress=$(echo '{ "command": ["get_property", "percent-pos"] }' | socat - /tmp/mpvsocket | $sed -nE "s@.*\"data\":([0-9\.]*),.*@\1@p")
          sleep 1
        done
        last_line=$($sed '/^$/d' "$tmp_position" | tail -1)
        position=$(date -u -d "@$(printf "%.0f" "$last_line")" "+%H:%M:%S")
        progress=$(printf "%.0f" "$progress")
        [ -n "$position" ] && send_notification "Stopped at" "5000" "$images_cache_dir/  $title ($media_type)  $media_id.jpg" "$position"
      fi
    else
      if [ -n "$subs_links" ]; then
        [ -z "$resume_from" ] && mpv "$subs_arg"="$subs_links" --force-media-title="$displayed_title" "$video_link"
        [ -n "$resume_from" ] && mpv --start="$resume_from" --force-media-title="$displayed_title" "$video_link"
      else
        [ -z "$resume_from" ] && mpv --force-media-title="$displayed_title" "$video_link"
        [ -n "$resume_from" ] && mpv --start="$resume_from" --force-media-title="$displayed_title" "$video_link"
      fi
    fi
    ;;
  *yncpla*) nohup "syncplay" "$video_link" -- --force-media-title="${displayed_title}" >/dev/null 2>&1 & ;;
  *) $player "$video_link" ;;
  esac
}

next_episode_exists() {
  episodes_list=$(curl -s "https://${base}/ajax/v2/season/episodes/${season_id}" | $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' |
    $sed -nE "s@.*data-id=\"([0-9]*)\".*title=\"([^\"]*)\">.*@\2\t\1@p" | hxunent)
  next_episode=$(printf "%s" "$episodes_list" | $sed -n "/$data_id/{n;p;}")
  [ -n "$next_episode" ] && return
  tmp_season_id=$(curl -s "https://${base}/ajax/v2/tv/seasons/${media_id}" | $sed -n "/href=\".*-$season_id/{n;n;n;n;p;}" | $sed -nE "s@.*href=\".*-([0-9]*)\">(.*)</a>@\2\t\1@p")
  [ -z "$tmp_season_id" ] && return
  season_title=$(printf "%s" "$tmp_season_id" | cut -f1)
  season_id=$(printf "%s" "$tmp_season_id" | cut -f2)
  next_episode=$(curl -s "https://${base}/ajax/v2/season/episodes/${season_id}" | $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' |
    $sed -nE "s@.*data-id=\"([0-9]*)\".*title=\"([^\"]*)\">.*@\2\t\1@p" | hxunent | head -1)
  [ -n "$next_episode" ] && return
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
      else
        printf "%s\t%s\t%s\t%s\n" "$title" "$position" "$media_id" "$media_type" >>"$histfile"
      fi
    fi
    ;;
  tv)
    if [ "$progress" -gt "90" ]; then
      next_episode_exists
      if [ -n "$next_episode" ]; then
        episode_title=$(printf "%s" "$next_episode" | cut -f1)
        data_id=$(printf "%s" "$next_episode" | cut -f2)
        episode_id=$(curl -s "https://${base}/ajax/v2/episode/servers/${data_id}" | $sed ':a;N;$!ba;s/\n//g;s/class="nav-item"/\n/g' | $sed -nE "s@.*data-id=\"([0-9]*)\".*title=\"([^\"]*)\".*@\1\t\2@p" | grep "$provider" | cut -f1)
        $sed -i "s|\t[0-9:]*\t[0-9]*\ttv\t[0-9]*\t[0-9]*.*\t.*\t[0-9]*|\t00:00:00\t$media_id\ttv\t$season_id\t$episode_id\t$season_title\t$episode_title\t$data_id|1" "$histfile"
        send_notification "Updated to next episode" "5000" "" "$episode_title"
      else
        $sed -i "/$episode_id/d" "$histfile"
        send_notification "Completed" "5000" "" "$title"
      fi
    else
      if grep -q -- "$media_id" "$histfile" 2>/dev/null; then
        $sed -i "/$media_id/d" "$histfile"
      fi
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$title" "$position" "$media_id" "$media_type" "$season_id" "$episode_id" "$season_title" "$episode_title" "$data_id" >>"$histfile"
    fi
    ;;
  esac
}

download_video() {
  ffmpeg -loglevel error -stats -i "$1" -c copy "$2".mp4
}

loop() {
  while [ "$keep_running" = "true" ]; do
    get_embed
    [ -z "$embed_link" ] && exit 1
    get_json
    [ -z "$video_link" ] && exit 1
    if [ "$download" = "1" ]; then
      if [ "$media_type" = "movie" ]; then
        download_video "$video_link" "$title" || exit 1
        send_notification "Finished downloading" "5000" "" "$title"
      else
        download_video "$video_link" "$title - $season_title - $episode_title" || exit 1
        send_notification "Finished downloading" "5000" "" "$title - $season_title - $episode_title"
      fi
      exit
    fi
    play_video && wait
    [ "$history" = 1 ] && save_history
    prompt_to_continue
    case "$continue_choice" in
    "Yes") resume_from="" && continue ;;
    "Search")
      rm "$images_cache_dir"/*
      rm "$applications_dir"/*
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
    [ "$use_external_menu" = "0" ] && choice=$(printf "%s" "$response" | fzf --with-nth 1 -d "\t" --header "Choose a Movie or TV Show")
    title=$(printf "%s" "$choice" | $sed -nE "s@(.*) \((movie|tv)\).*@\1@p")
    media_type=$(printf "%s" "$choice" | $sed -nE "s@(.*) \((movie|tv)\).*@\2@p")
    media_id=$(printf "%s" "$choice" | cut -f2)
  fi
  [ "$media_type" = "tv" ] && choose_episode
  keep_running="true"
  loop
}

play_from_history() {
  [ ! -f "$histfile" ] && send_notification "No history file found" "5000" "" && exit 1
  [ "$watched_history" = 1 ] && exit 0
  watched_history=1
  choice=$(tac "$histfile" | nl -w 1 | nth "Choose an entry:")
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
    choose_episode
  fi
  keep_running="true" && loop
}

# TODO: remove code duplication
choose_from_trending() {
  [ "$image_preview" = "1" ] && response=$(curl -s "https://${base}/home" | $sed -n '/id="trending-movies"/,/class="block_area block_area_home section-id-02"/p' | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
    $sed -nE "s@.*img data-src=\"([^\"]*)\".*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\1\t\3\t\2\t\4 [\5]@p" | hxunent)
  [ "$image_preview" = "0" ] && response=$(curl -s "https://${base}/home" | $sed -n '/id="trending-movies"/,/id="trending-tv"/p' | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
    $sed -nE "s@.*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\3 (\1) [\4]\t\2@p" | hxunent)
  main
}

choose_from_recent_movie() {
  [ "$image_preview" = "1" ] && response=$(curl -s "https://${base}/movie" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
    $sed -nE "s@.*img data-src=\"([^\"]*)\".*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\1\t\3\t\2\t\4 [\5]@p" | hxunent)
  [ "$image_preview" = "0" ] && response=$(curl -s "https://${base}/movie" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
    $sed -nE "s@.*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\3 (\1) [\4]\t\2@p" | hxunent)
  main
}

choose_from_recent_tv() {
  [ "$image_preview" = "1" ] && response=$(curl -s "https://${base}/tv-show" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
    $sed -nE "s@.*img data-src=\"([^\"]*)\".*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\1\t\3\t\2\t\4 [\5]@p" | hxunent)
  [ "$image_preview" = "0" ] && response=$(curl -s "https://${base}/home" | $sed ':a;N;$!ba;s/\n//g;s/class="flw-item"/\n/g' |
    $sed -nE "s@.*<a href=\".*/(tv|movie)/watch-.*-([0-9]*)\".*title=\"([^\"]*)\".*class=\"fdi-item\">([^<]*)</span>.*@\3 (\1) [\4]\t\2@p" | hxunent)
  main
}

update_script() {
  update=$(curl -s "https://raw.githubusercontent.com/justchokingaround/lobster/master/lobster.sh" || die "Connection error")
  update="$(printf '%s\n' "$update" | diff -u "$(which lobster)" -)"
  if [ -z "$update" ]; then
    send_notification "Script is up to date :)"
  else
    if printf '%s\n' "$update" | patch "$(which lobster)" -; then
      send_notification "Script has been updated"
    else
      send_notification "Can't update for some reason!"
    fi
  fi
  exit 0
}

configuration
while [ $# -gt 0 ]; do
  case "$1" in
  -c | --continue) play_from_history && exit ;;
  -d | --download) download="1" && shift ;;
  -h | --help) usage && exit 0 ;;
  -e | --edit) [ -f "$config_file" ] && "$lobster_editor" "$config_file" && exit 0 || exit 0 ;;
  -p | --provider)
    provider="$2"
    if [ -z "$provider" ]; then
      provider="UpCloud"
      shift
    else
      shift 2
    fi
    ;;
  -j | --json) json_output="1" && shift ;;
  -q | --quality)
    quality="$2"
    if [ -z "$quality" ]; then
      quality="1080"
      shift
    else
      shift 2
    fi
    ;;
  --rofi | --dmenu | --external-menu) use_external_menu="1" && shift ;;
  -t | --trending) trending="1" && shift ;;
  -r | --recent)
    recent="$2"
    if [ -z "$recent" ]; then
      recent="movie"
      shift
    else
      shift 2
    fi
    ;;
  -i | --image-preview) image_preview="1" && shift ;;
  -l | --language)
    subs_language="$2"
    if [ -z "$subs_language" ]; then
      subs_language="english"
      shift
    else
      shift 2
    fi
    ;;
  -s | --syncplay) player="syncplay" && shift ;;
  -u | -U | --update) update_script ;;
  -v | -V | --version) send_notification "Lobster Version: %s\n" "$LOBSTER_VERSION" && exit 0 ;;
  *) query="$(printf "%s" "$query $1" | $sed "s/^ //;s/ /-/g")" && shift ;;
  esac
done
if [ "$image_preview" = 1 ]; then
  test -d "$images_cache_dir" || mkdir -p "$images_cache_dir"
  if [ "$use_external_menu" = 1 ]; then
    test -d "$applications_dir" || mkdir -p "$applications_dir"
  fi
fi
[ -z "$provider" ] && provider="UpCloud"
[ "$trending" = "1" ] && choose_from_trending
[ "$recent" = "movie" ] && choose_from_recent_movie
[ "$recent" = "tv" ] && choose_from_recent_tv

main
