#!/bin/sh

version="1.0.2"
base="https://www5.himovies.to"
history_file="$HOME/.cache/lobster_history.txt"
config_file="$HOME/.config/lobster/lobster_config.txt"
[ ! -d "$HOME/.config/lobster" ] && mkdir -p "$HOME/.config/lobster"
[ ! -f "$config_file" ] && printf "player=mpv\nsubs_language=English\n" > "$config_file"
player="$(grep '^player=' "$config_file"|cut -d'=' -f2)" || player="mpv"
subs_language="$(grep '^subs_language=' "$config_file"|cut -d'=' -f2)" || subs_language="English"

yoinkity_yoink() {
  key=$(curl -s "$movie_page"|sed -nE "s@.*recaptcha_site_key = '(.*)'.*@\1@p")
  co=$(printf "https://www5.himovies.to:443"|base64|tr "=" ".")
  vtoken=$(curl -s "https://www.google.com/recaptcha/api.js?render=$key"|
    sed -nE "s_.*po\.src=.*releases/(.*)/recaptcha.*_\1_p")
  recaptcha_token=$(curl -s "https://www.google.com/recaptcha/api2/anchor?ar=1&hl=en\
    &size=invisible&cb=cs3&k=${key}&co=${co}&v=${vtoken}"|
    sed -En 's_.*id="recaptcha-token" value="([^"]*)".*_\1_p')
  id=$(curl -s "https://www5.himovies.to/ajax/get_link/${provider_id}?_token=${recaptcha_token}"|
    sed -nE 's_.*"link":".*/(.*)\?z=".*_\1_p')

  xml_links=$(curl -s "https://mzzcloud.life/ajax/embed-4/getSources?id=${id}" \
    -H 'X-Requested-With: XMLHttpRequest'|tr '{|}' '\n'|
    sed -nE 's_.*file":"([^"]*)","type.*_\1_p; s_.*file":"([^"]*)","label":"'$subs_language'.*".*_\1_p')
  mpv_link=$(printf "%s" "$xml_links"|head -1)
  subs_links=$(printf "%s" "$xml_links"|sed -n '2,$p'|sed -e 's/:/\\:/g' -e 'H;1h;$!d;x;y/\n/:/' -e 's/:$//')
  [ -z "$mpv_link" ] && printf "No links found\n" && exit 1
  [ -z "$subs_links" ] && printf "No subtitles found\n"
}

main() {
  case "$media_type" in
    movie)
      movie_page="$base"$(curl -s "https://www5.himovies.to/ajax/movie/episodes/${movie_id}"|
        tr -d "\n"|sed -nE 's_.*href="([^"]*)".*UpCloud.*_\1_p')
      provider_id=$(printf "%s" "$movie_page"|sed -nE "s_.*\.([0-9]*)\$_\1_p")
      [ -z "$provider_id" ] && movie_page="$base"$(curl -s "https://www5.himovies.to/ajax/movie/episodes/${movie_id}"|
        tr -d "\n"|sed -nE 's_.*href="([^"]*)".*Vidcloud.*_\1_p') && provider_id=$(printf "%s" "$movie_page"|
        sed -nE "s_.*\.([0-9]*)\$_\1_p")
      yoinkity_yoink
      case $player in
        iina)
          iina --no-stdin --keep-running --mpv-sub-files="$subs_links" --mpv-force-media-title="$movie_title" "$mpv_link" ;;
        vlc)
          if uname -a | grep -qE '[Aa]ndroid';then
            am start --user 0 -a android.intent.action.VIEW -d "$mpv_link" -n org.videolan.vlc/org.videolan.vlc.gui.video.VideoPlayerActivity -e "title" "$movie_title" > /dev/null 2>&1 &
          else
            vlc "$mpv_link" --meta-title "$movie_title"
          fi ;;
        *)
          if uname -a | grep -qE '[Aa]ndroid';then
            am start --user 0 -a android.intent.action.VIEW -d "$mpv_link" -n is.xyz.mpv/.MPVActivity > /dev/null 2>&1 &
          else
            mpv --sub-files="$subs_links" --force-media-title="$movie_title" "$mpv_link"
          fi ;;
      esac ;;
    tv)
      if [ -z "$season_id" ] || [ -z "$episode_id" ]; then
        seasons_ids=$(curl -s "https://www5.himovies.to/ajax/v2/tv/seasons/${movie_id}"|
          sed -nE 's_.*data-id="([0-9]*)".*_\1_p')
        number_of_seasons=$(( $(printf "%s" "$seasons_ids"|wc -l|tr -d "[:space:]") + 1 ))
        [ "$number_of_seasons" -gt 1 ] && printf "Please choose a season number between 1 and %s: " \
          "$number_of_seasons" && read -r season_number || season_number=1
        [ -z "$season_number" ] && season_number=$number_of_seasons
        season_id=$(printf "%s" "$seasons_ids"|sed -nE "${season_number}p")
        episode_ids=$(curl -s "https://www5.himovies.to/ajax/v2/season/episodes/${season_id}"|
          sed -nE 's_.*data-id="([0-9]*)".*_\1_p')
        number_of_episodes=$(( $(printf "%s" "$episode_ids"|wc -l|tr -d "[:space:]") + 1 ))
        printf "Please choose an episode number between 1 and %s: " "$number_of_episodes" && read -r episode_number
        [ -z "$episode_number" ] && episode_number=$number_of_episodes
        episode_id=$(printf "%s" "$episode_ids"|sed -nE "${episode_number}p")
      fi
      [ -z "$movies_choice" ] || show_base=$(printf "%s" "$movies_choice"|cut -f1)
      movie_page="${base}${show_base}\."$(curl -s "https://www5.himovies.to/ajax/v2/episode/servers/${episode_id}"|
        tr -d "\n"|sed -nE 's_.*data-id="([0-9]*)".*title="Server UpCloud".*_\1_p')
      provider_id=$(printf "%s" "$movie_page"|sed -nE "s_.*\.([0-9]*)\$_\1_p")
      yoinkity_yoink
      case $player in
        iina)
          iina --no-stdin --keep-running --mpv-sub-files="$subs_links" \
            --mpv-force-media-title="${movie_title}: S${season_number} Ep ${episode_number}" "$mpv_link" ;;
        vlc)
          if uname -a | grep -qE '[Aa]ndroid';then
            am start --user 0 -a android.intent.action.VIEW -d "$mpv_link" -n org.videolan.vlc/org.videolan.vlc.gui.video.VideoPlayerActivity -e "title" "$movie_title" > /dev/null 2>&1 &
          else
            vlc "$mpv_link" --meta-title "$movie_title: S${season_number} Ep ${episode_number}"
          fi ;;
        *)
          if uname -a | grep -qE '[Aa]ndroid';then
            am start --user 0 -a android.intent.action.VIEW -d "$mpv_link" -n is.xyz.mpv/.MPVActivity > /dev/null 2>&1 &
          else
            mpv --sub-files="$subs_links" --force-media-title="${movie_title}: S${season_number} Ep ${episode_number}" "$mpv_link"
          fi ;;
      esac
      # shellcheck disable=SC2034,SC2162
      printf "Press Enter to mark episode as watched or Ctrl-C to exit\n" && read useless
      grep -v "$show_base" "$history_file" > "$history_file.tmp"
      printf "%s\t%s\t%s\t%s: S%s Ep(%s)\n" "$show_base" "$season_id" \
        "$episode_id" "$movie_title" "$season_number" "$episode_number" >> "$history_file.tmp"
      mv "$history_file.tmp" "$history_file"
      ;;
    *)
      exit 1
      ;;
  esac
}

get_input() {
  if [ -z "$deez" ]; then
    [ -z "$*" ] && printf "Enter a Movie/TV Show name: " && read -r query || query=$*
    query=$(printf "%s" "$query"|tr " " "-")
    search_params=search/${query}
  else
    search_params=$deez
  fi
  movies_results=$(curl -s "${base}/${search_params}"|
    sed -nE '/class="film-name"/ {n; s/.*href="(.*)".*/\1/p;n; s/.*title="(.*)".*/\1/p;d;}'|
    sed -e 'N;s/\n/\{/' -e "s/&#39;/'/g")
  movies_choice=$(printf "%s" "$movies_results"|sed -nE 's_/(.*)/(.*)\{(.*)_\2{\3 (\1)_p'|
    fzf --height=12 -d"{" --with-nth 2..|sed -nE "s_(.*)\{(.*) \((.*)\)_/\3/\1\t\2_p")

  movie_id=$(printf "%s" "$movies_choice"|sed -nE 's_.*/[movie/|tv/].*-([0-9]*).*_\1_p')
  movie_title=$(printf "%s" "$movies_choice"|cut -f2)
  media_type=$(printf "%s" "$movies_choice"|sed -nE 's_.*/([^/]*)/.*_\1_p')
}

play_from_history() {
  selection=$(fzf --tac -1 --cycle --height=12 --with-nth 4.. < "$history_file")
  [ -z "$selection" ] && exit 0
  show_base=$(printf "%s" "$selection"|cut -f1)
  season_id=$(printf "%s" "$selection"|cut  -f2)
  episode_id=$(printf "%s" "$selection"|cut -f3)
  movie_title=$(printf "%s" "$selection"|cut -f4|sed -nE 's_(.*): S[0-9].*_\1_p')
  season_number=$(printf "%s" "$selection"|cut -f4|sed -nE 's_.*: S([0-9]*).*_\1_p')
  episode_number=$(( $(printf "%s" "$selection"|cut -f4|sed -nE 's_.*S[0-9].*Ep\(([0-9]*)\).*_\1_p') + 1 ))
  episode_id=$(curl -s "https://www5.himovies.to/ajax/v2/season/episodes/${season_id}"|
    grep 'data-id'|sed -nE "/data-id=\"${episode_id}\"/{n;p;}"|sed -nE 's/.*data-id="([0-9]*)".*/\1/p')
  movie_id=$(printf "%s" "$selection"|sed -nE 's_.*-([0-9]*).*_\1_p')
  if [ -z "$episode_id" ]; then
    season_id=$(curl -s "https://www5.himovies.to/ajax/v2/tv/seasons/${movie_id}"|
      grep 'data-id'|sed -nE "/data-id=\"${season_id}\"/{n;p;}"|sed -nE 's/^.*data-id="([0-9]*)".*/\1/p')
    episode_id=$(curl -s "https://www5.himovies.to/ajax/v2/season/episodes/${season_id}"|
      grep -m1 data-id|sed -nE 's_.*data-id="([0-9]*)".*_\1_p')
    season_number=$(( $(printf "%s" "$selection"|cut -f4|sed -nE 's_.*S([0-9]*).*_\1_p') + 1 ))
    episode_number=1
  fi
  [ -z "$show_base" ] || show_base=$(printf "%s" "$show_base"|cut -f1)
  [ -z "$episode_id" ] && echo "No next episode" && 
    grep -v "$show_base" "$history_file" > "$history_file.tmp" &&
    mv "$history_file.tmp" "$history_file" && exit 0
  media_type="tv"
  continue_history=true
  main
}

while getopts "cduUvVht" opt; do
  case $opt in
    c)
      while true; do
        play_from_history
        tput clear
      done ;;
    d)
      rm -f "$history_file" && printf "History file deleted\n" && exit 0 ;;
    u|U)
      update=$(curl -s "https://raw.githubusercontent.com/justchokingaround/lobster/master/lobster.sh"||die "Connection error")
      update="$(printf '%s\n' "$update" | diff -u "$(which lobster)" -)"
      if [ -z "$update" ]; then
        printf "Script is up to date :)\n"
      else
        if printf '%s\n' "$update" | patch "$(which lobster)" - ; then
          printf "Script has been updated\n"
        else
          printf "Can't update for some reason!\n"
        fi
      fi
      exit 0 ;;
    v|V)
      printf "Lobster version: %s\n" "$version" && exit 0 ;;
    t)
      printf "What do you want to watch? (T)V Show or (M)Movie: " && read -r media_type
      [ "$media_type" = "T" ] || [ "$media_type" = "t" ] && deez="tv-show" || deez="movie"
      get_input && main && exit 0 ;;
    h)
      printf "Usage: lobster [arg] <query> \n"
      printf "Play movies and TV shows from himovies.to\n"
      printf "  -c, \t\tContinue watching from last episode\n"
      printf "  -d, \t\tDelete history file\n"
      printf "  -u, \t\tUpdate script\n"
      printf "  -v, \t\tPrint version\n"
      printf "  -t, \t\tSuggest a trending TV Show or Movie\n"
      printf "  -h, \t\tDisplay this help and exit\n"
      exit 0 ;;
    \?)
      printf "Invalid option: -%s\n" "$OPTARG" >&2
      exit 1 ;;
  esac
done

if [ -z "$continue_history" ]; then
  get_input "$*"
  main
fi
