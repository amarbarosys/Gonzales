# contrib/amarbaro: our additions (MIT)

Separate files that use Gonzales; they contain no Gonzales code. MIT applies to this directory only
([LICENSE](LICENSE)). Gonzales is (c) 2019-2026 Andreas Wendleder, GPL-3 ([../../LICENSE](../../LICENSE)).

| File | What |
|---|---|
| `gz-render.sh` | Render a pbrt scene at the best settings by default: GPU, denoiser, 2048 px, 4096 spp, ACES 2.0 SDR view (OCIO 2.x), optional white balance on a white patch (`--wb X0,Y0,X1,Y1`), 16-bit PNG. `--test` = 256 spp / 512 px, named `*-TEST.png`. Finds this checkout itself; uses `gpu-wait` only if installed. Needs `build-amd/gonzales` and `oiiotool`. |
| `test_gz-render.sh` | Its check: a `--test` render lands as a 512 px 16-bit `*-TEST.png`; bad input fails loudly. |
| `SKILL.md` | Agent skill for operating Gonzales: task table, integrators, flags and env switches, scene support, AMD build and tests, book map, gotchas, each with `path:lines` references into this repo. |
