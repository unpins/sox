{
  description = "Standalone build of SoX (Sound eXchange) — the audio Swiss-army knife (sox / play / rec / soxi)";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # SoX installs ONE real binary, `sox`, plus three argv[0] symlinks the upstream
  # install-exec-hook creates — `play`, `rec`, `soxi` — all dispatched on
  # basename(argv[0]) inside sox.c. So there's no multicall surgery: the canonical
  # binary is already named after the package, and `lib.withAliases` just harvests
  # the three symlinks into an UNPIN_META block so unpin recreates them at install.
  #
  # Live audio in a fully-static binary is the hard part. SoX's OWN device backends
  # (alsa.c / pulseaudio.c) can't carry it: the static ALSA backend dies on a modern
  # PulseAudio/PipeWire desktop because libasound dlopen's its routing module
  # (libasound_module_pcm_pipewire.so) — impossible under static musl — so the
  # `default` pcm has no device; and SoX's pulseaudio backend uses AC_CHECK_LIB with
  # a bare `-lpulse` link test that can't satisfy the static libpulse dep chain.
  #
  # So we route SoX's playback through libao instead, reusing the exact built-in
  # static-driver libao proven for unpins/vorbis-tools (./audio.nix: pulse + alsa +
  # oss compiled INTO libao.a as static_drivers[], pulse(50)>alsa(35)>oss(20) on
  # Linux, macosx on Darwin — recipes reference-libao-static-builtin-drivers +
  # reference-static-libpulse-client-recipe). libao's own test()/ao_default_driver_id
  # probing connects to the pulse/pipewire socket when present and falls to ALSA
  # hw/dmix on bare metal — no dlopen, no daemon lib on disk.
  #
  # Two wires make SoX use it:
  #   - preConfigure exports LIBAO_LIBS from `pkg-config --static --libs ao` so SoX's
  #     `AC_CHECK_LIB(ao, ao_play, …, other-libs=$LIBAO_LIBS)` link test (and the
  #     final link) see libao's full static chain (libpulse-simple/alsa). A bare
  #     `-lao` test would fail-link → libao silently dropped.
  #   - a one-liner moves try_device("ao") to the front of set_default_device(), so
  #     `sox -d` / play / rec pick libao (and its probing) instead of SoX's broken
  #     native alsa default. (Inert on Windows, where libao isn't compiled and the
  #     native waveaudio backend handles playback.)
  #
  # enableLame = true turns on MP3 *encode* (off by default in nixpkgs); MP3 decode
  # (libmad) is already on. The rest of the codec set — libsndfile, libvorbis,
  # opusfile, flac, wavpack, libpng (spectrogram) — links static from pkgsStatic.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "sox";
      smoke = [ "--version" ];
      smokePattern = "SoX v";

      # Native (Linux + Darwin). Playback via the ./audio.nix built-in-driver libao.
      build = pkgs:
        let
          ps = pkgs.pkgsStatic;
          audioLibao = import ./audio.nix { lib = pkgs.lib // ulib; } ps;

          sox = (ps.sox.override {
            enableLibao = true;
            libao = audioLibao;
            # Native alsa backend shares libao's pipewire-static libasound.a (one
            # copy, no vanilla alsa-lib whose `default` dlopen-fails). Sox's own
            # pulse backend is off: playback routes through libao → alsa.
            alsa-lib = audioLibao.alsaStatic;
            enableLibpulseaudio = false;
            enableLame = true;
          }).overrideAttrs (o: {
            meta = (o.meta or { }) // { platforms = pkgs.lib.platforms.all; broken = false; };
            # libao's static link chain (libao + pulse-simple/alsa or CoreAudio
            # frameworks) for SoX's AC_CHECK_LIB(ao) test and final link.
            preConfigure = (o.preConfigure or "") + ''
              export LIBAO_LIBS="$(''${PKG_CONFIG:-pkg-config} --static --libs ao)"
              echo "unpins: LIBAO_LIBS=$LIBAO_LIBS"
              [ -n "$LIBAO_LIBS" ] || { echo "unpins: pkg-config could not resolve ao.pc"; exit 1; }
            '';
            # Make libao the default PLAYBACK device (file_count>0 ⇒ not `rec`,
            # which libao can't do — recording falls through to the native
            # backends below). We set filetype="ao" directly instead of via
            # try_device(): try_device probes the handler with a ZEROED format
            # (rate=0), and libao's startwrite divides by the rate → SIGFPE. The
            # real open later uses the true format, and libao's own pulse(50)→
            # alsa(35)→oss(20) test()/priority selection picks the live server
            # (pulse/pipewire socket) or falls to ALSA hw/dmix on bare metal.
            postPatch = (o.postPatch or "") + ''
              substituteInPlace src/sox.c \
                --replace-fail \
                  'if (!f->filetype) f->filetype = getenv("AUDIODRIVER");' \
                  'if (!f->filetype) f->filetype = getenv("AUDIODRIVER");
                if (!f->filetype && file_count) f->filetype = "ao";'
            '';
          });
        in
        ulib.withAliases pkgs
          {
            primary = "sox";
            aliasesFromSymlinksIn = "bin";
          }
          sox;

      # Windows via mingw. No alsa/pulse/libao (Linux device APIs); SoX's waveaudio
      # (WMM) backend is compiled in by configure on mingw and needs no extra libs
      # beyond the Win32 system DLLs. The codec set crosses cleanly; meta-allow the
      # unix-guarded leaves. MP3 encode (lame) stays on.
      windowsBuild = pkgs:
        let
          cross = ulib.mingwStaticCross pkgs;
          metaAllow = d: d.overrideAttrs (o: {
            meta = (o.meta or { }) // { platforms = pkgs.lib.platforms.all; broken = false; };
          });
          sox = (cross.sox.override {
            enableLibao = false;
            enableLame = true;
          }).overrideAttrs (o: {
            meta = (o.meta or { }) // { platforms = pkgs.lib.platforms.all; broken = false; };
            buildInputs = builtins.map metaAllow (o.buildInputs or [ ]);
          });
        in
        ulib.withAliases pkgs
          {
            primary = "sox";
            aliasesFromSymlinksIn = "bin";
          }
          sox;
    };
}
