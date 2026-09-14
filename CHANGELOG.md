# Changelog

## [Unreleased]

### Fixed

- On Linux, `rec` did not work, and neither did `play` whenever it used ALSA
  (for example with `default_driver=alsa` in `/etc/libao.conf`): both stopped
  with `Cannot access file …/alsa.conf`. The binary looked for the ALSA
  configuration in a directory that only existed on the build machine. That
  configuration is now built into the binary, so ALSA no longer needs any
  files from the system; `/etc/asound.conf` and `~/.asoundrc` still apply.
  Every Linux binary released so far is affected.

- Reading audio from a pipe without naming its format, as in
  `cat song.flac | sox - out.wav`, failed on Linux and Windows. The format is
  now detected, as it already was on macOS.

- On Windows, reading WAV and other formats from a pipe failed even with the
  format given, as in `type song.wav | sox -t wav - out.flac`
  (`invalid chunk ID found`).

### Added

- The formats SoX reads and writes through libsndfile — `caf`, `w64`, `paf`,
  `pvf`, `mat4`, `mat5` and `fap` — on Linux and Windows. The released
  binaries have none of them.

- On Linux, `rec` records from PulseAudio or PipeWire directly.

### Removed

- The `ladspa` effect and the `--magic` option on Linux. Neither could work in
  this binary — LADSPA plugins are shared libraries it can't load, and
  `--magic` had no libmagic database to read — and the macOS and Windows
  binaries never had them.
