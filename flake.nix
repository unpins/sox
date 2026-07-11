{
  description = "SoX (Sound eXchange), the audio Swiss-army knife (sox / play / rec / soxi), as a single self-contained binary";

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

      # sox is C; build it under the unpin-llvm engine (clang/lld, static musl,
      # single binary). Its codec/audio deps stay ordinary pkgsStatic `.a`s,
      # linked as external native archives by the engine link.
      #
      # LTO is OFF: clang-21's whole-program LTO miscompiles libsox.c's version
      # lazy-init — `static info = { …, /*version*/ NULL, … }; if (!info.version)
      # info.version = sox_version();` — constant-propagating the initial NULL and
      # dropping the runtime write, so `sox --version` prints "SoX v(null)"
      # (verified: lto=false → "SoX v14.4.2"). That is only the visible symptom of
      # an LTO codegen bug (same class as the darwin ffmpeg teardown miscompile,
      # llvm/llvm-project#186922 / ziglang/zig#20198); other sox TUs could be
      # silently miscompiled too, so drop LTO for the whole package rather than
      # trust it here. sox is still a single static binary — LTO is an
      # optimization, not required for the fold. Marginal size/speed cost, none to
      # correctness.
      engStdenv = pkgs:
        let sp = pkgs.pkgsStatic; in
        ulib.unpinAdapterStdenv {
          inherit pkgs;
          target = sp.stdenv.hostPlatform.config;
          native = pkgs.stdenv.buildPlatform.system == pkgs.stdenv.hostPlatform.system;
          cxx = false;
          lto = false;
          captureLinks = true;
        };
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "sox";
      smoke = [ "--version" ];
      # Match the real version, not a bare "SoX v" — the latter also matches the
      # "SoX v(null)" an LTO-miscompiled build prints (see engStdenv), so it would
      # silently pass a broken binary.
      smokePattern = "SoX v14\\.4";
      engine = "unpin-llvm";

      # sox bakes a handful of plugin/data-dir path strings into the binary —
      # libmagic's magic DB, pulseaudio's server/locale dirs, libao's and
      # alsa-lib's dynamic-plugin dirs, and sox's own libsox plugin/LADSPA dirs.
      # All are inert here: the binary is fully static (no dlopen — audio.nix
      # compiles libao's drivers in, format handlers are built-in), and those
      # /nix/store paths don't exist on a user's machine anyway. Scrub them so the
      # shipped binary is 0-ref and portable.
      removeReferences = [
        "file-static"
        "libpulseaudio"
        "libao"
        "alsa-lib"
        "unstable-2021-05-09-lib"
      ];

      # Native (Linux + Darwin). Playback via the ./audio.nix built-in-driver libao.
      build = pkgs:
        let
          # libopus needs the arm64 meson-intrinsics fix on native aarch64-darwin
          # (nixpkgs writes meson cpu_family = "arm64"; opus' meson.build only
          # matches arm/aarch64 → "no intrinsics support for arm64"). SoX pulls
          # libopus transitively via opusfile AND libsndfile, so patch it once in
          # the package set. Inert on every other platform (just widens a match
          # list). Same nativeFixes.libopus opus-tools uses.
          ps = pkgs.pkgsStatic.extend (final: prev: {
            libopus = ulib.nativeFixes.libopus prev;
            # libX11 (pulled on Linux via libao's playback chain
            # libpulseaudio → dbus → libX11) has a configure probe that checks
            # whether its cpp needs -undef to stop predefining `unix`. The
            # engine's clang cpp keeps `unix` defined even under -undef, so the
            # probe aborts ("defines unix with or without -undef. I don't know
            # what to do."). RAWCPP only preprocesses X11's host-independent
            # locale/compose text at build time, so hand it the build-host gcc
            # cpp (which honors -undef); libX11 links in as a plain static .a
            # regardless of which cpp cooked its data. Inert on darwin/windows
            # (no X11 in the CoreAudio/WMM playback paths). Same fix ddcutil uses.
            libx11 = prev.libx11.overrideAttrs (_: {
              RAWCPP = "${final.buildPackages.stdenv.cc}/bin/cpp";
            });
            # libmpg123 (pulled by libsndfile for MP3 decode) builds its mpg123/
            # out123 CLI programs even under nixpkgs' libOnly (that only drops the
            # audio backends). Those programs fail the engine's whole-program LTO
            # link (ld.lld: undefined symbol `fputs`), and we don't ship them —
            # libsndfile needs only libmpg123.a. Select just that component
            # (--disable-components --enable-libmpg123): no programs, no
            # libout123/libsyn123, so the offending link never happens and the
            # decode library is unchanged.
            # fftw (single, pulled via libpulseaudio's equalizer module) forces
            # --enable-openmp and links llvmPackages.openmp, but the engine's
            # self-contained clang has no OpenMP runtime → configure aborts
            # ("don't know how to enable OpenMP"). The OpenMP variant
            # (libfftw3f_omp) is unused — pulseaudio links the serial libfftw3f —
            # so drop OpenMP and keep pthreads threading (--enable-threads).
            fftwFloat = prev.fftwFloat.overrideAttrs (o: {
              configureFlags = final.lib.filter (f: f != "--enable-openmp")
                (o.configureFlags or [ ]);
              buildInputs = final.lib.filter (d: (d.pname or "") != "openmp")
                (o.buildInputs or [ ]);
            });
            # lame's `#ifdef HAVE_XMMINTRIN_H` SSE paths (libmp3lame/{vector/
            # xmm_quantize_sub,fft,quantize,lame}.c use `__m128`) don't compile on
            # the i686 target's -march=i686 baseline (no SSE). configure defines
            # HAVE_XMMINTRIN_H anyway: its probe compiles `_mm_sfence()` with
            # clang's *default* i686 flags (SSE2-capable) BEFORE lame appends
            # -march=i686 to CFLAGS, so it passes where the real -march=i686
            # compile fails (gcc doesn't false-positive here). The i686 target
            # deliberately assumes no SSE, so undefine the macro post-configure —
            # every SSE block then compiles as its scalar fallback (the code ARM/
            # PPC already use; MP3 encode unchanged). Gated to i686; x86_64 (SSE2
            # baseline) keeps the vectorized paths and its hash.
            lame = if final.stdenv.hostPlatform.isx86_32
              then prev.lame.overrideAttrs (o: {
                postConfigure = (o.postConfigure or "") + ''
                  sed -i '/#define HAVE_XMMINTRIN_H 1/d' config.h
                '';
              })
              else prev.lame;
            # libvorbis' 32-bit-x86 CFLAGS case hardcodes `-mno-ieee-fp`, a
            # GCC-only flag the engine clang rejects as a fatal unknown argument
            # (x86_64 takes a different case, so it's unaffected). The flag only
            # relaxes IEEE FP strictness for -ffast-math (already on); drop it so
            # the i686 build compiles. Gated to i686 to keep other hashes.
            libvorbis = if final.stdenv.hostPlatform.isx86_32
              then prev.libvorbis.overrideAttrs (o: {
                postPatch = (o.postPatch or "") + ''
                  substituteInPlace configure --replace-fail ' -mno-ieee-fp' ""
                '';
              })
              else prev.libvorbis;
            # libmad's configure.ac appends a fistful of GCC-tuning flags
            # (-fcse-follow-jumps/-fregmove/…) in its `$GCC = yes` branch — which
            # the engine clang also takes (it sets __GNUC__), but clang rejects
            # those flags as fatal "unknown argument". nixpkgs already strips
            # -fforce-mem and re-runs autoconf; strip the remaining clang-hostile
            # ones the same way (they're gcc micro-tuning; clang's -O2 covers it,
            # decode output unchanged).
            libmad = prev.libmad.overrideAttrs (o: {
              postPatch = (o.postPatch or "") + ''
                sed -i -E 's/-f(force-addr|thread-jumps|cse-follow-jumps|cse-skip-blocks|expensive-optimizations|regmove|schedule-insns2)//g' configure.ac
              '';
            });
            libmpg123 = prev.libmpg123.overrideAttrs (o: {
              configureFlags = (o.configureFlags or [ ])
                ++ [ "--disable-components" "--enable-libmpg123" ];
              # With only the library built there are no man pages, so the
              # recipe's declared `man` output would be empty and nix errors
              # ("failed to produce output path"). Materialize it.
              postInstall = (o.postInstall or "") + ''
                mkdir -p "$man"
              '';
            });
          });
          audioLibao = import ./audio.nix { lib = pkgs.lib // ulib; } ps;

          sox = (ps.sox.override {
            stdenv = engStdenv pkgs;
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
          } // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
            # pkgsStatic on darwin can't suppress libtool's shared build (no
            # static libSystem), so libsox builds as a .dylib and the sox
            # frontend links it dynamically → fails the portability check. Force
            # libtool to emit only the static archive so libsox folds into the
            # binary (libSystem + system frameworks stay the only dynamic deps).
            # Same fix lame/xz use. Gated on darwin so Linux/cross keep their hash.
            postConfigure = (o.postConfigure or "") + ''
              sed -i 's/^build_libtool_libs=yes$/build_libtool_libs=no/' libtool
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
          metaAllow = d: d.overrideAttrs (o: {
            meta = (o.meta or { }) // { platforms = pkgs.lib.platforms.all; broken = false; };
          });
          # libtool swallows the stdenv's -static for the program link, so the
          # gcc stack-protector runtime leaks in as a libssp-0.dll import.
          # mingwStaticBinary adds libtool-aware LDFLAGS=-all-static at make-time
          # so the final link resolves libssp.a (and every codec dep) statically
          # → only system DLLs (KERNEL32/msvcrt/WINMM) remain.
          sox = ulib.mingwStaticBinary {
            pkg = (ulib.mingwStaticCross pkgs).sox;
            staticDeps = {
              enableLibao = false;
              enableLame = true;
            };
            extraOverrides = old: {
              meta = (old.meta or { }) // { platforms = pkgs.lib.platforms.all; broken = false; };
              buildInputs = builtins.map metaAllow (old.buildInputs or [ ]);
            };
          };
        in
        ulib.withAliases pkgs
          {
            primary = "sox";
            aliasesFromSymlinksIn = "bin";
          }
          sox;
    };
}
