#!/usr/bin/env bash
# Copyright (c) 2026 AMARBARO · amarbaro.org labs.
# SPDX-License-Identifier: MIT
# gz-render SCENE.pbrt [--out OUT.png] [--wb X0,Y0,X1,Y1] [--ev 1] [--spp 4096] [--res 2048] [--test]
# Gonzales render at the best settings by default: GPU (through gpu-wait when installed), denoiser on, 2048 px,
# 4096 spp, then the ACES 2.0 SDR view (OCIO 2.x), optional white balance on a patch that is white in the scene,
# 16-bit PNG. --test = 256 spp, 512 px, output named *-TEST.png so it is never mistaken for a result.
# GZ_DIR = the Gonzales checkout (default: the checkout this script sits in, else ~/Projects/imports/Gonzales).
set -euo pipefail
self="$(dirname "$(readlink -f "$0")")"
root="$(git -C "$self" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$root" && -d "$root/src/gonzales" ]] || root="$HOME/Projects/imports/Gonzales"
gz="${GZ_DIR:-$root}"
scene="${1:?usage: gz-render SCENE.pbrt [--out OUT.png] [--wb X0,Y0,X1,Y1] [--ev 1] [--spp 4096] [--res 2048] [--test]}"; shift
spp=4096 res=2048 ev=1 wb="" out="" test=0
while (($#)); do
  case "$1" in
    --spp) spp="$2"; shift 2 ;; --res) res="$2"; shift 2 ;; --ev) ev="$2"; shift 2 ;;
    --wb) wb="$2"; shift 2 ;; --out) out="$2"; shift 2 ;; --test) test=1; spp=256; res=512; shift ;;
    *) echo "FAIL args: unknown $1"; exit 1 ;;
  esac
done
[[ -f "$scene" ]] || { echo "FAIL gz-render: no scene $scene"; exit 1; }
[[ -x "$gz/build-amd/gonzales" ]] || { echo "FAIL gz-render: no $gz/build-amd/gonzales (skill gonzales: Build)"; exit 1; }
scene="$(realpath "$scene")"
out="${out:-${scene%.pbrt}$( ((test)) && echo -TEST).png}"
film=$(grep -oE '"string filename" *\[ *"[^"]+"' "$scene" | tail -1 | sed -E 's/.*"([^"]+)"$/\1/')
film="${film:-gonzales.exr}"
work="$gz/.work/gz-render"; mkdir -p "$work"
exr="$work/$(basename "${out%.png}").exr"
# Gonzales opens data files and its libs relative to the repo root: it must run from there
rm -f "$gz/$film"
queue=(); command -v gpu-wait >/dev/null && queue=(gpu-wait run --priority 60 --timeout 3600 --vram 12 --mem 12 --label gz-render --cwd "$gz" --)
( cd "$gz" && "${queue[@]}" /usr/bin/time -f 'GZ %e s %M KB' build-amd/gonzales --gpu --spp "$spp" --resolution "${res}x${res}" "$scene" ) \
  > "$work/last.log" 2>&1 || { echo "FAIL gz-render: render failed"; tail -5 "$work/last.log"; exit 1; }
[[ -f "$gz/$film" ]] || { echo "FAIL gz-render: no output $film"; tail -5 "$work/last.log"; exit 1; }
mv "$gz/$film" "$exr"
m=$(awk -v e="$ev" 'BEGIN{print 2^e}'); mr=$m mb=$m
if [[ -n "$wb" ]]; then
  read -r r g b < <(oiiotool "$exr" --ch R,G,B --crop "$wb" --printstats 2>&1 | awk '/Stats Avg/{print $3,$4,$5; exit}')
  mr=$(awk -v g="$g" -v c="$r" -v m="$m" 'BEGIN{print m*g/c}'); mb=$(awk -v g="$g" -v c="$b" -v m="$m" 'BEGIN{print m*g/c}')
fi
oiiotool "$exr" --ch R,G,B --iscolorspace "Linear Rec.709 (sRGB)" --mulc "$mr,$m,$mb" \
  --ociodisplay "sRGB - Display" "ACES 2.0 - SDR 100 nits (Rec.709)" -d uint16 -o "$out"
echo "gz-render: $(grep -oE 'GZ [0-9.]+ s [0-9]+ KB' "$work/last.log") ${res}px ${spp}spp ev=$ev wb=${wb:-none} -> $out (exr $exr)"
