{
  description = "wypas development environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Keep Rust independently bumpable so refreshing the compiler does not
    # silently move the Go, C++, Node, database, or platform toolchains.
    nixpkgs-rust.url = "github:NixOS/nixpkgs/e5bdc4a41d4c072fe1e3787eaa0320a384741d44";
  };

  outputs = { self, nixpkgs, nixpkgs-rust }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          rustPkgs = nixpkgs-rust.legacyPackages.${system};

          # Keep cross-project command-line tooling on the same pinned nixpkgs
          # revision. Language-specific package managers still own application
          # dependencies (go.mod, Cargo.lock, package-lock.json, and so on).
          commonPackages = with pkgs; [
            bashInteractive
            coreutils
            curl
            findutils
            gawk
            git
            gnumake
            gnugrep
            gnused
            jq
            ripgrep
            unzip
            zip
          ];

          basePackages = commonPackages ++ [ pkgs.python3 ];

          goPackages = basePackages ++ (with pkgs; [
            go_1_26
            pkg-config
          ]);

          goCgoPackages = goPackages ++ (with pkgs; [
            gcc
            cmake
            curl
          ]);

          cppPackages = with pkgs; [
            boost
            cmake
            gcc14
            grpc
            rdkafka
            luajit
            ninja
            nlohmann_json
            openssl
            pkg-config
            protobuf
            pugixml
            zlib
            curl
            zip
            unzip
            gnutar
            git
            python3
            autoconf
            automake
            libtool
            libx11
            libxrandr
            libxinerama
            libxcursor
            libxi
            libxext
            libGL
            libGLU
            openal
            wayland
            wayland-protocols
            wayland-scanner
            libxkbcommon
          ];

          # vcpkg builds GLFW with both X11 and Wayland backends. GLFW loads
          # its Wayland dependencies with dlopen(), so the linker cannot infer
          # their Nix store paths and does not retain them in the executable's
          # RUNPATH. Expose those runtime libraries to every shell that can
          # build or launch the native client.
          cppRuntimeLibraryPath = pkgs.lib.makeLibraryPath (with pkgs; [
            wayland
            libxkbcommon
          ]);

          vcpkgShellHook = ''
            export VCPKG_ROOT="$HOME/.vcpkg"
            if [ ! -f "$VCPKG_ROOT/vcpkg" ]; then
              echo "Bootstrapping vcpkg..."
              git clone --filter=blob:none https://github.com/microsoft/vcpkg.git "$VCPKG_ROOT"
              "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics
            fi
            export PATH="$VCPKG_ROOT:$PATH"
          '';

          rustPackages = [
            rustPkgs.rustc
            rustPkgs.cargo
            rustPkgs.clippy
            rustPkgs.rustfmt
          ] ++ (with pkgs; [
            cmake
            gcc
            pkg-config
            vulkan-loader
            vulkan-headers
          ]);

          nodePackages = with pkgs; [
            nodejs_22
          ];

          contentPackages = basePackages ++ (with pkgs; [
            git-lfs
            imagemagick
            libxml2
            luajit
            rsync
            shellcheck
            xmlstarlet
          ]);

          # Match the CUDA image used for training; Python packages and GPU
          # libraries remain owned by the project's container/requirements.
          pythonMlPackages = commonPackages ++ (with pkgs; [
            cmake
            gcc
            pkg-config
            python311
            uv
          ]);

          platformPackages = basePackages ++ (with pkgs; [
            docker-client
            docker-compose
            gh
            mariadb.client
            nodejs_22
            openssl
            procps
            rsync
          ]);
        in
        {
          base = pkgs.mkShell {
            packages = basePackages;
          };

          go = pkgs.mkShell {
            packages = goPackages;
          };

          go-cgo = pkgs.mkShell {
            packages = goCgoPackages;
          };

          cpp = pkgs.mkShell {
            packages = cppPackages;
            LD_LIBRARY_PATH = cppRuntimeLibraryPath;
            shellHook = vcpkgShellHook;
          };

          cpp-wasm = pkgs.mkShell {
            packages = cppPackages ++ [ pkgs.emscripten ];
            LD_LIBRARY_PATH = cppRuntimeLibraryPath;
            shellHook = vcpkgShellHook + ''
              export EMSDK_SHIM="$PWD/.direnv/emsdk-shim"
              mkdir -p "$EMSDK_SHIM/upstream"
              ln -sfn "${pkgs.emscripten}/share/emscripten" "$EMSDK_SHIM/upstream/emscripten"
              export EMSDK="$EMSDK_SHIM"
            '';
          };

          rust = pkgs.mkShell {
            packages = rustPackages;
          };

          node = pkgs.mkShell {
            packages = nodePackages;
          };

          content = pkgs.mkShell {
            packages = contentPackages;
          };

          python-ml = pkgs.mkShell {
            packages = pythonMlPackages;
          };

          platform = pkgs.mkShell {
            packages = platformPackages;
          };

          # Compatibility alias for older checkouts. New infra work uses the
          # broader platform profile.
          proxy = pkgs.mkShell {
            packages = platformPackages;
          };

          default = pkgs.mkShell {
            packages = pkgs.lib.unique (basePackages
              ++ goPackages
              ++ goCgoPackages
              ++ cppPackages
              ++ rustPackages
              ++ nodePackages
              ++ contentPackages
              ++ pythonMlPackages
              ++ platformPackages);
            LD_LIBRARY_PATH = cppRuntimeLibraryPath;
            shellHook = vcpkgShellHook;
          };
        });
    };
}
