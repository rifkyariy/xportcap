# Xportcap

A macOS app that turns CapCut's encrypted draft cache back into playable video and audio.

CapCut keeps rendered clips (`Resources/combination/*.mp4`) and processed audio
(`Resources/audioAlg/*.wav`) inside each draft folder, scrambled so no player opens them.
Xportcap finds those files, works out how each one was scrambled, checks every frame
decodes, and exports a normal file. Your CapCut drafts are only read, never modified.

## Features

- Lists your CapCut projects with covers, and shows which ones contain locked media
- Exports video as **Original HEVC MP4** (lossless, instant), **H.264 1080p**, or **ProRes 4444**
- ProRes keeps transparency when the clip has an alpha matte (`*.mp4.alpha.mp4`)
- Exports 16-bit PCM **WAV** audio
- Live progress per file, Export All, dark/light/system appearance
- Solved parameters are cached, so a second export of the same file is instant

## Requirements

- macOS 15 or later (Apple silicon or Intel)
- Swift 6 toolchain (Xcode 16+ or the Command Line Tools)
- CapCut drafts in `~/Movies/CapCut/User Data/Projects/com.lveditor.draft`

## Build and run

```bash
./build-app.sh            # release build -> build/Xportcap.app (icon included, ad-hoc signed)
open build/Xportcap.app
```

For development, `swift build` and `swift run Xportcap` also work.

Exports go to `~/Movies/xportcap` by default; change it under **Settings → Choose Output Folder…**.

## Command line

The same binary has headless modes, useful for testing:

```bash
.build/release/Xportcap --solve FILE.mp4 [FILE.wav ...]        # print key, P, L per file
.build/release/Xportcap --export SRC DEST [original|h264|prores] # full export with progress
.build/release/Xportcap --render-icon OUT.png                    # 1024 px app icon
```

## How it works

Each file is XORed with a single byte, but only in periodic blocks: byte `x` is scrambled
iff `(x mod P) < L`. Roughly 80–92% of the file is untouched. The three parameters differ
per file:

| Parameter | How it is recovered |
|---|---|
| `key` | Known magic bytes at offset 0 (`00 00 00` for MP4, `RIFF` for WAV) |
| `P` (period) | Probe HEVC NAL headers / AAC frames for scrambled vs. plain, then find the period whose residues separate them |
| `L` (length) | Video: decode one keyframe per candidate with VideoToolbox. Audio: pick the byte boundary where the waveform is smoothest |

Every video result is accepted only after **all** frames decode. Off-by-one in `L` still
parses fine but corrupts pixels, so structure checks alone are not trusted.

Which files are encrypted is read from each project's `crypto_key_store.dat`
(zlib-compressed BSON), not guessed.

## Project layout

```
Sources/
  App/         XportcapApp (entry), CLI (headless modes)
  Models/      Project, Params, ExportFormat, JobState
  Data/        ProjectIndex (root_meta_info.json), KeyStore (crypto_key_store.dat)
  Decryption/  MP4 box parsing, VideoSolver, WavSolver
  Export/      Exporter (single entry point), AlphaMerge, ParamCache
  ViewModels/  Library (projects), ExportQueue (jobs + progress)
  Views/       RootView, Sidebar/, Detail/, Components/, Brand/
```

## Known limits

- WAV support covers 16-bit PCM only.
- ProRes exports with transparency have no audio track; export Original or H.264 for audio.
- The 32-byte `crpt` blob in each file probably encodes the parameters directly; it is not
  cracked yet, so parameters are recovered from content instead.

## Disclaimer

For recovering your own projects. Not affiliated with CapCut or ByteDance.
