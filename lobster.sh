#!/bin/sh
# shellcheck disable=SC2034,SC2162

version="3.0.5"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
config_file="$XDG_CONFIG_HOME/lobster/lobster_config.txt"
history_file="$XDG_CONFIG_HOME/lobster/lobster_history.txt"
[ ! -d "$XDG_CONFIG_HOME/lobster" ] && mkdir -p "$XDG_CONFIG_HOME/lobster"
[ ! -f "$config_file" ] && printf "player=mpv\nsubs_language=English\nvideo_quality=1080\nbase=https://api.haikei.xyz/movies/flixhq\npreferred_server=vidcloud\n" >"$config_file"
player="$(grep '^player=' "$config_file" | cut -d'=' -f2)" || player="mpv"
base="$(grep '^base=' "$config_file" | cut -d'=' -f2)" || base="https://api.haikei.xyz/movies/flixhq"
subs_language="$(grep "^subs_language=" "$config_file" | cut -d'=' -f2)" || subs_language="English"
video_quality="$(grep "^video_quality=" "$config_file" | cut -d'=' -f2)" || video_quality="1080p"
server="$(grep "^preferred_server=" "$config_file" | cut -d'=' -f2)" || server="vidcloud"
case "$(uname -s)" in
MINGW* | *Msys) separator=';' && path_thing='' ;;
*) separator=':' && path_thing="\\" ;;
esac

play_video() {
	json_data=$(curl -s "$base/watch?episodeId=${episode_id}&mediaId=${media_id}&server=${server}&")
	referrer=$(printf "%s" "$json_data" | tr "{|}" "\n" | sed -nE "s@\"Referer\":\"([^\"]*)\"@\1@p")
	mpv_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | sed -nE "s@\"url\":\"([^\"]*)\",\"quality\":\"$video_quality\",.*@\1@p")
	subs_links=$(printf "%s" "$json_data" | tr "{|}" "\n" | sed -nE "s@\"url\":\"([^\"]*.vtt)\",\"lang\":\"$subs_language.*@\1@p" | sed -e "s/:/\\$path_thing:/g" -e "H;1h;\$!d;x;y/\n/$separator/" -e "s/$separator\$//")
	[ -z "$mpv_link" ] && mpv_link=$(printf "%s" "$json_data" | tr "{|}" "\n" | sed -nE "s@\"url\":\"([^\"]*)\",\"quality\":\".*@\1@p" | head -n1)
	[ -z "$mpv_link" ] && printf "No links found\n" && exit 1
	[ -z "$subs_links" ] && printf "No subtitles found\n"
	case $player in
	iina)
		iina --no-stdin --keep-running --mpv-referrer="$referrer" --mpv-sub-files="$subs_links" \
			--mpv-force-media-title="$video_title" "$mpv_link"
		;;
	vlc)
		if uname -a | grep -qE '[Aa]ndroid'; then
			am start --user 0 -a android.intent.action.VIEW -d "$mpv_link" -n org.videolan.vlc/org.videolan.vlc.gui.video.VideoPlayerActivity -e "title" "$video_title" >/dev/null 2>&1 &
		else
			vlc "$mpv_link" --http-referrer="$referrer" --meta-title "$video_title"
		fi
		;;
	*)
		if uname -a | grep -qE '[Aa]ndroid'; then
			am start --user 0 -a android.intent.action.VIEW -d "$video_title" -n is.xyz.mpv/.MPVActivity >/dev/null 2>&1 &
		else
			[ -z "$resume_from" ] && opts="" || opts="--start=${resume_from}%"
			stopped_at=$(mpv "$opts" --referrer="$referrer" --sub-files="$subs_links" --force-media-title="$video_title" "$mpv_link" 2>&1 | grep AV |
				tail -n1 | sed -nE 's_.*AV: ([^ ]*) / ([^ ]*) \(([0-9]*)%\).*_\3_p')
		fi
		;;
	esac
}

history() {
	if [ "$stopped_at" -gt 85 ]; then
		if [ "$media_type" = "Movie" ]; then
			# using grep -c instead of wc -l, bc wc -l has weird behavior when the file doesn't end with a newline
			[ "$(grep -c . <"$history_file")" -eq 1 ] && rm "$history_file" && exit 0
			grep -sv "$media_id" "$history_file" >"$history_file.tmp" && mv "$history_file.tmp" "$history_file" && exit 0
		fi
		episode_id=$(printf "%s" "$tv_show_json" | sed -nE "s@.*\"id\":\"([0-9]*)\",\"title\":\"([^\"]*)\",\"number\":$((episode_number + 1)),\"season\":$season_number.*@\1@p")
		stopped_at=0 && episode_number=$((episode_number + 1))
		[ -z "$episode_id" ] && episode_id=$(printf "%s" "$tv_show_json" | sed -nE "s@.*\"id\":\"([0-9]*)\",\"title\":\"([^\"]*)\",\"number\":1,\"season\":$((season_number + 1)).*@\1@p") &&
			stopped_at=0 && episode_number=1 && season_number=$((season_number + 1))
		[ -z "$episode_id" ] && [ grep -c . -eq 1 ] <"$history_file" && exit 0
		[ -z "$episode_id" ] && grep -sv "$media_id" "$history_file" >"$history_file.tmp" && mv "$history_file.tmp" "$history_file" && exit 0
		grep -sv "$media_id" "$history_file" >"$history_file.tmp"
		printf "%s\t%s\t%s\t%s: S%s Ep(%s)\n" "$media_id" "$episode_id" "$stopped_at" "$movie_title" "$season_number" "$episode_number" >>"$history_file.tmp"
		mv "$history_file.tmp" "$history_file"
		[ -z "$episode_id" ] && [ "$(grep -c . <"$history_file")" -eq 1 ] && rm "$history_file" && exit 0
	else
		grep -sv "$media_id" "$history_file" >"$history_file.tmp"
		[ "$media_type" = "Movie" ] && printf "%s\t%s\t%s\n" "$media_id" "$stopped_at" "$movie_title" >>"$history_file.tmp" ||
			printf "%s\t%s\t%s\t%s: S%s Ep(%s)\n" "$media_id" "$episode_id" "$stopped_at" "$movie_title" "$season_number" "$episode_number" >>"$history_file.tmp"
		mv "$history_file.tmp" "$history_file"
	fi
}

main() {
	printf "Loading...\n"
	case "$media_type" in
	"Movie")
		episode_id=$(curl -s $base/info?id="$media_id" | tr "{|}" "\n" | sed -nE "s@\"id\":\"([0-9]*)\".*@\1@p")
		video_title="$movie_title"
		play_video
		printf "Press Enter to save movie progress or Ctrl-C to exit (this will not reset your progress)\n" && read useless
		history
		exit 0
		;;
	"TV Series")
		tv_show_json=$(curl -s "$base/info?id=${media_id}")
		if [ -z "$season_number" ] || [ -z "$episode_number" ]; then
			number_of_seasons=$(printf "%s" "$tv_show_json" | sed -nE "s@.*\"season\":([0-9]*).*@\1@p")
			[ "$number_of_seasons" -gt 1 ] && printf "Please choose a season number between 1 and %s: " \
				"$number_of_seasons" && read -r season_number || season_number=1
			[ -z "$season_number" ] && season_number=$number_of_seasons
			number_of_episodes_in_season=$(printf "%s" "$tv_show_json" | sed -nE "s@.*\"number\":([0-9]*),\"season\":$season_number.*@\1@p")
			[ "$number_of_episodes_in_season" -gt 1 ] && printf "Please choose an episode number between 1 and %s: " \
				"$number_of_episodes_in_season" && read -r episode_number || episode_number=1
			[ -z "$episode_number" ] && episode_number=$number_of_episodes_in_season
		fi
		episode=$(printf "%s" "$tv_show_json" | sed -nE "s@.*\"id\":\"([0-9]*)\",\"title\":\"([^\"]*)\",\"number\":$episode_number,\"season\":$season_number.*@\1\t\2@p")
		episode_id=$(printf "%s" "$episode" | cut -f1)
		episode_title=$(printf "%s" "$episode" | cut -f2)
		video_title="${movie_title} - S${season_number} ${episode_title}"
		play_video
		printf "Press Enter to save episode progress or Ctrl-C to exit (this will not reset your progress)\n" && read useless
		history
		;;
	esac
	tput clear && printf "Press Enter to continue watching, or Ctrl+C to exit" && read -r useless
	first_run="" && play_from_history
}

get_input() {
	[ -z "$*" ] && printf "Enter a Movie/TV Show name: " && read -r query || query=$*
	query=$(printf "%s" "$query" | tr " " "-")
	movies_choice=$(curl -s "$base/${query}" | tr "{|}" "\n" |
		sed -nE "s@\"id\":\"([^\"]*)\",\"title\":\"([^\"]*)\",.*\"type\":\"([a-zA-Z ]*)\"\$@\1\t\2 (\3)@p" | fzf --border -1 --reverse --with-nth 2..)
	[ -z "$movies_choice" ] && exit 0
	media_type=$(printf "%s" "$movies_choice" | sed -nE "s_.*\(([a-zA-Z ]*)\)\$_\1_p")
	media_id=$(printf "%s" "$movies_choice" | cut -f1)
	movie_title=$(printf "%s" "$movies_choice" | cut -f2 | sed -nE "s_(.*) \((.*)\)\$_\1_p")
}

play_from_history() {
	selection=$(fzf --border --reverse --tac -1 --cycle -d"\t" --with-nth -1 <"$history_file")
	[ -z "$selection" ] && exit 0
	if printf "%s" "$selection" | grep -qE '^movie/'; then
		media_type="Movie"
		media_id=$(printf "%s" "$selection" | cut -f1)
		resume_from=$(printf "%s" "$selection" | cut -f2)
		movie_title=$(printf "%s" "$selection" | cut -f3)
	else
		media_type="TV Series"
		media_id=$(printf "%s" "$selection" | cut -f1)
		episode_id=$(printf "%s" "$selection" | cut -f2)
		resume_from=$(printf "%s" "$selection" | cut -f3)
		[ "$resume_from" -eq -1 ] && resume_from=0
		movie_title=$(printf "%s" "$selection" | cut -f4 | sed -nE 's_(.*): S[0-9].*_\1_p')
		season_number=$(printf "%s" "$selection" | cut -f4 | sed -nE 's_.*: S([0-9]*).*_\1_p')
		episode_number=$(printf "%s" "$selection" | cut -f4 | sed -nE 's_.*S[0-9].*Ep\(([0-9]*)\).*_\1_p')
	fi
	continue_history=true
	if [ -z "$first_run" ]; then
		main
	else
		first_run=false
	fi
}

while getopts "cduUvVh" opt; do
	case $opt in
	c) play_from_history ;;
	d)
		rm -f "$history_file" && printf "History file deleted\n" && exit 0
		;;
	u | U)
		update=$(curl -s "https://raw.githubusercontent.com/justchokingaround/lobster/master/lobster.sh" || die "Connection error")
		update="$(printf "%s\n" "$update" | diff -u "$(which lobster)" -)"
		if [ -z "$update" ]; then
			printf "Script is up to date :)\n"
		else
			if printf "%s\n" "$update" | patch "$(which lobster)" -; then
				printf "Script has been updated\n"
			else
				printf "Can't update for some reason!\n"
			fi
		fi
		exit 0
		;;
	v | V)
		printf "Lobster version: %s\n" "$version" && exit 0
		;;
	h)
		printf "Usage: lobster [arg] or lobster [movie/TV show name]\n"
		printf "Play movies and TV shows from flixhq.to\n"
		printf "  -c, \t\tContinue watching from last minute saved\n"
		printf "  -d, \t\tDelete history file\n"
		printf "  -u, \t\tUpdate script\n"
		printf "  -v, \t\tPrint version\n"
		printf "  -h, \t\tDisplay this help and exit\n"
		exit 0
		;;
	\?)
		printf "Invalid option: -%s\n" "$OPTARG" >&2
		exit 1
		;;
	esac
done

if [ -z "$continue_history" ]; then
	get_input "$*"
	main
fi
