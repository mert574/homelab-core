#!/usr/bin/env bash
# Generate the curated Jellyfin Live TV playlist for CT 110 (media).
#
# Sources channels from iptv-org (free, publicly-available streams) and remaps each
# channel's tvg-id to the matching epgshare01 XMLTV id so Jellyfin's guide (EPG) lines
# up. Curated to: top mainstream Turkish (entertainment + major news), international
# English news, and German public/news. Run daily by a systemd timer (see
# nix/hosts/media.nix); Jellyfin re-reads the file + re-fetches EPG on its own guide
# refresh. Streams geo-locked to Turkey/UK are dead from this German-hosted box.
set -uo pipefail
OUT="${1:-/var/lib/jellyfin/livetv/playlist.m3u}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
IPTV="https://iptv-org.github.io/iptv"
EPG="https://epgshare01.online/epgshare01"

# --- fetch channel sources ---
for cc in tr de uk us; do curl -fsSL "$IPTV/countries/$cc.m3u" -o "$TMP/$cc.m3u" || true; done
curl -fsSL "$IPTV/categories/news.m3u" -o "$TMP/news.m3u" || true
curl -fsSL "$IPTV/countries/int.m3u"  -o "$TMP/int.m3u"  || true

# --- epgshare01 channel ids (for tvg-id remap); US1 currently 404s, so skip it ---
for f in TR1 DE1 UK1; do curl -fsSL "$EPG/epg_ripper_${f}.xml.gz" -o "$TMP/$f.xml.gz" || true; done
zcat "$TMP"/*.xml.gz 2>/dev/null | grep -oP '<channel id="\K[^"]+(?=")' | sort -u > "$TMP/epgids.txt"

# normalized-core -> id table (strip country suffix, ENGLISH/HD tokens, non-alnum)
awk '{ id=$0; core=id; sub(/\.[a-z][a-z]$/,"",core);
       gsub(/[Ee][Nn][Gg][Ll][Ii][Ss][Hh]|HD/,"",core); gsub(/[^A-Za-z0-9]/,"",core);
       print toupper(core) "|" id }' "$TMP/epgids.txt" > "$TMP/cores.txt"

# explicit tvg-id overrides where the auto-match is wrong/ambiguous (name-substr -> id)
declare -A OVERRIDE=(
  ["EuroStar"]="Euro.Star.de"
  ["DW English"]="DEUTSCHE.WELLE.(EN).tr"
)

norm(){ echo "$1" | tr 'a-z' 'A-Z' | sed -E 's/\([0-9]+P\)//g; s/\[[^]]*\]//g; s/ENGLISH//g; s/\bHD\b//g' | tr -cd 'A-Z0-9'; }

epgid(){ # $1 = display name -> best epgshare01 id (or empty)
  local name="$1" o n hit
  for o in "${!OVERRIDE[@]}"; do case "$name" in *"$o"*) echo "${OVERRIDE[$o]}"; return;; esac; done
  n="$(norm "$name")"; [ -z "$n" ] && return
  hit="$(awk -F'|' -v n="$n" '$1==n{print $2; exit}' "$TMP/cores.txt")"
  echo "$hit"
}

# pick FIRST stream for a channel-name regex; prefer a non-geo-blocked feed.
# emits the EXTINF (with remapped tvg-id + given group) and its URL. $1=regex $2=group $3..=files
emit(){ local pat="$1" grp="$2"; shift 2
  local block ext url name eid
  block="$(awk -v p="$pat" 'BEGIN{IGNORECASE=1}
    /^#EXTINF/{l=$0; getline u; nm=l; sub(/.*,/,"",nm);
      if (nm ~ p && u ~ /^https?:/ && l !~ /Geo-blocked/){print l "\n" u; exit}}' "$@")"
  [ -z "$block" ] && block="$(awk -v p="$pat" 'BEGIN{IGNORECASE=1}
    /^#EXTINF/{l=$0; getline u; nm=l; sub(/.*,/,"",nm);
      if (nm ~ p && u ~ /^https?:/){print l "\n" u; exit}}' "$@")"
  [ -z "$block" ] && return
  ext="$(printf '%s' "$block" | sed -n 1p)"; url="$(printf '%s' "$block" | sed -n 2p)"
  name="${ext#*,}"; eid="$(epgid "$name")"
  # set tvg-id to the epg id (blank if none), and the group tag
  ext="$(printf '%s' "$ext" | sed -E "s/tvg-id=\"[^\"]*\"/tvg-id=\"${eid//\//\\/}\"/; s/group-title=\"[^\"]*\"/group-title=\"$grp\"/")"
  printf '%s\n%s\n' "$ext" "$url"
}

TR=("kanal d" "atv" "eurostar|star tv" "trt 1" "tv ?8" "kanal 7" "teve2" "beyaz" \
    "fox tv|now tv" "ntv" "habertürk|haberturk" "a haber|ahaber" "trt haber" "halk tv" \
    "tgrt haber" "ülke|ulke")
DE=("Das Erste" "ZDFneo" "ZDFinfo" "ZDF " "phoenix" "tagesschau" "ARD-alpha" "3sat" \
    "arte" "ProSieben" "SAT.1" "kabel eins")
EN=("GB News" "Al Jazeera English" "France 24 English" "DW English" "Euronews English" \
    "TRT World" "CGTN" "Africanews" "CNBC" "Bloomberg TV" "ABC News Live 1" "CBS News 24" \
    "NBC News NOW " "Reuters" "Channel 4 " "ITV1")

{
  echo "#EXTM3U"
  for p in "${TR[@]}"; do emit "$p" TR "$TMP/tr.m3u"; done
  for p in "${DE[@]}"; do emit "$p" DE "$TMP/de.m3u" "$TMP/int.m3u"; done
  for p in "${EN[@]}"; do emit "$p" EN "$TMP/uk.m3u" "$TMP/us.m3u" "$TMP/news.m3u" "$TMP/int.m3u"; done
} | tr -d '\r' > "$TMP/out.m3u"

n=$(grep -c '^#EXTINF' "$TMP/out.m3u")
[ "$n" -lt 20 ] && { echo "refusing to install a suspiciously small playlist ($n channels)" >&2; exit 1; }
install -D -m 644 "$TMP/out.m3u" "$OUT"
chown jellyfin:media "$OUT" 2>/dev/null || true
echo "wrote $n channels to $OUT ($(grep -c 'tvg-id=""' "$TMP/out.m3u") without EPG id)"
