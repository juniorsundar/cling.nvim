{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      # Define supported systems
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # Helper function to generate outputs for each system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

    in
    {
      # Development shells for each supported system
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            name = "neovim-config";
            packages = [
              pkgs.uv
              pkgs.python3
              pkgs.lua-language-server
              pkgs.stylua
              pkgs.bash-completion
            ];

            shellHook = ''
              VENV_DIR=".venv"

              if [ ! -d "$VENV_DIR" ]; then
                echo "Creating Python virtual environment at $VENV_DIR..."
                uv venv $VENV_DIR -p ${pkgs.python3}/bin/python
              fi

              source "$VENV_DIR/bin/activate"

              # uv pip install --quiet -r requirements.txt

              uv pip install pre-commit
              pre-commit install

              source ${pkgs.bash-completion}/etc/profile.d/bash_completion.sh
              # zsh
            '';
          };
        }
      );
    };
}
