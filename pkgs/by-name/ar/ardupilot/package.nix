{
  lib,
  stdenv,
  buildPackages,
  fetchFromGitHub,
  git,
  pkg-config,
  python3,
  runCommand,

  board ? "sitl",
  vehicles ? [
    "copter"
    "plane"
    "rover"
    "sub"
  ],
}:

let
  # We don't need ChibiOS and friends, reduce submodule total size to 500MB over 1GB
  submodules = {
    "modules/waf" = fetchFromGitHub {
      owner = "ArduPilot";
      repo = "waf";
      rev = "35eadbb64e2052099a853b571e507c33032b392c";
      hash = "sha256-1B2WY/oDNcdWTS60ecG6940LfKlahNRSTEcgmLp2GZw=";
    };
    "modules/mavlink" = fetchFromGitHub {
      owner = "ArduPilot";
      repo = "mavlink";
      rev = "288b907c384a892c8519bfe271682424b1e1a3a0";
      fetchSubmodules = true; # pymavlink, used to generate the headers
      hash = "sha256-569h8m+PS6p3ga+g88yc7b2OY1P8z2qUXLb0UuxzFn0=";
    };
    "modules/DroneCAN/DSDL" = fetchFromGitHub {
      owner = "DroneCAN";
      repo = "DSDL";
      rev = "04e0e818b06c180eb1720fcdf16484d0f12895ee";
      hash = "sha256-FIlFKB8c8ou0LKMGxMyPQTGoG/8OparPyuYqAuyQfJI=";
    };
    "modules/DroneCAN/dronecan_dsdlc" = fetchFromGitHub {
      owner = "DroneCAN";
      repo = "dronecan_dsdlc";
      rev = "de47a8972b7d8c59e50c3acfab5754db29798caa";
      hash = "sha256-WkS8qXozeV8L5PGFY+Kqa6Ue0VGNepYJBKtletYSc6E=";
    };
    "modules/DroneCAN/libcanard" = fetchFromGitHub {
      owner = "DroneCAN";
      repo = "libcanard";
      rev = "601ed35467e0ac38819df17cd7c918de19f62d58";
      hash = "sha256-FaucEHVK609FuN9ssPtuAn+m+7X9R9ji4iHxd9HaG2o=";
    };
    "modules/littlefs" = fetchFromGitHub {
      owner = "ArduPilot";
      repo = "littlefs";
      rev = "34be692aafaaf4319a18e415b08aa4332697408b";
      hash = "sha256-1Zug+kxBDjeduFIFCl7QQOnHcP//HRvPkYN84M13mXY=";
    };
    "modules/lwip" = fetchFromGitHub {
      owner = "ArduPilot";
      repo = "lwip";
      rev = "a6bf350c679ed8ba042ad58bf81cc540d61bb605";
      hash = "sha256-OyYIkvVtZTD7Xx5zRxQhUtyGpTL11fq3oVkCL7OY2hI=";
    };
  };

  binaryName = {
    copter = "arducopter";
    heli = "arducopter-heli";
    plane = "arduplane";
    rover = "ardurover";
    sub = "ardusub";
    blimp = "blimp";
    antennatracker = "antennatracker";
  };

  toolchain =
    if stdenv.buildPlatform == stdenv.hostPlatform then
      "native"
    else
      lib.removeSuffix "-" stdenv.cc.targetPrefix;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "ardupilot";
  version = "4.7.3";

  src = fetchFromGitHub {
    owner = "ArduPilot";
    repo = "ardupilot";
    tag = "Copter-${finalAttrs.version}";
    hash = "sha256-Z3H0bb1Sipct6K53EcberhuwvEZneZlANgMOJJ6Plkg=";
  };

  # Commit of the tag, reported by the firmware as its git hash.
  gitSha = "d9c5097c3d8333435712ffed86bca8ce00c4bb46";

  postUnpack = lib.concatStrings (
    lib.mapAttrsToList (path: src: ''
      cp -r --no-preserve=mode ${src}/. "$sourceRoot/${path}"
    '') submodules
  );

  # gen-bindings generates the Lua bindings during the build, so it has to
  # be built for the build machine. It is also built with -Werror, which
  # newer compilers trip on.
  #
  # waf asks git for HEAD to embed it in the firmware, but the source has
  # no .git, so answer with the tag commit instead.
  postPatch = ''
    substituteInPlace libraries/AP_Scripting/wscript \
      --replace-fail 'BINDING_CC="gcc"' 'BINDING_CC="${buildPackages.stdenv.cc.targetPrefix}cc"' \
      --replace-fail ' -Werror -Wextra' ' -Wextra'

    cat >> Tools/ardupilotwaf/git_submodule.py <<EOF

    def _git_head_hash(ctx, path, short=False, hash_abbrev=8):
        sha = "${finalAttrs.gitSha}"
        return sha[:hash_abbrev] if short else sha
    EOF
  '';

  strictDeps = true;
  __structuredAttrs = true;
  enableParallelBuilding = true;

  depsBuildBuild = [ buildPackages.stdenv.cc ];

  nativeBuildInputs = [
    git # waf's configure looks for it even though the hash is patched
    pkg-config
    (python3.pythonOnBuildForHost.withPackages (
      ps: with ps; [
        dronecan
        empy
        pexpect
      ]
    ))
  ];

  configurePhase = ''
    runHook preConfigure

    python3 ./waf configure \
      --board ${board} \
      --toolchain ${toolchain} \
      --no-submodule-update \
      --disable-tests

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    python3 ./waf ${lib.escapeShellArgs vehicles} -j $NIX_BUILD_CORES

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 build/${board}/bin/* -t $out/bin

    runHook postInstall
  '';

  passthru.tests = lib.optionalAttrs (stdenv.buildPlatform.canExecute stdenv.hostPlatform) {
    help = runCommand "ardupilot-help" { } ''
      for bin in ${finalAttrs.finalPackage}/bin/*; do
        "$bin" --help | grep -- --help
      done
      touch $out
    '';
  };

  meta = {
    description = "Autopilot firmware for multicopters, planes, rovers, boats and submarines";
    homepage = "https://ardupilot.org";
    changelog = "https://github.com/ArduPilot/ardupilot/blob/${finalAttrs.src.tag}/ArduCopter/ReleaseNotes.txt";
    license = lib.licenses.gpl3Plus;
    maintainers = with lib.maintainers; [ patrickelectric ];
    platforms =
      if board == "sitl" then lib.platforms.linux ++ lib.platforms.darwin else lib.platforms.linux;
    mainProgram = binaryName.${lib.head vehicles};
  };
})
