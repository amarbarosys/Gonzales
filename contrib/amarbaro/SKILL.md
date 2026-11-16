---
name: gonzales
description: "Operate the Gonzales spectral Mojo renderer on an AMD gfx1100 GPU: build, pick the integrator (PT, SPPM, VCM, MNEE), flags and env switches, supported scene features, tests that run without CUDA, Blender add-on, book map, gotchas. Use before any Gonzales build, render, fix, scene question or upstream PR."
metadata:
  short-description: "Operate the Gonzales spectral Mojo renderer on an AMD gfx1100 GPU: build, integrators, flags, scene support, tests without CUDA, Blender add-on, gotchas."
  license: MIT (this skill text only)
---

# gonzales

**Gonzales is not ours.** © 2019-2026 Andreas Wendleder, GPL-3. This skill (our notes on using it) is MIT; it grants
and claims nothing about Gonzales. Never put our licence, copyright or owner line into any file of the Gonzales repo
or fork outside our own folder; our additions sit in `contrib/amarbaro/` as separate MIT files that contain no Gonzales code (GPL-3 s5 "aggregate").

Spectral Monte Carlo renderer in Mojo (Andreas Wendleder, upstream `gonsolo/gonzales`, GPL-3): PT, SPPM, BDPT/VCM,
MNEE caustics, a-trous denoiser, pbrt-v4 + Mitsuba scenes, Blender Hydra add-on (`src/hdgonzales/blender`).
Paths below are relative to the Gonzales repo root. A digest of all docs can be kept untracked in `.work/`.

## Pick the task

| Task | Do this | Read more |
|---|---|---|
| Quality render of a scene | the "Quality sample" recipe below | "Quality sample" below |
| Smoke check after a change | `build-amd/gonzales --gpu --no-denoise --spp 4 --resolution 32x32 --seed 1 Scenes/cornell-box.pbrt` | Makefile:436-441 |
| Unit tests (AMD) | `make unittest-amd`: 554 tests baseline | README.md:11-12; Makefile:547-549 |
| Glass / water caustic scene | `--sppm` (water) or `--vcm` (glass, volumes); PT only finds 1-2 vertex caustics via MNEE | docs/05b_manifold_caustics.md:1-18; compare_bitterli.sh:76-130 |
| Many lights, direct light noise | `--restir` (diffuse only) | docs/A1_feature_status.md:17 |
| Smoky / foggy scene | PT (all media), VCM and SPPM only handle homogeneous media | docs/09_volumetric_media.md:13-21 |
| Long render that must survive a crash | `--checkpoint run.ckpt --checkpoint-every MIN`, later `--resume run.ckpt` | docs/08_rendering_pipeline.md:77-129 |
| Out of VRAM | `GONZALES_BATCH=2` (-3 GB at 1 MP, glass scenes +7 % wall), `GONZALES_MESH_HOST`, `GONZALES_ENV_DOWN=1`, `GONZALES_PTEX_BUDGET_MB`, `GONZALES_GPU_LOG=1` | src/gonzales/core/env.mojo:45-52,63 |
| What does flag or env X do | `build-amd/gonzales --list-env`; flags: `src/gonzales/__init__.mojo:204-340` (`--help` shows a subset only) | "Flags" |
| Scene feature supported? | render log: `Warning: unsupported ... Supported: ...` | "Scene support" |
| Render a `.blend` | Blender add-on engine GONZALES (Hydra), `make hydra` | "Blender add-on" |
| Why is the image blurry | `PixelFilter` lines of the scene | "Gotchas" |
| Which chapter explains X | "Book map" | docs/00_index.md:1-22 |

## When to use

Any Gonzales build, render, fix, memory work or upstream PR; any asset render with spectral light (glass, gems,
liquids, caustics, CG stock stills that carry no generative-AI label).

## Integrators

| Need | Flag / env | Notes (source) |
|---|---|---|
| Default, everything | `--gpu` (omit for CPU) | PT with NEE + MIS, MNEE on smooth glass; GPU wavefront, no GPU megakernel for PT (README.md:78-90; docs/A4_execution_modes_plan.md:20-26) |
| Turn MNEE off | `GONZALES_NO_MNEE=1` | GPU PT only (env.mojo:24) |
| Water / volumetric caustics | `--sppm [--sppm-passes N (64)] [--sppm-photons N] [--sppm-radius R]` | radius and photons default from the scene's `Integrator "sppm"` (compare_bitterli.sh:112-124); dense media off by density-dependent error (docs/A1_feature_status.md:22) |
| Subsurface via dipole | `--jb [--jb-spacing S --jb-near K]` | CPU, SPPM based (src/gonzales/__init__.mojo:150-153) |
| Glass caustics, closed rooms | `--vcm [--vcm-spp N --vcm-photons N --vcm-budget --vcm-cap N]`, `--vcm-wavefront` staged driver (same image) | no uniformgrid/nanovdb media; staged driver OOMs at 1920x1080 on 12 GB (docs/09_volumetric_media.md:13-21; docs/rtcore/NOTES.md:353-358) |
| Many lights | `--restir`, `--restir-gi` (needs `--restir`, CPU), `--sms-restir` (interactive only), `--vol-restir-reuse` (GPU, media) | docs/A1_feature_status.md:17-21; src/gonzales/__init__.mojo:177-194 |
| Guided paths | `--guide` | opt-in, measured no gain (docs/A4_execution_modes_plan.md:203-206) |

`compare_bitterli.sh` routes volumetric-caustic and glass-of-water to `--vcm`, water-caustic to `--sppm --sppm-passes 200`.
The CLI flag chooses the integrator, not the scene's `Integrator` line. Hardware RT (`--rt-hardware`) is NVIDIA only.

## Flags and env switches

Flags (src/gonzales/__init__.mojo:204-340): backend `--gpu --vulkan-rt --vulkan-rt-shade --rt-hardware --bake`; quality
`--spp N --seed N --resolution WxH --width --height --no-denoise --guide`; debug `--pixel X Y --verbose --list-env`;
viewer `--interactive --fullscreen --interactive-frames N`; long jobs `--checkpoint --checkpoint-every --resume
--stop-after`; integrators as above. A render without `--seed` takes the clock as seed (docs/08_rendering_pipeline.md:103-104).

There is no env switch for spp, denoiser strength or filter: noise = `--spp`, the scene's `Film`, `PixelFilter`,
`maxdepth`, and denoiser on/off. 62 env switches exist (env.mojo:13-80). Most useful:

| Group | Switch (default) | Effect |
|---|---|---|
| Data/caches | `GONZALES_DATA_DIR` (src/gonzales/data) | spectral tables, cwd-relative by default |
| | `GONZALES_SCENE_CACHE` file | parsed-scene cache; `.rt`, `.heat` next to it; tied to scene path and size |
| | `GONZALES_CAMERA_SCENE` file | camera and maxdepth from another pbrt file, one cache for many views |
| Quality | `GONZALES_NO_DENOISE` | `--interactive-frames` output not denoised |
| | `GONZALES_TEX_SPP` (16) | Ptex footprint as at N spp |
| | `GONZALES_CULL_SIZE` (0) | drop instances smaller than that fraction of image height |
| Memory | `GONZALES_BATCH` 1-8 (samples a pixel in flight: default 4 for a glass scene on the MNEE queue, else 8; each step down frees 0.55 GB a megapixel); `GONZALES_MNEE_INLINE=1` (old inline MNEE probe, no queue); `GONZALES_PTEX_BUDGET_MB` (2048); `GONZALES_MESH_HOST` KB; `GONZALES_MESH_VRAM_MB`; `GONZALES_ENV_HOST` KB; `GONZALES_ENV_DOWN=1` | host placement and budgets, mostly automatic |
| Backend | `GONZALES_RTCORE`, `GONZALES_RTCORE_CUBIN` (abs path), `GONZALES_RT_PRUNE=1`, `GONZALES_NO_SW_SHADOW` | NVIDIA RT-core options |
| Logs | `GONZALES_GPU_LOG`, `GONZALES_TIMING`, `GZ_VCM_TIMING=1\|2`, `GONZALES_FRAME_LOG`, `GONZALES_ROUND_LOG`, `GONZALES_BENCH=N` | stage and phase timings, free VRAM per upload |

## Scene support and limits

pbrt-v4 (`Include`, `Import`, `.pbrt.gz`, instancing) and Mitsuba. Unsupported items warn and fall back
(src/gonzales/core/diagnostics.mojo:1-35).

| Kind | Supported | Else |
|---|---|---|
| Shapes | trianglemesh, plymesh, loopsubdiv, disk, bilinearmesh, sphere, curve (src/gonzales/scene/description/pbrt_parser.mojo:1317-1322) | skipped, hole in scene |
| Materials | diffuse, conductor, dielectric, thindielectric, coateddiffuse, coatedconductor, diffusetransmission, mix, subsurface, interface/none, hair, measured (material_builder.mojo:563-568) | grey diffuse |
| Textures | imagemap, scale, mix, checkerboard, constant, ptex; mappings uv, planar, cylindrical, spherical; alpha only from imagemap (pbrt_parser.mojo:1205-1209,1709-1716,1747) | flat default / mesh uv / opaque |
| Lights | area, point, distant, infinite incl. portal (light_builder.mojo:17-111) | no spot, goniometric, projection handler (docs/A1_feature_status.md:75) |
| Media | homogeneous, uniformgrid, nanovdb (stub build: `.nvdb` off), cloud (baked 160^3) (pbrt_parser.mojo:946-951; docs/09_volumetric_media.md:36-44) | dropped: renders empty |
| PixelFilter | gaussian, box, triangle; default radius 1.5 / 0.5 / 2 (pbrt_parser.mojo:315-340) | mitchell, lanczos, sinc: Gaussian + warning |
| Film | rgb, spectral | gbuffer renders as rgb, no AOV channels (pbrt_parser.mojo:343-358) |
| Camera | perspective | `environment` unhandled (docs/A1_feature_status.md:75) |
| Mitsuba | bsdf diffuse, dielectric, thindielectric, roughdielectric; shapes serialized, obj, ply, rectangle, cube, sphere, disk (mitsuba_parser.mojo:702-706,866-871) | grey diffuse / skipped |

Not supported at all: motion blur, true displacement (rendered as bump like pbrt-v4), OIDN/OptiX denoiser
(docs/A1_feature_status.md:92-99; Documentation/ReleaseNotes/0.4.md:32). Output: beauty EXR + `albedo.exr`
(docs/08_rendering_pipeline.md:74-75). Deviations: Ptex capped at 4 texels per face side at default budget
(0.4.md:29-31); chromatic absorber gonzales/pbrt 1.30, 1.22, 0.73 (docs/02_spectra_and_color.md:186-200);
GPU PT not run-to-run reproducible, 4.5% of Cornell pixels differ (docs/08_rendering_pipeline.md:127-129).

## Build (measured 2026-11-16, Mojo 1.2.0, modular 26.7.0)

```
cd path/to/Gonzales
uv sync                                         # .python-version pins 3.14 (max 26.7 ships cp314 wheels only)
make release-amd AMD_TARGET=gfx1100             # default AMD_TARGET stays gfx1030 (RX 6800)
```
- On checkouts before these fixes use `uv venv --python 3.14` and
  `make release BUILD_DIR=build-amd CUDA_HOME=/nonexistent MOJO_BUILD_FLAGS="--target-accelerator gfx1100"`.
  282-361 s, 4.9-8.0 GB peak RSS, 75.8 MB binary. `make dev` builds a hint-free copy in ~3 min instead of ~10 (Makefile:345-351).
- System deps (Arch extra): `openimageio ptex vulkan-headers glfw`.
  CUDA/OptiX/NanoVDB absent -> their bridges build as stubs (expected; Makefile:98-130).

## Test (what runs on gfx1100)

- `make unittest-amd`: 67 files, 554 tests, all pass on main 7901141a (196 s, 2.4 GB). Keeps
  `Tests/unit/gpu/test_gpu.mojo`; CUDA interop and RT-core tests are stubs (Makefile:420-424,547-549,564-592).
- `make smoketest` uses `./build/gonzales`, not `build-amd`, and runs only CPU rows without CUDA (Makefile:436-441,524-541):
  run the Cornell flags above by hand on `build-amd`. `make analytictest` prints "skip" without CUDA
  (Makefile:488-494); `Scripts/analytic_check.py` and `Scripts/smoke_matrix.py` are GPU render checks and can be run by
  hand. `make causticstest` needs the Bitterli corpus (`CAUSTIC_REF_DIR`, default a home-relative `src/bitterli`) and builds `release`.
- `compare_bitterli.sh` / `compare_pbrt.sh` / `bench.sh` hard-code the gonzales binary, pbrt-v4 and corpus locations as home-relative paths,
  need `oiiotool` and a pbrt-v4 binary; edit paths before use (compare_bitterli.sh:3-8; bench.sh:1-31).

## Run

- Runs from any directory (absolute rpath; `src/gonzales/data` falls back to the binary's checkout,
  `GONZALES_DATA_DIR` overrides; src/gonzales/app/pipeline.mojo `data_dir_default`). Older checkouts fail outside the
  repo root (`liboiiobridge.so` not found, `cannot open Sobol data file`).
- Output goes to the scene's `Film "string filename"` in the cwd: move it away after each run.
- GPU: `timeout 240 build-amd/gonzales --gpu --spp 64 SCENE.pbrt`
- Flags used most: `--gpu --no-denoise --spp N --resolution WxH --seed N --list-env`.
- Measured, Cornell box 512x512, 64 spp: GPU 0.75 s / 309 MB, CPU 6.6 s / 130 MB; GPU vs CPU mean abs error 0.0017
  (sample noise).
- Docs numbers for scale: bathroom 1024 px 64 spp, RTX 3060: GPU 4.9 s, CPU 24.2 s (README.md:108-124).

## Quality sample = the standard for every render (GPU, best settings)

Every render runs `--gpu` (under a job scheduler or `timeout`); CPU only for a parity check. A sample shown to anyone:
```
timeout 1800 \
  build-amd/gonzales --gpu --spp 4096 --resolution 2048x2048 SCENE.pbrt      # denoiser on (default)
# white balance on a surface that is white in the scene (WR = 2*G/R, WB = 2*G/B of its patch avg; 2 = +1 EV):
oiiotool OUT.exr --ch R,G,B --crop X0,Y0,X1,Y1 --printstats | grep "Stats Avg"
oiiotool OUT.exr --ch R,G,B --iscolorspace "Linear Rec.709 (sRGB)" --mulc WR,2,WB \
  --ociodisplay "sRGB - Display" "ACES 2.0 - SDR 100 nits (Rec.709)" -d uint16 -o OUT.png
```
OCIO here is 2.x (`ocio://default`): the views are ACES 2.0; "ACES 1.0 - SDR Video" does not exist in it
(`oiiotool --colorconfiginfo` lists them). Measured on Cornell 2048 px 4096 spp: 273 s GPU, 0.7 GB RSS; wall grain
(high-pass std, 8-bit) 1.79 -> 0.15, edges 1 px. The Cornell lamp is very warm (EXR avg B = 0.18 R): unbalanced
it reads brown.
Never show `--no-denoise`, <= 256 spp or a plain `--colorconvert linear sRGB` clamp as quality: grain, clipped
lights and a muddy tone (reviewer verdict on the first sample).

## Blender add-on

Hydra render engine `GONZALES` (Blender >= 4.2): `make hydra` builds `build/hydra/hdGonzales.so` (+ `plugInfo.json`,
links `-lusd_ms`); plugin dir `GONZALES_HYDRA_DIR` or `build/hydra` (src/hdgonzales/blender/__init__.py:5-12;
Makefile:271-283). Panel: Integrator PATH/BDPT/VCM (default PATH), Viewport 32 spp, Render 64 spp, Max Depth 12, Denoise
on (`__init__.py:78-110`). Combined pass only; Cycles adaptive, clamp, glossy blur and bounce limits are carried over
(`__init__.py:20-40`). Materials Hydra cannot express (hair, glass, Principled, node graphs) are baked or compiled to
shader programs; no UVs -> image mean (`materials.py:1-18`, `shader.py:1-10`; docs/06_lights_and_materials.md:59-82).
Sky/colour worlds are baked by Cycles in a second Blender into a 2048 px EXR (`world.py:1-10`). Debug: `make gzreplay`
renders a recorded API session without Blender (Makefile:285-292).

## For assets

Render our `.blend` (Blender add-on) and `.glb` props (convert to pbrt) for stock stills and marketplace turntables:
CG of our own models carries no gen-AI label; spectral light gets glass, liquids and gems right. EXR out via OIIO.

## Book map (docs/)

00_index (contents) | 00_introduction (why Mojo, older module table) | 01_geometry (vectors, rays, PathState) |
02_spectra_and_color (hero wavelengths, RGB upsampling, chromatic media shortfall) | 02b_monte_carlo (estimator, MIS,
RR) | 03_shapes_and_acceleration (shapes, SAH BVH) | 04_sampling (cosine, GGX VNDF, Z-Sobol) | 05_reflection_models
(BSDFs, coated walk, hair, measured) | 05b_manifold_caustics (MNEE, SMS) | 06_lights_and_materials (lights, textures,
shader programs) | 07_path_tracing (bounce loop, CPU vs GPU) | 08_rendering_pipeline (parse, GPU wavefront, CPU tiles,
output, checkpoint/resume) | 09_volumetric_media (media, delta/ratio tracking, VCM volume bugs) | A0 roadmap
(historical) | A1_feature_status (feature tables, stale in places) | A2_restir_migration_plan (1328 lines, ReSTIR/SMS
phases) | A3_restir_theory (MIS/RIS/GRIS, VCM notes §8) | A4_execution_modes_plan (CPU/GPU x software/RT x PT/SPPM/VCM,
measurements) | A5_library_plan (layered packages) | MOJO_PORT_ROADMAP (historical) | PROFILING (Nsight findings) |
rtcore/NOTES.md (RT cores from CUDA, `--rt-hardware`) | rtcore/ACCEL_FORMAT.md (RT structure format).
Release notes: `Documentation/ReleaseNotes/0.4.md` (Moana on 12 GB, run recipe); 0.3 is Swift era.

## Gotchas

- Blurry image: check every `PixelFilter` line in the scene; the last one wins. `Scenes/cornell-box.pbrt` line 10 sets
  `gaussian xradius 5 sigma 2.5`: 6 px edges at 512 px. pbrt default (no PixelFilter, or `gaussian` alone: radius 1.5,
  sigma 0.5) gives 1 px edges. The denoiser does not cause it (`--no-denoise` keeps the 6 px) (README.md:22-23).
- PSNR/sharpness of renders: Laplacian variance is swamped by noise at <= 256 spp; measure an edge's 10-90 % width.
- `release-amd` without `AMD_TARGET=gfx1100` still builds for gfx1030 (RX 6800), not the 7900 XTX.
- `--help` lists a subset of the flags; read `src/gonzales/__init__.mojo:204-340` for `--sppm`, `--vcm`, `--rt-hardware`.
- Read the log for `Warning: unsupported` lines: a skipped shape or a grey material is not an error exit.
- `docs/A1_feature_status.md` (2026-08-05) is stale: says `measured` is a rough conductor and NanoVDB unsupported; chapters
  05 (lines 279-307) and 09 (13-21) and the README say both are supported. `docs/00_introduction.md` and 0.3 notes are old.
- `--rt-hardware` needs `rt_trace.cubin` found cwd-relative, else it silently falls back to Vulkan and looks 3.4x
  slower and darker (docs/A4_execution_modes_plan.md:34-38). NVIDIA only; not usable on gfx1100.
- GPU PT and `--gpu --vcm` are not bit-reproducible (float atomics); fix `--seed` for comparisons
  (docs/A3_restir_theory.md:340-346). VCM reads under PT in closed boxes at low maxdepth (Scripts/smoke_matrix.py:12-16).
- Scene cache is tied to the scene file path and size (0.4.md:48).
- VRAM of a GPU file render is mostly per-path buffers: n_pixels x batch x ~550 B (PathState 328, shadow 104, intersection 48, ...) plus ~2.5 GiB the runtime holds for kernel scratch (the diffuse kernel needs 21 KB a thread). Bathroom 1024 px, 64 spp (2026-11-16, MNEE queue de5e14ea): batch 8 7.3 s / 8.9 GB, 4 7.7 s / 6.7 GB, 2 8.4 s / 5.5 GB. Glass-blocked NEE samples are probed once a flush from a queue (src/gonzales/transport/mnee_queue.mojo), not inline, so a lower batch no longer pays the manifold solve's tail every round. Manifold chains are capped at MAX_SMS_VERTICES = 4 (about 1 KB of private memory a vertex in each MNEE kernel; build with `-D MAX_SMS_VERTICES=6` for three glass objects in a row).
- Timing: wall time on a GPU is noisy (7.5-9.8 s run to run on one scene); compare per-kernel numbers (docs/PROFILING.md:18-21).

## Fork workflow

Each fix its own commit, tests against the 554-test baseline, numbers in the commit body. Fork changes stay GPL-3 as part of Gonzales and small enough to offer upstream (README.md:7-12).
