#!/usr/bin/env bash
# Copyright (c) 2026 AMARBARO · amarbaro.org labs.
# SPDX-License-Identifier: MIT
# Gate for gz-render: a --test render lands as 16-bit *-TEST.png at 512 px, bad input fails loudly. Uses the GPU queue.
set -euo pipefail
t="$(dirname "$(readlink -f "$0")")/gz-render.sh"
root="$(git -C "$(dirname "$(readlink -f "$0")")" rev-parse --show-toplevel 2>/dev/null || true)"; [[ -n "$root" && -d "$root/src/gonzales" ]] || root="$HOME/Projects/imports/Gonzales"
gz="${GZ_DIR:-$root}"
work="$gz/.work/gz-render-test"; mkdir -p "$work"; sed '10d' "$gz/Scenes/cornell-box.pbrt" > "$work/cb.pbrt"
fails=()
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails+=("$1"); fi; }
out="$("$t" "$work/cb.pbrt" --test --wb 225,112,287,162)"
check "test render named -TEST" '[[ -s "$work/cb-TEST.png" ]] && grep -q "cb-TEST.png" <<<"$out"'
check "512 px, 16-bit" '[[ "$(oiiotool --info "$work/cb-TEST.png" 2>&1)" == *"512 x  512"*"uint16"* ]]'
check "missing scene fails loudly" '! "$t" "$work/nope.pbrt" >/dev/null 2>&1'
check "unknown flag fails loudly" '! "$t" "$work/cb.pbrt" --bogus >/dev/null 2>&1'
((${#fails[@]})) && { echo "FAIL ${#fails[@]} ${fails[*]}"; exit 1; }
echo "all green"
