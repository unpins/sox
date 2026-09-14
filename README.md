# sox

[SoX](https://sourceforge.net/projects/sox/) (Sound eXchange) — the audio Swiss-army knife: convert, play, record and process audio across a huge range of formats and effects (`sox` / `play` / `rec` / `soxi`). A single self-contained binary, built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/sox/actions/workflows/sox.yml/badge.svg)](https://github.com/unpins/sox/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install sox`.

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

| command | what it does                                                     |
| ------- | ---------------------------------------------------------------- |
| `sox`   | convert and process audio, applying any chain of effects         |
| `play`  | play one or more files through the sound device                  |
| `rec`   | record from the sound device to a file                           |
| `soxi`  | print format / header info for an audio file                     |

`play` and `rec` use the system's sound server with no extra libraries:
PulseAudio or PipeWire on Linux (falling back to ALSA, then OSS), CoreAudio on
macOS, and the Windows audio API on Windows.

## Man pages

The SoX manual is embedded in the binary — read it with `unpin man sox`, or name
a page: `unpin man sox soxi`, `unpin man sox soxformat`.

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

- On Linux, ALSA's standard configuration is built into the binary, so ALSA
  works without the system's `/usr/share/alsa`. Your own settings in
  `/etc/asound.conf`, `/etc/alsa/conf.d` and `~/.asoundrc` still apply.
- The `ladspa` effect and the `--magic` option are not included: LADSPA plugins
  are shared libraries, which a single self-contained binary can't load, and
  `--magic` needs a libmagic database.
- The AMR-NB and AMR-WB formats are not included; their codecs are not free
  software.
- MP3 encoding (LAME) is included.
- Windows is built with mingw.
