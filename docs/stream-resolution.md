# Stream resolution (reverse-engineering notes)

The catalogue front-end is a Next.js app over TMDB. It does not host video:
the watch page embeds a third-party player in an iframe. This file documents
the request flow so `resolve_stream` can skip the iframes and hit the
underlying JSON APIs directly.

## Watch page

```
/watch/{type}/{id}[/{season}/{episode}]
  type = movie | tv
  id   = TMDB id
```

The route is `app/watch/[type]/[...slug]`. In the page chunk, the component
destructures the slug as `[M, L, B]`:

```js
let { type: A, slug: H } = e;
let [M, L, B] = H;              // M = id, L = season, B = episode
let [G] = useState(Number(L) || 1);   // season
let [X] = useState(Number(B) || 1);   // episode
```

So `/watch/movie/1284041` and `/watch/tv/108978/1/1`. The iframe `src` is
present in the server-rendered HTML, so a plain `curl` of the watch page is
enough to find the default player URL:

```
curl -s -A 'Mozilla/5.0' 'https://<front-end>/watch/movie/872585'
#  ... src="https://player.vidlove.cc/embed/movie/872585?autoplay=true&..."
```

## Server iframe URL builder

From the watch page chunk (`page-*.js`), function `v({server,type,id,season,episode,vidparams})`:

```js
s = (tv) ? `${id}/${season}/${episode}` : `${id}`;
switch (server) {
  case "111movies":  return `https://111movies.net/${type}/${s}?autoplay=1&theme=23ddc36c`;
  case "vidlove":    return (tv)
      ? `https://player.vidlove.cc/embed/tv/${id}/${season}/${episode}?${a}`
      : `https://player.vidlove.cc/embed/movie/${id}?${a}`;
  case "cinezo":     return (tv)
      ? `https://api.cinezo.net/tv/${id}/${season}/${episode}`
      : `https://api.cinezo.net/movie/${id}`;
  case "vidlinkpro": return `https://vidlink.pro/${type}/${s}?autoplay=true`;
  case "vidup":      return (tv)
      ? `https://vidup.to/tv/${id}/${season}/${episode}?autoPlay=true`
      : `https://vidup.to/movie/${id}?autoPlay=true`;
  case "videasy":    return `https://player.videasy.net/${type}/${s}?episodeSelector=true&overlay=true`;
  case "vsembed":    return (tv)
      ? `https://vsembed.ru/embed/tv/${id}/${season}/${episode}`
      : `https://vsembed.ru/embed/movie/${id}`;
  case "vidsuper":   return (tv)
      ? `https://vidsuper.net/tv/${id}/${season}/${episode}?nextEpisode=true&episodeSelector=true&overlay=true&skip_intro=true&color=6366F1`
      : `https://vidsuper.net/movie/${id}?nextEpisode=true&...`;
}
```

`a` (vidparams) is `autoplay=true&poster=true&chromecast=true&servericon=true&setting=true&pip=true&font=Roboto&fontcolor=ffffff&fontsize=20&opacity=0.5&primarycolor=ffffff&secondarycolor=ffffff&iconcolor=ffffff&server=Dark`
(plus `&logourl=...` for non-classic sites).

As of writing, `vidlink.pro` and `vidsuper.net` no longer resolve in DNS
(dead), so only the other six are relevant.

## Implemented backends

### rivestream.app (scrapper.rivestream.app)

`rivestream.app` is a Next.js aggregator with its own scraper API:

```
GET https://scrapper.rivestream.app/api/providers
    -> {"data":["apex","pulse","solstice","quasar","horizon","primevids","flowcast","asiacloud","citadel","hindicast","guru"]}

GET https://scrapper.rivestream.app/api/provider?provider={p}&id={tmdb_id}[&season={s}&episode={e}]
    -> {"data":{"sources":[{"quality":"HLS","url":"...","source":"...","format":"hls"}],"captions":[...]}}
```

`primevids`/`citadel` also want `&cb=<seconds/3000>` (a cheap cache-buster; the
client sends `Math.floor(Date.now()/3e6)`). The returned stream URLs are
referer-gated by `https://www.rivestream.app/`; several are
`proxy.valhallastream.dpdns.org/m3u8-proxy` URLs that forward the upstream
headers themselves. Playable directly by mpv (the extension-less `ts-proxy`
segments need `allowed_extensions=ALL`, which lobster already passes).

Provider preference in lobster: `quasar` (direct m3u8, most reliable) first,
then `apex`, `pulse`, `primevids`, `citadel`, `solstice`, and the rest.


### 1. vidlove / 111movies -> api.shows.st

`111movies.net` serves the *same* player build as `player.vidlove.cc`
(same `/assets/index-*.js`), so both share one backend.

Player fetches, per source, with `Accept: application/json` and any non-curl
`User-Agent` (plain `curl/8.x` gets `forbidden`):

```
https://api.shows.st/{type}?id={id}[&season={s}&episode={e}]&mode=json&sources={src}
  src: warden | cinefreak | moviebox2 | vidapi | moviebox | ipcloud | tcloud
```

Response:

```json
{
  "meta":      { "...tmdb metadata..." },
  "source":    null,          // or an object:
  "subtitles": [ { "label":"English", "file":"https://cache.vdrk.site/v1/vtt/.../English.vtt",
                   "type":"vtt", "source":"v1" }, ... ]
}
```

When `source` is an object:

```json
{
  "label": "VidAPI",
  "source": "vidapi",
  "url": "https://c.shows.st/api?d=...&internal_token=v1....internal.vidapi....",
  "manifest": "#EXTM3U\n#EXT-X-STREAM-INF:...RESOLUTION=1920x1080,...\nhttps://d.shows.st/api?d=...\n",
  "qualities": [ { "quality":"1080p", "codec":"h264", "url":"...", "type":"mp4" } ]
}
```

Important: the `d.shows.st` / `c.shows.st` / `a2.shows.st` URLs are
**referer-gated**. Without a referer (or with the wrong one) they return a
31577-byte `video/mp4` placeholder whose `ETag` is `dkrle0ht61g2od5` and whose
response carries `x-notice: harvest`. The accepted referer for tokens issued
by the vidlove player is `https://player.vidlove.cc/`.

```
# without referer   -> video/mp4, 31577 bytes (harvest placeholder)
# with referer      -> application/vnd.apple.mpegurl (real HLS playlist)
curl -s -H 'Referer: https://player.vidlove.cc/' 'https://c.shows.st/api?d=...'
```

Playback notes:

- `source.manifest` is an inline master playlist; its variant/segment URLs have
  **no file extension**, so mpv/ffmpeg need
  `--demuxer-lavf-o=allowed_extensions=ALL`.
- `source.qualities` (moviebox) are direct mp4 URLs, but they 302-redirect
  through `b.shows.st` and often 503; prefer manifest sources (`ipcloud`,
  `vidapi`, `tcloud`) first.
- `source.url` is the master playlist URL; with the vidlove referer it returns
  `application/vnd.apple.mpegurl`.

### 2. cinezo -> api.cinezo.net -> player.cinezo.live -> proxy1.flikhub.net

`api.cinezo.net/{type}/{id}[/{s}/{e}]` 301-redirects to
`https://player.cinezo.live/embed/{type}/{id}[/{s}/{e}]`. That SPA uses a
different proxy:

```
https://proxy1.flikhub.net/{type}?id={id}[&season={s}&episode={e}]&mode=json&sources={src}&hevc=1
  src: moviebox | cinefreak
```

Same response shape as shows.st, but the URLs are direct files behind their
proxy and **do not need a referer**:

```json
{
  "source": {
    "source": "cinefreak",
    "label": "CineFreak",
    "url": "https://proxy2.flikhub.net/proxy?url=<percent-encoded>&headers=<percent-encoded json>",
    "qualities": [
      { "quality":"MP4", "codec":"h264",
        "url":"https://proxy2.flikhub.net/proxy?url=...&headers=...", "type":"mp4" }
    ]
  },
  "subtitles": [ ... ]
}
```

`headers` is a percent-encoded JSON object (Referer/Origin/User-Agent) that
their proxy applies upstream; the client just fetches the `url` directly.

For **tv**, `moviebox` returns a per-episode mp4, while `cinefreak` often
returns a batch file (`S01E01-05`), so moviebox should be tried first for tv.
For **movies** either works; `cinefreak` tends to offer higher quality mkv.

### videasy (player.videasy.net -> player.videasy.to) — implemented

Two-step XOR-obfuscated source, with the decryption in the page chunk
`8351-*.js` (dynamic import for the watch component). The source list is
encrypted with a custom keystream (FNV-1a + murmur3-fmix + a sparse 61-word
state), not standard AES, so it is ported to a small Node snippet inside
`resolve_stream`.

```
GET https://api.speedracelight.com/seed?mediaId={id}
    -> {"seed":"59576942.TLxq0REt8JJKO4_m0TCZtX","ttlMs":30000}

GET https://api.speedracelight.com/cdn/sources-with-title?tmdbId={id}&mediaType={movie|tv}&seasonId={s}&episodeId={e}&enc=2&seed={seed}
    -> base64url ciphertext
```

Only `tmdbId`, `mediaType`, `seasonId`, `episodeId`, `enc` and `seed` are
required; `title`/`year`/`imdbId` are optional. Decrypted payload starts with
the magic bytes `mvm1` (`[109,118,109,49]`) followed by JSON:

```json
{
  "sources":   [ { "quality":"1080p", "url":"https://moon.peakstorm.top/vd/.../index-s1080p-v1-a1.m3u8" }, ... ],
  "subtitles": [],
  "thumbnail": "...",
  "playlist":  "https://moon.peakstorm.top/vd/.../master.m3u8"
}
```

The m3u8 URLs are referer-gated: any non-empty `Referer` works (lobster sends
`https://player.videasy.to/`). Segments are `.m4s` on `cleartrail.top`; mpv
plays them fine, and lobster also passes
`--demuxer-lavf-o=allowed_extensions=ALL` anyway.

Keystream derivation (from `8351-*.js`):

```js
K = [1116352408, ..., 3248222580]           // SHA-256 round constants
fmix(e)   = murmur3 fmix32 finalizer
rotl(e,t) = 32-bit rotate left
fnv(s)    = fmix(FNV-1a 32-bit of s)

a = fmix( fnv(seed) XOR fmix( mediaId XOR 2654435769 ) )
S = Array(61)
for e in 0..7:
    n = a % 61
    a = rotl(a + 2654435769, 7 + (7 & e))
    S[n] = a XOR fmix(a)
    a = fmix(a + n)
acc = fmix(2779096485 XOR a)

keystream byte k: repeat per counter c:
    n = acc % 61
    i = (n in S) ? -1 : 0
    d = S[n] (0 if unset)
    s = acc
    a = d XOR imul(2654435769, c + 1)
    l = (s XOR a) OR (s AND a AND i)
    l = rotl(l + acc, n & 31) XOR rotl(acc, (n*7) & 31)
    acc = fmix(l + 2654435769)
    S[n] = acc
    emit acc (little-endian 4 bytes)

plaintext = ciphertext XOR keystream; strip "mvm1" prefix.
```

`contrib/resolve-streams.mjs` has the full JS reference; `lobster.sh` embeds
the same algorithm as a compact `node` heredoc (guarded by
`command -v node`, with flikhub/shows.st as pure-shell fallback).

## Backends that still need JS crypto (not implemented)

### vidup.to

Next.js page. Server component passes an `en` token in the flight data and the
client player (a self-contained hls.js-like engine with AES-CBC/CENC decrypt
support, chunk `294-*.js`) uses it against an encrypted source endpoint. Needs
the token lifecycle + crypto reproduced; not done yet.

### vsembed.ru

```
https://vsembed.ru/embed/{type}/{id}[/{s}/{e}]
```

renders an iframe to:

```
https://cloudorchestranova.com/embed/{type}/{id}?vs={token}
```

which requires `Referer: https://vsembed.ru/` and loads
`/embed/iframe_player/assets/vsdec.js` (its own decryptor). Same situation as
videasy: needs JS crypto.

## Implementation

- `lobster.sh` `resolve_stream()`: videasy first (embedded Node decrypt, guarded
  by `command -v node`), then rivestream (scrapper API), then flikhub
  (cinezo), then api.shows.st (vidlove / 111movies). Subtitles come from the
  winning backend, or flikhub/shows.st when the winner has none. No deps
  beyond `curl`/`grep`/`sed`/`awk` plus optional `node` for videasy.
- `--provider videasy|rivestream|cinezo|vidlove` (or `provider=` in config)
  restricts `resolve_stream` to a single backend; omitting it runs the full
  fallback chain.
- `-j`/`--json` emits `sources` as a grouped object (`videasy`, `rivestream`,
  `cinezo`, `vidlove`) with every quality variant, plus the chosen
  `video_url`/`referer` and `subtitles`.
- `contrib/resolve-streams.mjs`: JS reference/prototype of the same logic
  (videasy + rivestream + cinezo + shows.st).
