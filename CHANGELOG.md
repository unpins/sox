# Changelog

## [Unreleased]

## [unstable-2021-05-09-2] - 2026-09-26

### Changed

- The Windows binary is now built by the same compiler as the Linux and macOS
  ones. It is about 14% smaller (4.65 MB to 4.00 MB); `--version` and
  conversions to FLAC, MP3, Ogg Vorbis and CAF, including from a pipe, were
  checked under Wine.

  It now uses the Universal C Runtime, which is part of Windows 10 and later.
  On Windows 7 or 8.1 that runtime has to be installed first — it comes through
  Windows Update. The previous binary did not need it.

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

- On Windows, pipes were treated like files. Reading WAV and other formats
  from a pipe failed even with the format given, as in
  `type song.wav | sox -t wav - out.flac` (`invalid chunk ID found`), and
  writing to one, as in `sox song.wav -t wav - | …`, added a second copy of
  the file header to the end of the audio.

### Added

- On Windows, the formats SoX reads and writes through libsndfile — `caf`,
  `w64`, `paf`, `pvf`, `mat4`, `mat5` and `fap`. The released Windows binary
  has none of them; Linux and macOS already had them.

- On Linux, `rec` records from PulseAudio or PipeWire directly.

### Removed

- The `ladspa` effect and the `--magic` option on Linux. Neither could work in
  this binary — LADSPA plugins are shared libraries it can't load, and
  `--magic` had no libmagic database to read — and the macOS and Windows
  binaries never had them.
