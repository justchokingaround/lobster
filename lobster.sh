#!/bin/sh

LOBSTER_VERSION="4.0.0"
config_file="$XDG_CONFIG_HOME/lobster/lobster_config.txt"
default_config="player=mpv\nsubs_language=English\nprovider=Vidcloud\nhistory_file=\"\$XDG_CONFIG_HOME/lobster/lobster_history.txt\"\nuse_external_menu=0\nimage_preview=\"0\""
lobster_editor=${VISUAL:-${EDITOR:-vim}}
case "$(uname -s)" in
MINGW* | *Msys) separator=';' && path_thing='' ;;
*) separator=':' && path_thing="\\" ;;
esac
command -v notify-send >/dev/null 2>&1 && notify="true" || notify="false"
send_notification() {
	[ -n "$json_output" ] && return
	[ "$use_external_menu" = "0" ] && printf "\33[2K\r\033[1;34m%s\n\033[0m" "$1" && return
	[ -z "$2" ] && timeout=3000 || timeout="$2"
	if [ "$notify" = "true" ]; then
		[ -z "$3" ] && notify-send "$1" -t "$timeout" -h string:x-dunst-stack-tag:vol
		[ -n "$3" ] && notify-send "$1" -t "$timeout" -i "$3" -h string:x-dunst-stack-tag:vol
	fi
}
dep_ch() {
	for dep; do
		command -v "$dep" >/dev/null || send-notification "Program \"$dep\" not found. Please install it."
	done
}
dep_ch "grep" "sed" "awk" "curl" "perl" "fzf" "mpv" || true
cleanup() {
	rm -rf "$images_cache_dir"
	[ -f /tmp/lobster_position ] && rm /tmp/lobster_position
	exit
}
trap cleanup EXIT INT TERM

usage() {
	printf "
  Usage: %s [options] [query]
  If a query is provided, it will be used to search for a Movie/TV Show

  Options:
    -c, --continue
      Continue watching from current history
    -D, --dmenu
      Use an external menu (instead of the default fzf) for selection menus (default one is rofi, but this can be specified in the config file)
    -e, --edit
      Edit config file using an editor defined with lobster_editor in the config (\$EDITOR by default)
    -h, --help
      Show this help message and exit
    -j, --json
      Outputs the json containing video links, subtitle links, referrers etc. to stdout
    -p, --provider
      Specify the provider to watch from (default: Vidcloud) (currently supported: Vidcloud)
    -l, --language
      Specify the subtitle language
    -u, --update
      Update the script
    -v, --version
      Show the version of the script

    Note: 
      All arguments can be specified in the config file as well.
      If an argument is specified in both the config file and the command line, the command line argument will be used.

    Some example usages:
     ${0##*/} a silent voice
     ${0##*/} -l spanish fight club
     ${0##*/} -l spanish blade runner --json

" "${0##*/}"
}

configuration() {
	XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
	[ ! -d "$XDG_CONFIG_HOME/lobster" ] && mkdir -p "$XDG_CONFIG_HOME/lobster"
	#shellcheck disable=1090
	[ -f "$config_file" ] && . "${config_file}"
	[ -z "$base" ] && base="flixhq.to"
	[ -z "$player" ] && player="mpv"
	[ -z "$subs_language" ] && subs_language="English"
	[ -z "$video_quality" ] && video_quality="1080"
	[ -z "$preferred_provider" ] && provider="Vidcloud" || provider="$preferred_provider"
	[ -z "$history_file" ] && history_file="$XDG_CONFIG_HOME/lobster/lobster_history.txt"
	[ -z "$use_external_menu" ] && use_external_menu="0"
	[ -z "$image_preview" ] && image_preview="0"
	[ -z "$images_cache_dir" ] && images_cache_dir="/tmp/lobster-images"
	[ -z "$image_config_path" ] && image_config_path="$HOME/dotfiles/rofi/styles/image-preview.rasi"
}

external_menu() {
	rofi -sort -dmenu -i -width 1500 -p "" -mesg "$1"
}

launcher() {
	[ "$use_external_menu" = "0" ] && fzf --reverse --prompt "$1"
	[ "$use_external_menu" = "1" ] && external_menu "$1"
}

nth() {
	stdin=$(cat -)
	[ -z "$stdin" ] && return 1
	line=$(printf "%b\n" "$stdin" | awk -F '\t' "{ print NR, $1 }" | launcher "$2" | cut -d\  -f1)
	[ -n "$line" ] && printf "%b\n" "$stdin" | sed "${line}q;d" || exit 1
}

get_input() {
	if [ "$use_external_menu" = "0" ]; then
		printf "Enter a query: " && read -r query
	else
		query=$(printf "" | launcher "Enter a query")
	fi
	[ -n "$query" ] && query=$(echo "$query" | tr ' ' '-')
	[ -z "$query" ] && send_notification "Error: No query provided" "1000"
}

select_episode() {
	season_id=$(curl -s "https://${base}/ajax/v2/tv/seasons/${media_id}" | sed -nE "s@.*href=\".*-([0-9]*)\">(.*)</a>@\1\t\2@p" |
		nth "\$2" "Select a season: " | cut -f1)
	episode_id=$(curl -s "https://${base}/ajax/v2/season/episodes/${season_id}" | sed -nE "s@.*data-id=\"([0-9]*)\"@\1@p;s@[[:space:]]*title=\"(.*)\">.*@\1@p" |
		sed "N;s/\n/\t/g" | nth "\$2" "Select an episode: " | cut -f1)
	episode_id=$(curl -s "https://${base}/ajax/v2/episode/servers/${episode_id}" | sed -nE "s@.*data-id=\"([0-9]*)\".*@\1@p;s@.*title=\"(.*)\".*@\1@p" |
		sed "N;s/\n/\t/g" | grep "$provider" | cut -f1)
}

choose_from_list() {
	list=$(curl -s "https://${base}/search/$query" | sed ':a;N;$!ba;s/\n//g;s/class="film-detail"/\n/g' | sed -nE 's@.*data-src="([^"]*)".*<a href="(.*watch-[^"]*)".*title="([^"]*)".*@\1{\3{\2@p' | perl -MHTML::Entities -pe 'decode_entities($_);')
	# if the list only contains one entry, then auto select it
	if [ "$(printf "%s" "$list" | wc -l)" -lt 1 ]; then
		send_notification "Since only one entry was found, it was automatically selected" "3000"
		image_url=$(printf "%s" "$list" | cut -d'{' -f1)
		title=$(printf "%s" "$list" | cut -d'{' -f2)
		href=$(printf "%s" "$list" | cut -d'{' -f3)
		media_type=$(printf "%s" "$href" | cut -d/ -f2)
		media_id=$(printf "%s" "$href" | sed -nE "s@.*-([0-9]*).*@\1@p")
		case "$image_preview" in
		"true" | 1)
			mkdir -p "$images_cache_dir"
			curl -s -o "$images_cache_dir/$media_id.jpg" "$image_url"
			wait && sleep 1
			;;
		esac
		return
	fi
	case "$image_preview" in
	"true" | 1)
		mkdir -p "$images_cache_dir"
		printf "%s" "$list" | while IFS='{' read -r image_url title href; do
			media_id=$(printf "%s" "$href" | sed -nE "s@.*-([0-9]*)\$@\1@p")
			curl -s -o "$images_cache_dir/$media_id.jpg" "$image_url" &
		done
		wait && sleep 1
		choice=$(printf "%s" "$list" | while IFS='{' read -r image_url title href; do
			media_id=$(printf "%s" "$href" | sed -nE "s@.*-([0-9]*)\$@\1@p")
			media_type=$(printf "%s" "$href" | cut -d/ -f2)
			printf "[%s]\t%s (%s)\x00icon\x1f%s/%s.jpg\n" "$href" "$title" "$media_type" "$images_cache_dir" "$media_id"
		done | rofi -dmenu -i -p "" -theme "$image_config_path" -mesg "Choose a Movie or TV Show: " -display-columns 2..)
		media_type=$(printf "%s" "$choice" | sed -nE "s@.*\((.*)\)\$@\1@p")
		href=$(printf "%s" "$choice" | sed -nE "s@.*\[(.*)\].*@\1@p")
		media_id=$(printf "%s" "$href" | sed -nE "s@.*-([0-9]*)\$@\1@p")
		title=$(printf "%s" "$choice" | sed -nE "s@.*\[$href\]\t(.*) \(.*\)@\1@p")
		;;
	*)
		choice=$(printf "%s" "$list" | while IFS='{' read -r image_url title href; do
			media_type=$(printf "%s" "$href" | cut -d/ -f2)
			printf "%s (%s)\t %s\n" "$title" "$media_type" "$href"
		done | nth "\$1" "Choose a Movie or TV Show: ")
		title=$(printf "%s" "$choice" | sed -nE "s@(.*) \(.*\).*@\1@p")
		media_type=$(printf "%s" "$choice" | sed -nE "s@.* \((.*)\).*@\1@p")
		href=$(printf "%s" "$choice" | sed -nE "s@.*(/$media_type.*)@\1@p")
		media_id=$(printf "%s" "$href" | sed -nE "s@.*-([0-9]*)\$@\1@p")
		;;
	esac

	[ "$media_type" ] && select_episode
}

play_video() {
	history_contains_href=$(grep -E "^$href" "$history_file")
	if [ -n "$history_contains_href" ]; then
		case "$media_type" in
		"movie") resume_from=$(grep "$href" "$history_file" | cut -f2) ;;
		"tv") resume_from=$(grep "$href" "$history_file" | cut -f3) ;;
		esac
		send_notification "Resuming from $resume_from" "5000" "$images_cache_dir/$media_id.jpg"
	fi
	[ -z "$history_contains_href" ] && send_notification "Playing $title" "5000" "$images_cache_dir/$media_id.jpg"
	case $player in
	iina)
		iina --no-stdin --keep-running --mpv-sub-files="$subs_links" \
			--mpv-force-media-title="$title" "$video_link"
		;;
	vlc)
		if uname -a | grep -qE '[Aa]ndroid'; then
			am start --user 0 -a android.intent.action.VIEW -d "$video_link" -n org.videolan.vlc/org.videolan.vlc.gui.video.VideoPlayerActivity -e "title" "$title" >/dev/null 2>&1 &
		else
			vlc "$video_link" --meta-title "$title"
		fi
		;;
	*)
		if uname -a | grep -qE '[Aa]ndroid'; then
			am start --user 0 -a android.intent.action.VIEW -d "$title" -n is.xyz.mpv/.MPVActivity >/dev/null 2>&1 &
		else
			[ -z "$resume_from" ] && opts="" || opts="--start=${resume_from}"
			if [ -n "$subs_links" ]; then
				nohup mpv "$opts" --sub-file="$subs_links" --force-media-title="$title" --input-ipc-server=/tmp/mpvsocket "$video_link" >/dev/null 2>&1 &
			else
				nohup mpv "$opts" --force-media-title="$title" --input-ipc-server=/tmp/mpvsocket "$video_link" >/dev/null 2>&1 &
			fi
			PID=$!
			while ! ps -p $PID >/dev/null; do
				sleep 0.1
			done
			sleep 2

			while ps -p $PID >/dev/null; do
				position=$(echo '{ "command": ["get_property", "time-pos"] }' | socat - /tmp/mpvsocket | sed -nE "s@.*\"data\":([0-9\.]*),.*@\1@p")
				[ "$position" != "" ] && printf "%s" "$position" >/tmp/lobster_position
				sleep 1
			done
			position=$(date -u -r "$(printf "%.0f" "$(cat /tmp/lobster_position)")" "+%H:%M:%S")
			[ -n "$position" ] && send_notification "Stopped at $position" "5000" "$images_cache_dir/$media_id.jpg"
		fi
		;;
	esac
}

add_to_history() {
	if [ "$position" -gt 90 ]; then
		case "$media_type" in
		"movie")
			# using grep -c instead of wc -l, bc wc -l has weird behavior when the file doesn't end with a newline
			[ "$(grep -c . <"$history_file")" -eq 1 ] && rm "$history_file" && exit 0
			grep -sv "$media_id" "$history_file" >"$history_file.tmp" && mv "$history_file.tmp" "$history_file" && exit 0
			;;
		"tv")
			# episode_id=$(printf "%s" "$tv_show_json" | sed -nE "s@.*\"id\":\"([0-9]*)\",\"title\":\"([^\"]*)\",\"number\":$((episode_number + 1)),\"season\":$season_number.*@\1@p")
			# stopped_at=0 && episode_number=$((episode_number + 1))
			# [ -z "$episode_id" ] && episode_id=$(printf "%s" "$tv_show_json" | sed -nE "s@.*\"id\":\"([0-9]*)\",\"title\":\"([^\"]*)\",\"number\":1,\"season\":$((season_number + 1)).*@\1@p") &&
			# 	stopped_at=0 && episode_number=1 && season_number=$((season_number + 1))
			# [ -z "$episode_id" ] && [ grep -c . -eq 1 ] <"$history_file" && exit 0
			# [ -z "$episode_id" ] && grep -sv "$media_id" "$history_file" >"$history_file.tmp" && mv "$history_file.tmp" "$history_file" && exit 0
			# grep -sv "$media_id" "$history_file" >"$history_file.tmp"
			# printf "%s\t%s\t%s\t%s: S%s Ep(%s)\n" "$media_id" "$episode_id" "$stopped_at" "$movie_title" "$season_number" "$episode_number" >>"$history_file.tmp"
			# mv "$history_file.tmp" "$history_file"
			# [ -z "$episode_id" ] && [ "$(grep -c . <"$history_file")" -eq 1 ] && rm "$history_file" && exit 0
			;;
		esac
	else
		grep -sv "$media_id" "$history_file" >"$history_file.tmp"
		[ "$media_type" = "movie" ] && printf "%s\t%s\t%s\n" "$href" "$position" "$title" >>"$history_file.tmp" ||
			exit
		# printf "%s\t%s\t%s\t%s: S%s Ep(%s)\n" "$href" "$episode_id" "$position" "$title" "$season_number" "$episode_number" >>"$history_file.tmp"
		mv "$history_file.tmp" "$history_file"
	fi
	sleep 1
	send_notification "History file entry has been updated!" "3000" "$images_cache_dir/$media_id.jpg"
}

play_from_history() {
	selection=$(nth "\$NF" "Select a Movie or a TV Show episode: " <"$history_file")
	[ -z "$selection" ] && exit 0
	if printf "%s" "$selection" | grep -qE '^/movie/'; then
		media_type="movie"
		href=$(printf "%s" "$selection" | cut -f1)
		resume_from=$(printf "%s" "$selection" | cut -f2)
		title=$(printf "%s" "$selection" | cut -f3)
	else
		media_type="tv"
		href=$(printf "%s" "$selection" | cut -f1)
		episode_id=$(printf "%s" "$selection" | cut -f2)
		resume_from=$(printf "%s" "$selection" | cut -f3)
		title=$(printf "%s" "$selection" | cut -f4 | sed -nE 's_(.*): S[0-9].*_\1_p')
		season_number=$(printf "%s" "$selection" | cut -f4 | sed -nE 's_.*: S([0-9]*).*_\1_p')
		episode_number=$(printf "%s" "$selection" | cut -f4 | sed -nE 's_.*S[0-9].*Ep\(([0-9]*)\).*_\1_p')
	fi
	media_id=$(printf "%s" "$href" | sed -nE "s@.*-([0-9]*)@\1@p")
	exit
}

get_links() {
	if [ "$media_type" = "movie" ]; then
		# request to get the episode id
		movie_page="https://${base}"$(curl -s "https://${base}/ajax/movie/episodes/${media_id}" |
			tr -d "\n" | sed -nE "s_.*href=\"([^\"]*)\".*$provider.*_\1_p")
		episode_id=$(printf "%s" "$movie_page" | sed -nE "s_.*-([0-9]*)\.([0-9]*)\$_\2_p")
	fi
	# request to get the embed
	embed_link=$(curl -s "https://flixhq.to/ajax/sources/${episode_id}" | sed -nE "s_.*\"link\":\"([^\"]*)\".*_\1_p")

	send_notification "Getting the video links..." "5000"
	# get the juicy links
	parse_embed=$(printf "%s" "$embed_link" | sed -nE "s_(.*)/embed-(4|6)/(.*)\?z=\$_\1\t\2\t\3_p")
	provider_link=$(printf "%s" "$parse_embed" | cut -f1)
	source_id=$(printf "%s" "$parse_embed" | cut -f3)
	embed_type=$(printf "%s" "$parse_embed" | cut -f2)

	json_data=$(curl -s "${provider_link}/ajax/embed-${embed_type}/getSources?id=${source_id}" -H "X-Requested-With: XMLHttpRequest")

	if printf "%s" "$json_data" | tr "{|}" "\n" | sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p" | grep -q "\.m3u8"; then
		video_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p" | head -1)
	else
		key="$(curl -s "https://github.com/enimax-anime/key/blob/e${embed_type}/key.txt" | sed -nE "s_.*js-file-line\">(.*)<.*_\1_p")"
		# json_data='{"sources":"U2FsdGVkX1/FFrM4Q3+gr/QZiMDJWG+eemoDuag4k2JQ+pJgP4JljPwS9eTsOUavYqueiW1ZNfy/5wHR9SSeSbSiHnYOFy+OGZ2i6Ua7xRlZAeS34HHauYcQb8bVI/W/7kjc4lqf3TJ5o7VPKK/7MCkyAMGuxi9rKxi1dOPdht5KCCi5tpzPQkogseyYGyHoUZ+mG5ks4FvtQjFxbeaX458VyFoC757MsUZJ1OZj0FGVBlZ0G7VMEzx00c+3IM4cVSqzJqffvJh8hxZ6W8dttKeCGit+WvFWq6/sS/Xxn7Bx4p9tpnpO1uFEiSM7XWPK/PITDDfS3qn5LBF0Lr56e3sYnMEJsqEKrMqin/aJRG9Cqm67kk9N4cFvErzLAJ8w1Fdu7eIPSIKPvm8kboMk9eNRbPBUuokLHwnNo0lX1U5bfg+hKvtPrHz5qYMD1+V0hIIsnf4uNJx/WB5luq4YLuv8sDhv2LsLuwMfnZ5bjLijLNDe0tekWJMV/HvYbwEIM80Jbn5gU8jJhMrn6OVeLC7S/W8fEpCn6UR+V5v8JEc4vljSpOyyMcEK5/TIyIiZ","tracks":[{"file":"https://cc.2cdns.com/30/0d/300da5b98ce4991553bb752f97ffb156/300da5b98ce4991553bb752f97ffb156.vtt","label":"English","kind":"captions","default":true},{"file":"https://prev.2cdns.com/_m_preview/e8/e8c05b70294a004173d8514ed4f6cc6f/thumbnails/sprite.vtt","kind":"thumbnails"}],"server":18}'
		video_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | sed -nE "s_.*\"sources\":\"([^\"]*)\".*_\1_p" | head -1 | base64 -d |
			openssl enc -aes-256-cbc -d -md md5 -k "$key" 2>/dev/null | sed -nE "s_.*\"file\":\"([^\"]*)\".*_\1_p")
	fi
	# TODO: Fix this
	# episode_links=$(printf "%s" "$json_data" | sed -E "s@sources\":\"[^\"]*\"@sources\":\"$video_link\"@")

	[ "$json_output" = "true" ] && printf "%s\n" "$episode_links"
	[ "$json_output" = "true" ] && exit 0
	subs_links=$(printf "%s" "$json_data" | tr "{|}" "\n" | sed -nE "s@\"file\":\"([^\"]*)\".*\"$subs_language.*@\1@p" | head -1)
	#[ $(printf "%s" "$subs_links" | wc -l) -gt 1 ] && subs_links=$(printf "%s" "$subs_links" | sed -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
	[ -z "$subs_links" ] && printf "No subtitles found\n"
}

update_script() {
	update=$(curl -s "https://raw.githubusercontent.com/justchokingaround/lobster/master/lobster.sh" || die "Connection error")
	update="$(printf '%s\n' "$update" | diff -u "$(which jerry)" -)"
	if [ -z "$update" ]; then
		printf "Script is up to date :)\n"
	else
		if printf '%s\n' "$update" | patch "$(which jerry)" -; then
			printf "Script has been updated\n"
		else
			printf "Can't update for some reason!\n"
		fi
	fi
	exit 0
}

while [ $# -gt 0 ]; do
	case "$1" in
	-c | --continue) play_from_history ;;
	-D | --dmenu) use_external_menu="1" && shift ;;
	-e | --edit) [ -f "$config_file" ] && "$lobster_editor" "$config_file" && exit 0 || echo "$default_config" >"$config_file" && "$lobster_editor" "$config_file" && exit 0 ;;
	-h | --help) usage && exit 0 ;;
	-p | --provider) preferred_provider="$2" && shift 2 ;;
	-j | --json) json_output="true" && shift ;;
	-l | --language) subs_language="$2" && shift 2 ;;
	-u | -U | --update) update_script ;;
	-v | -V | --version) printf "Lobster Version: %s\n" "$LOBSTER_VERSION" && exit 0 ;;
	*) query="$(printf "%s" "$query $1" | sed "s/^ //;s/ /-/g")" && shift ;;
	esac
done
configuration

main() {
	[ -z "$query" ] && get_input
	[ -z "$query" ] && exit 1
	choose_from_list
	[ -z "$href" ] && exit 1
	get_links
	[ -z "$video_link" ] && exit 1
	play_video
	[ -n "$position" ] && add_to_history
}

if [ -z "$href" ]; then
	main
else
	get_links
	play_video
fi
