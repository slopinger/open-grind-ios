{
  description = "Open Grind for iOS: native SwiftUI port of the Open Grind Grindr client";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        core = pkgs.callPackage ./nix/core.nix { };
        opengrindkit = pkgs.callPackage ./nix/opengrindkit.nix { inherit core; };
        default = opengrindkit;
      });

      checks = forAllSystems (
        pkgs:
        let
          inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) core opengrindkit;
        in
        {
          # cargo test of the bridge runs in the core build.
          inherit core;

          # The Swift package's tests, plus a smoke test of the generated bindings
          # against the real Rust library (Linux only, see nix/opengrindkit.nix).
          inherit opengrindkit;

          # The committed bindings must match what the bridge generates.
          bindings = pkgs.runCommand "open-grind-ios-bindings-check" { } ''
            diff -u ${core}/share/swift/opengrind_core.swift \
              ${./OpenGrindKit/Sources/OpenGrindCore/opengrind_core.swift}
            diff -u ${core}/share/swift/opengrind_coreFFI.h \
              ${./OpenGrindKit/Sources/opengrind_coreFFI/include/opengrind_coreFFI.h}
            touch $out
          '';

          # The iOS app needs the iOS SDK (see .github/workflows/ios.yml). Here we
          # parse every app source and lint the whole Swift tree.
          app = pkgs.swiftPackages.stdenv.mkDerivation {
            name = "open-grind-ios-app-check";
            src = ./.;
            nativeBuildInputs = [
              pkgs.swiftPackages.swift
              pkgs.swift-format
            ];
            dontConfigure = true;
            buildPhase = ''
              find OpenGrind OpenGrindTests OpenGrindUITests -name '*.swift' -print0 | xargs -0 swiftc -parse
              swift-format lint --strict --recursive OpenGrind OpenGrindTests OpenGrindUITests \
                OpenGrindKit/Package.swift OpenGrindKit/Sources/OpenGrindKit \
                OpenGrindKit/Sources/OpenGrindCoreTransport OpenGrindKit/Tests
            '';
            installPhase = "touch $out";
          };
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell.override { inherit (pkgs.swiftPackages) stdenv; } {
          packages = [
            pkgs.swiftPackages.swift
            pkgs.swiftPackages.swiftpm
            pkgs.swift-format
            pkgs.cargo
            pkgs.rustc
            pkgs.clippy
            pkgs.rustfmt
            pkgs.cmake
            pkgs.git
            pkgs.perl
            pkgs.llvmPackages.clang
          ];
          LIBCLANG_PATH = "${pkgs.lib.getLib pkgs.llvmPackages.libclang}/lib";
          # Swift Testing captures a backtrace for every thrown error; on Linux that
          # crashes when a cancelled Task.sleep throws on the runtime's timer thread.
          SWT_SWIFT_ERROR_BACKTRACING_ENABLED = "0";
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
