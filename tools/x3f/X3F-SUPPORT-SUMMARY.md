# Sigma X3F (Foveon Quattro) support for RawTherapee — issue #4272

Branch: `x3f-quattro-support` (3 commits on top of `039b9b8`), +135 / −1 lines.

## What this does

RawTherapee can now open Quattro-generation X3F files (dp0/dp1/dp2/dp3
Quattro, sd Quattro, sd Quattro H) — the request in issue #4272 — and all
X3F files (including the already-supported SD9–Merrill range) now show full
EXIF metadata, which previously was completely missing.

## How (it was closer than expected)

The engine already had nearly everything: the `ST_FOVEON` sensor type, the
3-color/full-RGB data paths, the LibRaw integration adapted from ART
(including an `is_foveon` branch), and `.x3f` in the browser's extension
list. The bundled LibRaw 0.22.1 even ships the Kalpanika-derived X3F decoder
in `rtengine/libraw/src/x3f/` — it was simply compiled out because nothing
defined `USE_X3FTOOLS`.

### Commit 1 — Build bundled LibRaw with USE_X3FTOOLS
- New CMake option `WITH_LIBRAW_X3F` (default ON).
- `rtengine/LibRaw.cmake` appends `-DUSE_X3FTOOLS` to the LibRaw CXXFLAGS.
- No effect with `WITH_SYSTEM_LIBRAW` (depends on the system lib's build).

### Commit 2 — Decoder routing + white level
- `rawimage.cc`: pre-Quattro Foveon (Polaroid x530, SD9–SD1/DP Merrill)
  keeps going to the internal dcraw, whose output all existing
  camconst.json matrices/levels/crops were tuned for — zero rendering
  change for currently supported cameras. Only Quattro files (which dcraw
  cannot decode) go through LibRaw.
- `camconst.json`: white level 16383 for the sd Quattro H. LibRaw's
  internal table says 4000, but the decoded buffer is on a 14-bit scale —
  measured on real samples, ~5% of a normal frame sits above 4000 with
  hard clipping exactly at 16383. (The `!isFoveon()` guard in rawimage.cc's
  white-level bit-depth clamp already anticipates this kind of override.)

### Commit 3 — Metadata via the embedded JPEG
Exiv2 cannot parse X3F containers, so X3F files showed no EXIF at all.
Every X3F generation embeds a full-resolution JPEG preview carrying the
complete EXIF block. `metadata.cc` now falls back to locating that JPEG
(FOVb header → SECd directory → first `IMA2`/`IMAG` section with
format 18/JPEG) and feeding it to Exiv2 from memory. Bounds-checked
throughout; returns empty (and rethrows the original error) for anything
that isn't a well-formed X3F.

## Validation performed

Environment: Ubuntu 24.04 container, single core. Real X3F samples from
github.com/Kalpanika/x3f_test_files (sd Quattro H ×3, dp2 Quattro,
DP2 Merrill).

1. **Build**: bundled LibRaw configures and compiles cleanly with the flag;
   `LibRaw::cameraList()` reports all 10 Quattro/Merrill models as native
   (no "(DNG only)" suffix). Full RT `cmake` configure succeeds with the
   modified `LibRaw.cmake` (flag verified present in the generated LibRaw
   Makefile); `rawimage.cc` and `metadata.cc` compile with the project's
   real flags. `camconst.json` re-validated with a comment-aware JSON
   parser (309 entries).
2. **Decode**: a harness replicating `RawImage::loadRaw()`'s LIBRAW branch
   step-by-step (open_buffer → identify → unpack → color3_image →
   raw2image → is_foveon margin override → `compress_image` indexing)
   decodes both samples to correct, recognizable photographs:
   - sd Quattro H: 6656×4480 raw → 6208×4160 active, black 256,
     `test-decode-sd-quattro-h.png`
   - dp2 Quattro (old firmware, 5888×3672 frame variant): 5446×3624
     active, black 2047, `test-decode-dp2-quattro.png`
3. **Routing**: same harness confirms DP2 Merrill triggers the
   dcraw-fallback rule while both Quattro files stay on LibRaw.
4. **Metadata**: the extractor + Exiv2-from-memory path returns 170–212
   EXIF entries on all three generations (ISO, ExposureTime, FNumber,
   FocalLength, LensModel, DateTimeOriginal, ...).
5. **White level**: histogram of a normally exposed sd Quattro H frame:
   5.3%/4.6%/4.1% of R/G/B above 4000, 0.02% pinned at exactly 16383.

## Known limitations / sensible follow-ups

- **Color is "decode-grade"**: LibRaw's Quattro matrices are approximate
  (the sd Quattro/H entry is even marked `/* temp */` upstream). Camera WB
  multipliers aren't read from CAMF (`cam_mul = 0`), so "Camera" WB falls
  back to the matrix-derived neutral. Proper `dcraw_matrix` camconst
  entries should be derived from the RPU/issue-thread color-target shots —
  the established community process. Decode + levels + metadata are the
  foundation this provides.
- File-browser thumbnails for Quattro use the full raw decode (slower)
  since the dcraw-identify quick-thumb fields aren't populated on the
  LibRaw path; wiring LibRaw's `unpack_thumb` (which has X3F support)
  would speed this up.
- Untested here: SFD multi-shot files, sd Quattro (non-H), dp0/1/3
  Quattro, half-size RAW modes — LibRaw's `foveon_data` table covers their
  frame variants, but real-file confirmation (e.g. the issue's filebin
  re-upload or RPU) is advisable before merging.
- `WITH_SYSTEM_LIBRAW` builds won't get X3F unless the distro enables it;
  the release notes flag this for packagers.

## Local dev scaffolding

The scripts in this directory (`brew-install.sh`, `build.sh`, `run.sh`) set
up a macOS Apple Silicon build for local testing. The three patch commits
themselves live on the `x3f-quattro-support` branch / PR.

- `brew-install.sh install` — snapshot brew state, install build deps
- `brew-install.sh uninstall` — diff snapshot, remove only what was added
- `build.sh` — configure + build with `WITH_LIBRAW_X3F=ON` and `OSX_DEV_BUILD=ON`
- `run.sh [file.x3f]` — launch the dev build with the env vars GTK needs
- `test-decode-sd-quattro-h.png`, `test-decode-dp2-quattro.png` — decode
  evidence (quick previews: black-subtract, matrix, gamma only)
