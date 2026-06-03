# sox

Standalone build of [SoX](https://sourceforge.net/projects/sox/) (Sound eXchange)
— the audio Swiss-army knife: convert, play, record and process audio across a
huge range of formats and effects (`sox` / `play` / `rec` / `soxi`).

[![CI](https://github.com/unpins/sox/actions/workflows/sox.yml/badge.svg)](https://github.com/unpins/sox/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

## Usage

Run `sox` with [unpin](https://github.com/unpins/unpin):

```bash
unpin sox in.wav out.flac    # convert in.wav to out.flac
```

To install it onto your PATH:

```bash
unpin install sox
```

`unpin install sox` also creates the `play`, `rec`, and `soxi` commands.

## Programs

One binary provides four commands:

| command | what it does                                                     |
| ------- | ---------------------------------------------------------------- |
| `sox`   | convert and process audio, applying any chain of effects         |
| `play`  | play one or more files through the sound device                  |
| `rec`   | record from the sound device to a file                           |
| `soxi`  | print format / header info for an audio file                     |

`play` / `rec` talk to the OS sound system out of the box — PulseAudio/PipeWire
(falling back to ALSA, then OSS) on Linux, CoreAudio on macOS, WMM on Windows —
with no shared libraries alongside the binary.

## Build locally

```bash
nix build github:unpins/sox
./result/bin/sox --version
```

Or run directly:

```bash
nix run github:unpins/sox -- --version
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/sox/releases) page has standalone binaries for manual download.

## Build notes

- `sox` is the one real binary; `play`, `rec` and `soxi` are the argv[0]
  symlinks upstream's install hook creates, dispatched on `basename(argv[0])`
  inside `sox.c`. No multicall surgery — `lib.withAliases` just harvests the
  three symlinks into an UNPIN_META block so unpin recreates them at install.
- Live audio is fully static and routed through **libao**, not SoX's own device
  backends. SoX's static ALSA backend dies on a modern PulseAudio/PipeWire
  desktop (libasound dlopen's its routing module, impossible under static musl),
  and its pulse backend can't satisfy the static libpulse dep chain. libao's
  backends are instead compiled directly into the binary as built-in drivers
  (pulse + alsa + oss on Linux, CoreAudio on macOS); playback talks straight to
  the PulseAudio/PipeWire socket — no dlopen, no daemon library on disk.
- MP3 **encode** (lame) is enabled; decode (libmad) is already on. The rest of
  the codec set — libsndfile, libvorbis, opusfile, flac, wavpack and libpng (for
  spectrograms) — links static from `pkgsStatic`.
- **Windows** is built with mingw and carries no companion DLLs. Playback uses
  SoX's native WMM (waveaudio) backend; libao/alsa/pulse are Linux-only and left
  out.
- The SoX man pages are embedded in the binary.
