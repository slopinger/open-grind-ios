{
  lib,
  stdenv,
  rustPlatform,
  cmake,
  git,
  perl,
  llvmPackages,
}:

# The Rust bridge (`core/`) for the host platform: the static and shared
# library, the `uniffi-bindgen` CLI, and the Swift bindings generated from the
# library. iOS builds of the library come from scripts/build-core-xcframework.sh,
# which needs Xcode.
rustPlatform.buildRustPackage {
  pname = "opengrind-core";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../core;
    fileset = lib.fileset.unions [
      ../core/Cargo.toml
      ../core/Cargo.lock
      ../core/src
    ];
  };

  cargoLock.lockFile = ../core/Cargo.lock;

  nativeBuildInputs = [
    cmake
    # boring-sys2 applies its BoringSSL patches with `git apply`.
    git
    perl
    llvmPackages.clang
  ];

  # cmake is only for boring-sys2's build script, not for this package.
  dontUseCmakeConfigure = true;
  LIBCLANG_PATH = "${lib.getLib llvmPackages.libclang}/lib";

  postInstall = ''
    ext=${if stdenv.hostPlatform.isDarwin then "dylib" else "so"}
    lib="$(find target -name "libopengrind_core.$ext" -path '*/release/*' | head -n1)"
    install -Dm644 "$lib" "$out/lib/libopengrind_core.$ext"
    install -Dm644 "$(dirname "$lib")/libopengrind_core.a" "$out/lib/libopengrind_core.a"
    "$out/bin/uniffi-bindgen" generate --library "$lib" --language swift --out-dir "$out/share/swift"
  '';

  meta = {
    description = "UniFFI bridge between the Open Grind iOS app and the grindr transport";
    homepage = "https://github.com/slopinger/open-grind-ios";
    license = lib.licenses.mit;
    mainProgram = "uniffi-bindgen";
  };
}
