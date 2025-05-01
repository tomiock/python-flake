{
  description = "Python development environment with uv venv creation and automatic activation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        python = pkgs.python312; # Define the python interpreter
        pythonPackages = python.pkgs;
        lib-path = with pkgs; lib.makeLibraryPath [
          libffi
          openssl
          stdenv.cc.cc
        ];

        # Define a separate file for the flake template to avoid embedding issues
        flakeContentFile = pkgs.writeTextFile {
          name = "flake-template";
          text = builtins.readFile ./flake.nix;
        };

        # Script to install the flake template
        installScript = pkgs.writeScriptBin "install-template" ''
          #!${pkgs.bash}/bin/bash
          set -e # Exit on error

          if [ -f flake.nix ]; then
            echo "flake.nix already exists in current directory. Aborting."
            exit 1
          fi

          echo "Installing Python flake template..."
          # Copy flake content from the template file to make it writable
          cp ${flakeContentFile} ./flake.nix
          chmod +w ./flake.nix

          # Create .gitignore if it doesn't exist
          if [ ! -f .gitignore ]; then
            echo "Creating .gitignore..."
            cat > .gitignore << 'EOF'
.venv/
.idea/
__pycache__/
env/
result
**/*.pyc

# DL related
data/
wandb/
outputs/

EOF
          fi

          echo "Template installed successfully!"
          echo "You can now use 'nix develop' in this directory."
        '';

        # Define the name of the virtual env directory
        venvDir = ".venv";

      in
      {
        devShells.default = pkgs.mkShell {
          # venvShellHook needs to be listed here to modify the shell startup
          venvDir = venvDir; # Tell venvShellHook which directory to activate
          packages = with pkgs; [
            # Python interpreter itself
            python 
            
            # The hook responsible for automatic activation!
            pythonPackages.venvShellHook 

            # Nix-provided Python packages
            pythonPackages.matplotlib
            pythonPackages.numpy
            pythonPackages.ipykernel

            # Tools
            uv 
            git
            rsync
            bashInteractive 
            installScript 
            coreutils 
          ];

          buildInputs = with pkgs; [
            openssl
            zlib
          ];

          # This hook runs BEFORE the interactive shell starts.
          # Its job now is to PREPARE the environment.
          shellHook = ''
            # Exit on error
            set -e 
            
            # Set SOURCE_DATE_EPOCH 
            SOURCE_DATE_EPOCH=$(date +%s)
            
            # Ensure system libraries are findable
            export LD_LIBRARY_PATH="${lib-path}:$LD_LIBRARY_PATH"
            
            # Use the variable defined in 'let' block
            VENV_DIR="${venvDir}" 

            # Check if the venv directory needs to be created
            if [ ! -d "$VENV_DIR" ]; then
              echo "Creating Python virtual environment using uv in $VENV_DIR..."
              # Create the venv using uv, pointing to the Nix-provided Python
              ${pkgs.uv}/bin/uv venv -p ${python}/bin/python3.12 "$VENV_DIR" 
              # No need to activate here; venvShellHook will do it later.
              echo "Virtual environment created."
            else
              echo "Using existing virtual environment in $VENV_DIR"
            fi

            # Install/sync packages from requirements.txt using uv if it exists
            # We need to temporarily activate *within this script* to ensure
            # uv installs into the correct venv, especially if PATH isn't
            # immediately updated in this non-interactive hook context.
            # Alternatively, explicitly tell uv where the venv is if supported,
            # but sourcing activate is reliable here for the install step.
            if [ -f requirements.txt ]; then
              echo "Syncing environment with requirements.txt using uv..."
              # Temporarily activate for the install command within this hook
              source "$VENV_DIR/bin/activate"
              ${pkgs.uv}/bin/uv pip sync requirements.txt
              # Deactivate after install (optional, cleans up this script's env)
              deactivate 
            else
              echo "No requirements.txt found. Skipping package installation/sync."
            fi

            # Reminder for the template installation
            if [ ! -f flake.nix ]; then
              echo "---------------------------------------------------------------------"
              echo "This is a temporary shell. To make it persistent for this project,"
              echo "run 'install-template' to copy the flake.nix file here."
              echo "---------------------------------------------------------------------"
            fi

            # Message indicating setup is done (before venvShellHook activates)
            echo "Nix shell environment configured. venvShellHook will now activate $VENV_DIR."
          '';

          # postShellHook remains the same: Link Nix packages into the venv
          # This runs after shellHook but before the final interactive shell is fully ready.
          postShellHook = ''
            # Use the variable defined in 'let' block
            VENV_DIR="${venvDir}" 
            
            # Ensure the target directory exists before creating symlinks
            mkdir -p ./$VENV_DIR/lib/python3.12/site-packages/
            
            # Symlink Nix store site-packages into the venv's site-packages
            ln -sfn ${python.sitePackages}/* ./$VENV_DIR/lib/python3.12/site-packages/
          '';
        };

        # Expose the template installation as a package
        packages.default = installScript;
      }
    );
}
