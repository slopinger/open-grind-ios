{
  lib,
  swiftPackages,
  core,
}:

let
  inherit (swiftPackages) stdenv swift swiftpm;
in
stdenv.mkDerivation {
  pname = "opengrindkit";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../OpenGrindKit;
    fileset = lib.fileset.unions [
      ../OpenGrindKit/Package.swift
      ../OpenGrindKit/Sources
      ../OpenGrindKit/Tests
    ];
  };

  nativeBuildInputs = [
    swift
    swiftpm
  ];

  # On Linux the package links the bridge as a system library from here (see
  # Package.swift); on Darwin it expects the XCFramework, which needs Xcode, so
  # only the pure Swift targets are built there.
  env = lib.optionalAttrs stdenv.hostPlatform.isLinux {
    OPENGRIND_CORE_LIB_DIR = "${core}/lib";
    # Swift Testing's backtraces for thrown errors crash on Linux when a
    # cancelled Task.sleep throws.
    SWT_SWIFT_ERROR_BACKTRACING_ENABLED = "0";
  };

  # Runs `swift test` (swiftpm setup hook). On Darwin, nixpkgs' SwiftPM refuses to
  # run tests without Xcode, so the suite only runs on Linux; on a Mac run
  # `swift test` in OpenGrindKit/ with Xcode's toolchain instead.
  doCheck = !stdenv.hostPlatform.isDarwin;

  postInstall = ''
    # The hook installs libOpenGrindKitShared; add the module interface it is
    # built from (a file on Linux, a directory on Darwin, hence cp -r).
    modules="$(swiftpmBinPath)/Modules"
    dest="$out/lib/swift/${stdenv.hostPlatform.swift.platform}"
    mkdir -p "$dest"
    cp -r "$modules/OpenGrindKit.swiftmodule" "$dest/"
  '';

  meta = {
    description = "Models, API client and state for Open Grind on iOS";
    homepage = "https://github.com/slopinger/open-grind-ios";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
