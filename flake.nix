{
  description = "Nix development shell for open-receipt";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          f (import nixpkgs { inherit system; })
        );
    in
    {
      devShells = forAllSystems (pkgs:
        let
          hostTool = name:
            pkgs.writeShellScriptBin name ''
              exec /usr/bin/${name} "$@"
            '';

          xcrunTool = name:
            pkgs.writeShellScriptBin name ''
              exec /usr/bin/xcrun ${name} "$@"
            '';
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.git
              pkgs.gnumake
              pkgs.ripgrep
              (hostTool "open")
              (hostTool "xcodebuild")
              (hostTool "xcrun")
              (xcrunTool "swift")
              (xcrunTool "swift-format")
              pkgs.xcbeautify
              pkgs.xcodegen
            ];

            shellHook = ''
              if [ "$(uname -s)" != "Darwin" ]; then
                echo "error: this dev shell only supports macOS." >&2
                return 1
              fi

              missing_tools=0

              macos_major=$(/usr/bin/sw_vers -productVersion | awk -F. '{ print int($1) }')

              if [ "$macos_major" -lt 27 ]; then
                echo "error: macOS 27+ is required; found macOS $macos_major." >&2
                missing_tools=1
              fi

              if [ ! -x /usr/bin/open ]; then
                echo "error: /usr/bin/open is required by the Makefile." >&2
                missing_tools=1
              fi

              if [ ! -x /usr/bin/xcodebuild ]; then
                echo "error: /usr/bin/xcodebuild is required by the Makefile." >&2
                missing_tools=1
              fi

              if [ ! -x /usr/bin/xcrun ]; then
                echo "error: /usr/bin/xcrun is required by the Makefile." >&2
                missing_tools=1
              fi

              if [ "$missing_tools" -eq 0 ]; then
                xcode_major=$(/usr/bin/xcodebuild -version | awk 'NR == 1 { print int($2) }')

                if [ "$xcode_major" -lt 27 ]; then
                  echo "error: Xcode 27+ is required; found Xcode $xcode_major." >&2
                  missing_tools=1
                fi

                if ! /usr/bin/xcrun --find swift >/dev/null 2>&1; then
                  echo "error: swift from the active Xcode toolchain is not available." >&2
                  missing_tools=1
                fi

                if ! /usr/bin/xcrun --find swift-format >/dev/null 2>&1; then
                  echo "error: swift-format from the active Xcode toolchain is not available." >&2
                  missing_tools=1
                fi

                if ! /usr/bin/xcrun --find simctl >/dev/null 2>&1; then
                  echo "error: simctl is not available from the active Xcode install." >&2
                  missing_tools=1
                fi

                if ! /usr/bin/xcrun --find devicectl >/dev/null 2>&1; then
                  echo "error: devicectl is not available from the active Xcode install." >&2
                  missing_tools=1
                fi
              fi

              if [ "$missing_tools" -ne 0 ]; then
                echo "Install macOS 27+ and select a full Xcode 27+ install with xcode-select." >&2
                return 1
              fi

              # xcrun always finds the metal stub, so run it to confirm the toolchain component exists.
              if ! /usr/bin/xcrun metal --version >/dev/null 2>&1; then
                echo "Installing the Metal Toolchain, which the app's shaders need..." >&2
                if ! /usr/bin/xcodebuild -downloadComponent MetalToolchain \
                  || ! /usr/bin/xcrun metal --version >/dev/null 2>&1; then
                  echo "error: the Metal Toolchain could not be installed." >&2
                  echo "Install it with: xcodebuild -downloadComponent MetalToolchain" >&2
                  return 1
                fi
              fi
            '';
          };
        });
    };
}
