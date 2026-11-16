[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Build](https://github.com/gonsolo/gonzales/actions/workflows/main.yml/badge.svg)](https://github.com/gonsolo/gonzales/actions/workflows/main.yml)
[![Test](https://github.com/gonsolo/gonzales/actions/workflows/test.yml/badge.svg)](https://github.com/gonsolo/gonzales/actions/workflows/test.yml)
[![Book](https://github.com/gonsolo/gonzales/actions/workflows/book.yaml/badge.svg)](https://github.com/gonsolo/gonzales/actions/workflows/book.yaml)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/4672/badge?v=1)](https://www.bestpractices.dev/projects/4672)

> **This fork (amarbarosys/Gonzales).** Gonzales is © 2019-2026 Andreas Wendleder and licensed under the GPL-3
> ([LICENSE](LICENSE)). This fork claims no rights over it; the changes listed here fall under the same GPL-3
> terms, as part of Gonzales. Upstream is [gonsolo/gonzales](https://github.com/gonsolo/gonzales); this
> fork runs it on an AMD Radeon RX 7900 XTX (gfx1100) to render 3D assets, and keeps each change small enough to
> offer back upstream. Every change below passes `make unittest-amd` on gfx1100 (67 files, 554 tests, same as
> upstream `7901141a`).
>
> | Change | Why |
> |---|---|
> | Removed `_to_spec_weight`, `Scene.with_camera_footprint`, `scene_parse_state_new` | Unused: every name in `src/` was counted over all tracked code, and these three had no use beyond their definition (the first lost its last callers in `cd6fdf82` and `339cd80a`). |
> | PLY big-endian and double readers: one load plus `byte_swap` instead of a heap allocation per value; removed the unused `_ply_u8_at` | About 19x faster on 64 MB of random bytes (354-400 ms to 19-20 ms) and bit-exact on all 67M offsets. Little-endian float PLY, the common case, was already a direct load. |
> | `.python-version` = 3.14 | `requires-python >=3.14` let `uv` pick 3.15, where `uv sync` fails: `max` 26.7 ships cp314 wheels only. A fresh venv now gets 3.14.10 (3.15.2 without the file). |
> | `make release-amd AMD_TARGET=gfx1100` (default stays gfx1030) | The target was hard-coded to the RX 6800. On the RX 7900 XTX it builds (282 s) and renders: Cornell box 512 px, 64 spp, GPU 0.75 s vs CPU 6.6 s. |
> | Runs from any directory: absolute rpath; data dir falls back to the binary's checkout (`GONZALES_DATA_DIR` still overrides) | It had to start from the repo root (`liboiiobridge.so` not found, `cannot open Sobol data file`). A GPU render from a directory outside the repo, without `LD_LIBRARY_PATH`, now works. |
> | Comment on `Scenes/cornell-box.pbrt`'s `PixelFilter` | Its gaussian (radius 5, sigma 2.5) makes edges about 6 px soft by design; the render is unchanged. |
> | `GONZALES_BATCH` (1-8): samples in flight for the GPU file render | The per-path buffers are pixels x batch; batch 8 is 4.5 GB of the Bitterli bathroom's 7.6 GB. Bathroom 1024 px, 64 spp: batch 8 7.9 s / 8,833 MiB, batch 4 9.2 s / 6,639 MiB, batch 2 11.4 s / 5,513 MiB. |
> | GPU path tracer: next-event samples blocked by glass go through an MNEE queue, probed once a flush | The shade kernel ran the manifold probe inline, so every bounce round waited for the longest solve (about 9 ms a round). Bathroom batch 8: 7.91 s -> 7.31 s (-8 %); batch 2: 11.4 s -> 8.43 s. |
> | `GONZALES_BATCH` defaults to 4 for a scene that uses the MNEE queue (others stay 8) | With the queue a lower batch no longer pays the solves' tail: bathroom VRAM peak 8,810 -> 6,708 MiB (-2.1 GiB) at the same wall; Cornell (no glass) unchanged and bit-identical. |
> | Diffuse shade kernel: a comptime variant without the ReSTIR DI/GI/SMS reuse for renders that never reuse reservoirs | Those branches were never taken by a file render but their stack counted as scratch: 24,384 -> 19,440 B a thread (-20 %, rocprofv3 Scratch_Size). |
> | `MAX_SMS_VERTICES` 6 -> 4, overridable with `-D` | About 1 KB of thread stack per vertex in the four kernels that carry the manifold solve (MNEE resolver 22,768 -> 20,624 B); bathroom, mnee-glass-cube and mnee-two-lights bit-identical between 6 and 4. |
> | `--check` lists a scene's fallback warnings from the parse alone, exit 3 if any | An agent had to start a render to learn a scene falls back (grey material, dropped shape, filter swap). Matches the warning lines of a real CPU render on 27 of 29 pbrt-v4-scenes files (the 2 others crash in the NanoVDB stub). |
> | `--noise T` and `--time S` stop the GPU file render early, per pixel and by the clock | The adaptive test and active-pixel buffers already existed for the Blender session only. Bathroom 512 px at equal time vs fixed 160 spp: relMSE 0.2563 -> 0.2130 (1.23x better). The stop rule biases the mean about 0.3 % low at `--noise 0.1` (known for adaptive stopping). |
> | Adaptive stop: divide by the square root of a bright pixel's intensity, as its comment and Cycles say | It divided by `I` above 1, so bright pixels stopped far too early (top 1 % of pixels had 8.5x the error). One line; the Blender session path shares the kernel and now matches Cycles. |
> | Removed an unused helper (`sm_reflect`) and a no-op loop; one `ReservoirBuffers[R]` for three field-for-field copies | 50 lines less (68,739 -> 68,689), every test and the 40-scene image gate (157 files, max abs error 0) unchanged. |
>
> Our own additions live apart in [`contrib/amarbaro/`](contrib/amarbaro/): a best-settings render script and an
> agent skill, MIT for that folder only, containing no Gonzales code.

# Gonzales — Physically Based Renderer

A production-capable spectral Monte Carlo renderer written in **Mojo**, designed
for high-end light transport simulation. Gonzales renders complex scenes —
including Disney's Moana Island, all 32 Bitterli benchmark scenes and a 65-scene
pbrt/Bitterli corpus — with path tracing, SPPM, BDPT and VCM on the CPU and on
NVIDIA and Intel GPUs, plus an à-trous wavelet denoiser.

📖 Read the [Gonzales Book](https://gonsolo.github.io/gonzales/) for detailed
documentation with annotated source code.

[![The whole Moana island on an RTX 3060](https://img.youtube.com/vi/dMYG1hy7kVY/maxresdefault.jpg)](https://youtu.be/dMYG1hy7kVY)

*The whole Moana island, interactive and fullscreen on an RTX 3060 with 12 GB ([video](https://youtu.be/dMYG1hy7kVY)).*

## Gallery

Benedikt Bitterli's scenes:

![Bitterli's scenes rendered with Gonzales](Images/gallery-bitterli.jpg)

The pbrt-v4 scenes:

![The pbrt-v4 scenes rendered with Gonzales](Images/gallery-pbrt.jpg)

*All rendered on an Intel Arc B580. The pbrt-v4 scenes and Bitterli's bathrooms,
bedroom, cars, classroom and coffee maker: 64 samples per pixel, denoised with
Intel Open Image Denoise. The other Bitterli scenes: 64 samples per pixel, or 32
SPPM passes for the two caustic scenes, denoised with Gonzales' own à-trous
denoiser.*

## Architecture

The renderer is written entirely in **Mojo** (~54,600 lines in `src/gonzales/`, plus
~12,700 lines of unit tests) and organized into focused groups of modules:

| Group | Lines | Responsibility |
|-------|------:|---------------|
| Shading and BxDFs | 12,700 | Diffuse, coated (pbrt's LayeredBxDF), conductor, dielectric, hair, measured, BSSRDF; spectral upsampling and sensors |
| Path tracer | 9,900 | CPU per-tile wavefront and GPU wavefront kernels, Z-Sobol sampler, film and outputs |
| Scene parsing | 9,400 | pbrt-v4 and Mitsuba parsers, PLY loader (threaded prefetch), materials, lights |
| BDPT / VCM | 6,900 | Bidirectional path tracing and vertex connection and merging (CPU and GPU) |
| Acceleration | 4,600 | SAH BVH2 (GPU) and BVH4 (CPU), instancing, native curve primitives |
| SPPM | 3,700 | Stochastic progressive photon mapping (CPU and GPU) |
| ReSTIR and guiding | 1,900 | Reservoir resampling (DI, GI, volumes, SMS) and path guiding |
| MNEE / SMS | 1,800 | Manifold next-event estimation and specular manifold sampling for glass caustics |
| Media | 1,800 | Homogeneous, uniform-grid, NanoVDB and cloud media |
| Denoising | 650 | GPU à-trous and CPU joint bilateral denoisers |
| Vulkan RT, RT cores, viewer | 460 | Second GPU backend, `--rt-hardware`, interactive viewer |

External C/C++ libraries (OpenImageIO, Ptex, Vulkan) are called via Mojo's
C FFI — not reimplemented.

## Key Features

- **Spectral transport** — Four hero wavelengths per path in every integrator, pbrt-style RGB-to-spectrum upsampling and sensor models
- **Wavefront GPU path tracing** — GPU kernels in Mojo with live-path compaction, compile-time kernel variants, deferred software shadow rays and an optional ray-tracing hardware backend (`--rt-hardware`): on NVIDIA with its own acceleration-structure builders (no Vulkan or OptiX in that path), on Intel through Level Zero's ray-tracing extension and ray queries
- **Fast CPU renderer** — Per-tile wavefront, 4-wide BVH with triangle records, vectorised shading
- **Four light-transport algorithms** — Path tracing, SPPM (`--sppm`), BDPT/VCM (`--vcm`) and ReSTIR variants, sharing materials, lights and MIS code
- **Specular caustics** — MNEE and SMS for glass and mirror caustics, with path-identity MIS so the result matches pbrt on the test cubes
- **Veach-style MIS** — Power heuristic balancing NEE and BSDF sampling; Russian roulette
- **Full material set** — Coated diffuse/conductor, rough and smooth dielectrics, hair, subsurface, measured BRDFs, alpha cutouts, bump and normal maps, Ptex
- **Volumes** — Heterogeneous media, NanoVDB, clouds, chromatic media
- **Scene formats** — PBRT-v4 (including object instancing and curves) and Mitsuba
- **Denoising** — Variance-adaptive à-trous GPU denoiser (Dammertz 2010) with albedo and normal guides
- **Interactive viewer** — Vulkan viewer with progressive refinement

## Testing

`make unittest` runs ~60 unit-test files concurrently; `make smoketest` runs an
integrator × feature matrix, and `make analytictest` checks renders against closed-form
furnace and plane solutions.

## Rendering Moana

| Version | Resolution | SPP | Time | Notes |
|---------|-----------|-----|------|-------|
| v0.0 (2021) | 2048×858 | 64 | 26h | GCE 8 CPU, 64 GB |
| v0.1 (2023) | 1920×800 | 64 | 78 min | Threadripper 1920X, with Embree |
| v0.2 (2026) | — | — | — | ARC cleanup, Embree removed |
| v0.3 (2026) | — | — | — | [Release Notes](Documentation/ReleaseNotes/0.3.md) |
| v0.4 (2026) | 1280×720 | 1/frame | ~7 fps | Whole island on a 12 GB RTX 3060, RT cores, interactive. [Release Notes](Documentation/ReleaseNotes/0.4.md) |

## Performance

Benchmark: [Bitterli bathroom](https://benedikt-bitterli.me/resources/) scene, 1024×1024, 64 spp, no denoiser.
Hardware: AMD Ryzen Threadripper 1920X (12 cores, 24 threads), NVIDIA RTX 3060 12 GB.

| Renderer | Mode | Wall time | Notes |
|---|---|---|---|
| **Gonzales** | GPU | **4.9s** | Wavefront path tracing, software BVH traversal (2.9 s of it rendering) |
| **Gonzales** | GPU (`--rt-hardware`) | 6.6s | Own RT-core structures; 3.3 s rendering, the rest is building them |
| **pbrt-v4** | GPU (OptiX) | 4.9s | Hardware RT cores |
| **Embree pathtracer** | CPU | 10.3s / 15.0s | Bare geometry / approximate materials, no textures (earlier measurement) |
| **Gonzales** | CPU | 24.2s | Full materials and textures (earlier measurement, not re-run) |
| **pbrt-v4** | CPU | 76.2s | Full materials and textures |

GPU rows measured on 2026-10-12 (median of three runs). Gonzales GPU is on par with pbrt GPU on this scene.
The CPU rows were not all measured on the same day, so they are not directly comparable, and Embree's
tutorial path tracer has no textures and only approximate materials.

### Lines of code

| Project | Lines (own code) |
|---|---|
| **Gonzales** | **~66,800** (Mojo, C/C++ and CUDA under `src/`) |
| pbrt-v4 | ~84,000 (excluding bundled data tables and third-party libs) |
| Embree kernel | ~96,000 (BVH/traversal only, no rendering) |

## Prerequisites

| Dependency | Description | Install (Arch) |
| --- | --- | --- |
| [Mojo](https://www.modular.com/mojo) (via `uv`) | Compiler; GPU target requires `--target-accelerator sm_XX` | `uv run mojo` |
| [OpenImageIO](https://github.com/AcademySoftwareFoundation/OpenImageIO) | EXR/HDR image I/O | `yay openimageio` |
| [Ptex](https://github.com/wdas/ptex) | Per-face texture mapping (Disney) | `yay ptex` |
| [Vulkan](https://vulkan.lunarg.com/) | Interactive viewer | `yay vulkan-icd-loader` |
| [Loupe](https://gitlab.gnome.org/GNOME/loupe) | EXR image viewer (for `make view_release`) | `yay loupe` |

For GPU rendering, set `--target-accelerator` to match your GPU's compute
capability (e.g. `sm_86` for RTX 3060, `sm_89` for RTX 4090).

## Installation

### Building from Source

```bash
make debug    # debug build
make release  # optimized release build
```

## Getting Started

1. Download scenes from [Bitterli](https://benedikt-bitterli.me/resources) (PBRT-v4 format) or [pbrt-v4-scenes](https://github.com/mmp/pbrt-v4-scenes)
2. Quick test — render and view a Cornell Box:
   ```bash
   make view_release
   ```
3. Or render any scene directly: `.build/release/gonzales path/to/scene.pbrt`
4. Environment switches (caches, memory budgets, logs): `gonzales --list-env` lists them; the table is `src/gonzales/core/env.mojo`.

## Acknowledgments

[Physically Based Rendering: From Theory to Implementation](https://www.pbr-book.org/) has been an inspiration since the project was called *lrt*.

© Andreas Wendleder 2019–2026
