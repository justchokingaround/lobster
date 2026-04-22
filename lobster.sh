#!/usr/bin/env sh

tmdb_base="https://www.themoviedb.org"
tab=$(printf '\t')
thumbnails_dir="${TMPDIR:-/tmp}/lobster-thumbnails"
mkdir -p "$thumbnails_dir"

cleanup() {
    rm -rf "$thumbnails_dir"
    exit
}
trap cleanup EXIT INT TERM HUP

flash() {
    for i in $(seq "${1:-2}"); do
        printf '\e[?5h'
        sleep 0.1
        printf '\e[?5l'
        sleep 0.1
    done
}

die() {
    flash
    printf '\033[1;31m✖ Error:\033[0m %s\n' "$*" >&2
    exit 1
}

warn() {
    printf '\033[1;33m⚠ Warning:\033[0m %s\n' "$*" >&2
}

info() {
    printf '\033[1;32m→\033[0m %s\n' "$*" >&2
}

log() {
    [ "${DEBUG:-0}" = "1" ] || return 0
    printf '\033[1;34m● [DEBUG]\033[0m %s\n' "$*" >&2
}

curl_safe() {
    out=$(curl -sL --max-time 10 "$1") || die "curl failed (network error): $1"
    [ -z "$out" ] && die "curl returned an empty response $1"
    printf "%s\n" "$out"
}

download_thumbnails() {
    while IFS="$tab" read -r id url _date title; do
        # Sets res to 600x900
        url=$(printf "%s\n" "$url" | sed -E "s@w[0-9]+_and_h[0-9]+_@w600_and_h900_@g")
        thumbnail_path="$thumbnails_dir/$title  $id.jpg"
        curl -sL -o "$thumbnail_path" "$url" &
        pids="$pids $!"
    done <<EOF
$1
EOF
    # Wait for background jobs to finish
    for pid in $pids; do
        wait "$pid" 2>/dev/null
    done
}

query=$(printf "%s\n" "$*" | tr ' ' '+')
response=$(curl -sL -H 'accept-language: en-US' "$tmdb_base/search?query=$query")

results=$(printf "%s\n" "$response" |
    sed 's/class="comp:media-card/\
/g' |
    sed -nE 's@.*href="/movie/([0-9]+)[^"]*".*<img alt="([^"]+)".*src="([^"]+)".*<span class="release_date[^>]*">([^<]+)</span>.*@\1\t\3\t\4\t\2@p')
[ -z "$results" ] && die "No results were found, something went wrong with your network or query"

download_thumbnails "$results"

found=$(find "$thumbnails_dir" -name "*.jpg" 2>/dev/null | head -1)
[ -z "$found" ] && die "No thumbnails were downloaded, something went wrong with your network or query"

file_list=$(printf "%s\n" "$results" | sed -E 's/([^\t]+)\t[^\t]+\t[^\t]+\t(.*)/\2  \1.jpg/')
user_choice=$(printf "%s\n" "$file_list" | fzf -d "  " --with-nth 1 --preview "chafa $thumbnails_dir/{}")
rc=$?
[ "$rc" -ne 0 ] && die "No selection made"
[ -z "$user_choice" ] && die "No selection made"

title=$(printf "%s\n" "$user_choice" | sed -nE "s@(.*)  .*\.jpg@\1@p")
tmdb_id=$(printf "%s\n" "$user_choice" | sed -nE "s@.*  (.*)\.jpg@\1@p")

echo "The TMDB ID of the movie you selected ($title) is: $tmdb_id"
