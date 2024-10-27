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

                # Template content as a string
                flakeContent = builtins.readFile ./flake.nix;

                # Script to install the flake template
                installScript = pkgs.writeScriptBin "install-template" ''
          #!${pkgs.bash}/bin/bash
          if [ -f flake.nix ]; then
            echo "flake.nix already exists in current directory. Aborting."
            exit 1
          fi

          echo "Installing Python flake template..."
          # Create a new writable file with the content
          cat > flake.nix << 'EOF'
                    ${flakeContent}
EOF

          # Create .gitignore if it doesn't exist
          if [ ! -f .gitignore ]; then
            echo "Creating .gitignore..."
            cat > .gitignore << 'EOF'
.venv/
result
EOF
          fi

          echo "Template installed successfully!"
          echo "You can now use 'nix develop' in this directory."
                '';
            in
                {
                devShells.default = pkgs.mkShell {
                    packages = with pkgs; [
                        pythonPackages.matplotlib
                        pythonPackages.numpy
                        pythonPackages.pandas

                        pythonPackages.venvShellHook
                        pythonPackages.ipykernel

                        pkgs.uv # pip alternative
                        # use `uv pip install` to get pythonPackages

                        installScript
                    ];

                    buildInputs = with pkgs; [
                        bashInteractive
                        openssl
                        git
                        rsync
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

              # Only run uv pip install if requirements.txt exists
              if [ -f requirements.txt ]; then
              uv pip install -r requirements.txt
              else
              echo "No requirements.txt found. Skipping package installation."
              fi

              echo "Type 'install-template' to install this flake template in the current directory"
              '';

                    postShellHook = ''
              ln -sf ${python.sitePackages}/* ./.venv/lib/python3.12/site-packages
              '';
                };

                # Expose the template installation as a package
                packages.default = installScript;
            }
        );
}

