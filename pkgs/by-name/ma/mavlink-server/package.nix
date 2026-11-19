{
  lib,
  rustPlatform,
  fetchFromGitHub,
  git,
  trunk,
  wasm-bindgen-cli_0_2_100,
  binaryen,
  llvmPackages,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "mavlink-server";
  version = "0.11.1";
  # commit of the version tag, reported by the server since the source has no .git
  gitSha = "a2f357746840fab7182695f7faa8211503e06083";

  src = fetchFromGitHub {
    owner = "bluerobotics";
    repo = "mavlink-server";
    tag = finalAttrs.version;
    # ArduPilot parameter metadata is a submodule embedded in the binary
    fetchSubmodules = true;
    hash = "sha256-QrmRaOjVWiwFh42uQtx430oH5SIzBJsZtPYrYbRWR+A=";
  };

  cargoHash = "sha256-McT0ATnLHRXAwVUVG6MwzV6K1pOqfkijjmcAHa73G/0=";

  strictDeps = true;
  __structuredAttrs = true;

  # the mavlink crate build script fails if git is missing
  nativeBuildInputs = [ git ];

  env = {
    # build.rs would install a rustup target and trunk, the frontend is built in passthru.frontend
    SKIP_FRONTEND = "1";
    # vergen cannot read git metadata from the source tarball
    VERGEN_GIT_DESCRIBE = finalAttrs.version;
    VERGEN_GIT_SHA = finalAttrs.gitSha;
  };

  # include_dir (git dependency) includes the README.md at its workspace root,
  # which is not part of the vendored crate
  postPatch = ''
    for crate in "$cargoDepsCopy"/source-git-*/include_dir-*; do
      touch "$crate/../README.md"
    done
  '';

  preBuild = ''
    cp -r --no-preserve=mode ${finalAttrs.passthru.frontend} src/webpage/dist
  '';

  # the release profile uses fat LTO with one codegen unit, building tests like that runs out of memory
  checkType = "debug";
  # tests share global state and need one process each, like upstream CI does
  useNextest = true;

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgramArg = "--version";

  passthru.frontend = rustPlatform.buildRustPackage {
    pname = "mavlink-server-frontend";
    inherit (finalAttrs) version src;

    sourceRoot = "${finalAttrs.src.name}/src/webpage";

    cargoHash = "sha256-OBPpW8AxtpJ7/H9mA6yXQk+aUS9KhFntsi8BD2vtJVs=";

    strictDeps = true;
    __structuredAttrs = true;

    nativeBuildInputs = [
      trunk
      # must match the wasm-bindgen version in src/webpage/Cargo.lock
      wasm-bindgen-cli_0_2_100
      binaryen
      llvmPackages.bintools-unwrapped
    ];

    buildPhase = ''
      runHook preBuild
      trunk build --offline --locked --release
      runHook postBuild
    '';

    # The server embeds gzipped assets, like build.rs does upstream
    installPhase = ''
      runHook preInstall
      cp -r dist $out
      find $out -type f ! -name '*.gz' -exec gzip -n {} +
      runHook postInstall
    '';

    doCheck = false;
  };

  meta = {
    description = "MAVLink router and broker with a REST API and web interface";
    homepage = "https://github.com/bluerobotics/mavlink-server";
    changelog = "https://github.com/bluerobotics/mavlink-server/releases/tag/${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "mavlink-server";
    platforms = lib.platforms.unix;
    maintainers = with lib.maintainers; [ patrickelectric ];
  };
})
