{
  description = "Python development environment with basic scientific packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        python = pkgs.python312;
        pythonPackages = python.pkgs;
        lib-path = with pkgs; pkgs.lib.makeLibraryPath [
          libffi
          openssl
          stdenv.cc.cc
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            pythonPackages.matplotlib
            pythonPackages.numpy
            pythonPackages.pandas
            
            pythonPackages.venvShellHook
            pythonPackages.ipykernel
            pythonPackages.jupyterlab
          ];

          buildInputs = with pkgs; [
            bashInteractive
            readline
            libffi
            openssl
            git
            openssh
            rsync
            pkg-config
            zlib
            uv
          ];

          shellHook = ''
            SOURCE_DATE_EPOCH=$(date +%s)
            export "LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${lib-path}"
            VENV=.venv

            if test ! -d $VENV; then
              python3.12 -m venv $VENV
            fi

            source ./$VENV/bin/activate
            uv pip install -r requirements.txt
          '';

          postShellHook = ''
            ln -sf ${python.sitePackages}/* ./.venv/lib/python3.12/site-packages
          '';
        };
      }
    );
}
