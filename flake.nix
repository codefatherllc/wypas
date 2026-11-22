{
  description = "wypas development environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
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

          goPackages = with pkgs; [
            go_1_26
            gnumake
            pkg-config
          ];

          goCgoPackages = goPackages ++ (with pkgs; [
            gcc
            cmake
            curl
          ]);

          cppPackages = with pkgs; [
            cmake
            gcc
            ninja
            pkg-config
            curl
            zip
            unzip
            gnutar
            git
          ];

          vcpkgShellHook = ''
            export VCPKG_ROOT="$HOME/.vcpkg"
            if [ ! -f "$VCPKG_ROOT/vcpkg" ]; then
              echo "Bootstrapping vcpkg..."
              git clone --filter=blob:none https://github.com/microsoft/vcpkg.git "$VCPKG_ROOT"
              "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics
            fi
            export PATH="$VCPKG_ROOT:$PATH"
          '';

          rustPackages = with pkgs; [
            rustc
            cargo
            cmake
            gcc
            pkg-config
            vulkan-loader
            vulkan-headers
          ];

          nodePackages = with pkgs; [
            nodejs_22
          ];

          proxyPackages = with pkgs; [
            gnumake
            gh
            openssl
            git
            nodejs_22
            docker-compose
            mariadb.client
            procps
          ];
        in
        {
          go = pkgs.mkShell {
            packages = goPackages;
          };

          go-cgo = pkgs.mkShell {
            packages = goCgoPackages;
          };

          cpp = pkgs.mkShell {
            packages = cppPackages;
            shellHook = vcpkgShellHook;
          };

          rust = pkgs.mkShell {
            packages = rustPackages;
          };

          node = pkgs.mkShell {
            packages = nodePackages;
          };

          proxy = pkgs.mkShell {
            packages = proxyPackages;
          };

          default = pkgs.mkShell {
            packages = goPackages
              ++ goCgoPackages
              ++ cppPackages
              ++ rustPackages
              ++ nodePackages
              ++ proxyPackages;
            shellHook = vcpkgShellHook;
          };
        });
    };
}
