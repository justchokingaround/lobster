#!/usr/bin/env node
// Prototype stream resolver, ported from the POSIX-shell resolve_stream.
//
// This is the reference implementation the POSIX-shell `resolve_stream` in
// lobster.sh was ported from. It skips the site's iframes and talks directly
// to the JSON backends the default players use, in order of preference:
//   * videasy (player.videasy.to) -> api.speedracelight.com (XOR-obfuscated)
//   * cinezo (player.cinezo.live) -> proxy1.flikhub.net   (direct mp4/mkv proxy)
//   * vidlove / 111movies       -> api.shows.st           (HLS master playlists)
//
// usage: node resolve-streams.mjs <type> <tmdb_id> [season] [episode] [quality] [subs_language]
// stdout: <video_url>\t<referer>\t<sub_url,sub_url,...>
//
// Reverse-engineering notes for all iframe servers live in
// docs/stream-resolution.md. The remaining servers (vidup, vsembed) still
// need their own WebCrypto step and are not implemented here.

const type = process.argv[2];
const id = process.argv[3];
const season = process.argv[4] || '1';
const episode = process.argv[5] || '1';
const quality = (process.argv[6] || '1080').replace(/\D/g, '') || '1080';
const lang = (process.argv[7] || 'english').toLowerCase();
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36';

async function getJSON(url) {
  const r = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/json' } });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
}

function pickQuality(qualities, target) {
  if (!qualities || !qualities.length) return null;
  const t = parseInt(target, 10) || 1080;
  return qualities
    .map(q => {
      const m = String(q.quality || '').match(/(\d{3,4})/);
      const h = m ? parseInt(m[1], 10) : 0;
      return { q, h, d: Math.abs(h - t) };
    })
    .sort((a, b) => a.d - b.d || b.h - a.h)[0].q.url;
}

function filterSubs(subs, lang) {
  if (!subs || !subs.length) return '';
  const out = [];
  for (const s of subs) {
    const label = (s.label || '').toLowerCase();
    if (!label.includes(lang)) continue;
    const f = s.file || s.url;
    if (f && !out.includes(f)) out.push(f.replace(/ /g, '%20'));
  }
  return out.join(',');
}

// highest/closest-resolution variant URL from an HLS master manifest body
function pickVariant(manifest, targetH) {
  const lines = manifest.split(/\r?\n/);
  const variants = [];
  for (let i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
    const m = lines[i].match(/RESOLUTION=(\d+)x(\d+)/);
    const h = m ? parseInt(m[2], 10) : 0;
    let j = i + 1;
    while (j < lines.length && (lines[j].startsWith('#') || lines[j].trim() === '')) j++;
    if (j < lines.length) variants.push({ url: lines[j].trim(), h });
  }
  if (!variants.length) return null;
  variants.sort((a, b) => Math.abs(a.h - targetH) - Math.abs(b.h - targetH) || b.h - a.h);
  return variants[0].url;
}

// ---------------- videasy (speedracelight) ----------------
const K = [1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221, 3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580];
const MAGIC = [109, 118, 109, 49]; // "mvm1"
const fmix = e => { e >>>= 0; e ^= e >>> 16; e = Math.imul(e, 2246822507) >>> 0; e ^= e >>> 13; e = Math.imul(e, 3266489909) >>> 0; return (e ^= e >>> 16) >>> 0; };
const rotl = (e, t) => { e >>>= 0; t &= 31; return t ? (e << t | e >>> 32 - t) >>> 0 : e >>> 0; };
const fnv = s => { let t = 2166136261; for (let i = 0; i < s.length; i++) t = Math.imul(t ^ s.charCodeAt(i), 16777619) >>> 0; return fmix(t); };
function keygen(seed, mid) {
  let a = fmix((fnv(seed) ^ fmix(((Number(mid) >>> 0) ^ 2654435769) >>> 0)) >>> 0) >>> 0;
  const S = new Array(61);
  for (let e = 0; e < 8; e++) {
    const n = a % 61;
    a = rotl((a + 2654435769) >>> 0, 7 + (7 & e));
    S[n] = (a ^ fmix(a)) >>> 0;
    a = fmix((a + n) >>> 0);
  }
  return { S, acc: fmix((2779096485 ^ a) >>> 0) >>> 0 };
}
function step(k, c) {
  const S = k.S; let o = k.acc; const n = o % 61;
  const i = 0 - Number(n in S); const d = S[n] >>> 0; const s = o;
  const a = (d ^ Math.imul(2654435769, c + 1)) >>> 0;
  let l = (((s ^ a) >>> 0) | ((s & a & i) >>> 0)) >>> 0;
  l = (rotl((l + o) >>> 0, 31 & n) ^ rotl(o, 31 & Math.imul(n, 7))) >>> 0;
  o = fmix((l + 2654435769) >>> 0);
  S[n] = o >>> 0; k.acc = o;
  return o >>> 0;
}
function decrypt(ct, seed, mid) {
  const r = new Uint8Array(Buffer.from(ct.replace(/-/g, '+').replace(/_/g, '/').padEnd(4 * Math.ceil(ct.length / 4), '='), 'base64'));
  const k = keygen(seed, mid);
  const ks = new Uint8Array(r.length);
  let o = 0;
  for (let e = 0; e < r.length;) {
    const t = step(k, o++);
    ks[e++] = 255 & t; if (e < r.length) ks[e++] = t >>> 8 & 255; if (e < r.length) ks[e++] = t >>> 16 & 255; if (e < r.length) ks[e++] = t >>> 24 & 255;
  }
  for (let e = 0; e < r.length; e++) r[e] ^= ks[e];
  for (let e = 0; e < 4; e++) if (r[e] !== MAGIC[e]) throw new Error('decrypt failed');
  return Buffer.from(r.subarray(4)).toString('utf8');
}

async function videasy() {
  const h = { 'User-Agent': UA };
  const seed = (await (await fetch(`https://api.speedracelight.com/seed?mediaId=${id}`, { headers: h, signal: AbortSignal.timeout(15000) })).json()).seed;
  const p = new URLSearchParams({ tmdbId: id, mediaType: type, seasonId: String(season), episodeId: String(episode), enc: '2', seed });
  const resp = await fetch(`https://api.speedracelight.com/cdn/sources-with-title?${p}`, { headers: h, signal: AbortSignal.timeout(15000) });
  if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
  const j = JSON.parse(decrypt(await resp.text(), seed, id));
  const url = pickQuality(j.sources, quality);
  if (!url) throw new Error('no sources');
  return { url, referer: 'https://player.videasy.to/', subs: filterSubs(j.subtitles, lang) };
}

// ---------------- rivestream (scrapper) ----------------
async function rivestream() {
  const order = ['quasar', 'apex', 'pulse', 'primevids', 'citadel', 'solstice', 'horizon', 'flowcast', 'asiacloud', 'hindicast', 'guru'];
  for (const p of order) {
    try {
      let url = `https://scrapper.rivestream.app/api/provider?provider=${p}&id=${id}`;
      if (type === 'tv') url += `&season=${season}&episode=${episode}`;
      if (p === 'primevids' || p === 'citadel') url += `&cb=${Math.floor(Date.now() / 3e6)}`;
      const j = await getJSON(url);
      if (!j || !j.data || !j.data.sources || !j.data.sources.length) continue;
      const video = j.data.sources[0].url;
      const subs = filterSubs(j.data.captions || [], lang);
      if (video) return { url: video, referer: 'https://www.rivestream.app/', subs };
    } catch { /* next */ }
  }
  return null;
}

// ---------------- cinezo (flikhub) ----------------
function apiUrl(base, src, hevc) {
  const q = type === 'tv'
    ? `tv?id=${id}&season=${season}&episode=${episode}&mode=json&sources=${src}`
    : `movie?id=${id}&mode=json&sources=${src}`;
  return `${base}/${q}${hevc ? '&hevc=1' : ''}`;
}

async function cinezo() {
  const order = type === 'tv' ? ['moviebox', 'cinefreak'] : ['cinefreak', 'moviebox'];
  for (const src of order) {
    try {
      const j = await getJSON(apiUrl('https://proxy1.flikhub.net', src, true));
      if (!j || !j.source) continue;
      const url = pickQuality(j.source.qualities, quality);
      if (url) return { url, referer: '', subs: filterSubs(j.subtitles, lang) };
    } catch { /* next */ }
  }
  return null;
}

// ---------------- vidlove / 111movies (shows.st) ----------------
async function showsst() {
  for (const src of ['ipcloud', 'vidapi', 'tcloud', 'warden', 'moviebox2', 'moviebox', 'cinefreak']) {
    try {
      const j = await getJSON(apiUrl('https://api.shows.st', src, false));
      if (!j || !j.source) continue;
      let url = pickQuality(j.source.qualities, quality);
      if (!url && j.source.manifest) url = pickVariant(j.source.manifest, parseInt(quality, 10));
      if (!url && j.source.url) url = j.source.url;
      if (url) return { url, referer: 'https://player.vidlove.cc/', subs: filterSubs(j.subtitles, lang) };
    } catch { /* next */ }
  }
  return null;
}

(async () => {
  for (const fn of [videasy, rivestream, cinezo, showsst]) {
    try {
      const r = await fn();
      if (r) {
        // fill in subtitles from the other backends if the chosen one had none
        if (!r.subs) {
          for (const subFn of [cinezo, showsst]) {
            try { const s = await subFn(); if (s && s.subs) { r.subs = s.subs; break; } } catch { }
          }
        }
        console.log(`${r.url}\t${r.referer}\t${r.subs}`);
        return;
      }
    } catch { /* next */ }
  }
  console.error('no stream found');
  process.exit(1);
})();
