{
  description = "dotfiles";

  inputs = {
    # Use `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` to use Nixpkgs 26.05.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Use `github:nix-darwin/nix-darwin/nix-darwin-26.05` to use Nixpkgs 26.05.
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # treehouse (kunchenguid): pool de git worktrees reusaveis. Vem do flake do
    # proprio upstream, nao do install.sh via curl que o README oferece — mesma
    # regra do item 3.4 do checklist. Versao travada pelo flake.lock.
    #
    # O `follows` abaixo nao e cosmetico: o flake dele pede nixpkgs-unstable e
    # sem isso o lock carregaria um segundo nixpkgs inteiro. Medido em
    # 29/jul/2026 que ele compila contra o 26.05-darwin daqui (buildGoModule e
    # git sao tudo que ele consome do nixpkgs).
    treehouse.url = "github:kunchenguid/treehouse";
    treehouse.inputs.nixpkgs.follows = "nixpkgs";

    # firstmate (kunchenguid): distro de shell scripts. NAO tem flake.nix, nao
    # tem binario e nao tem releases (verificado em 29/jul/2026: 0 releases) — o
    # README e explicito: "There is no app to install: the cloned repo is the
    # distro". Dai `flake = false`: este input nao expoe pacote, existe so para o
    # flake.lock travar o rev que a ativacao do home-manager materializa.
    # Por que um clone e nao um pacote no store: ver o comentario em home.nix.
    firstmate.url = "github:kunchenguid/firstmate";
    firstmate.flake = false;
  };

  # O `...` importa: sem ele este padrao e fechado e qualquer input novo
  # (treehouse foi o primeiro) aborta com "unexpected argument".
  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs, ... }:
    let
      # The one username line to change if this isn't your machine.
      # bootstrap.sh offers to rewrite this for you if your macOS username differs.
      user = "alex";
    in
    {
      darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit user; };
        modules = [
          ./configuration.nix
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Without this, activation aborts on any pre-existing regular file it
            # wants to own ("would be clobbered"). Move it aside instead.
            home-manager.backupFileExtension = "hm-bak";
            home-manager.extraSpecialArgs = { inherit user inputs; };
            home-manager.users.${user} = import ./home.nix;
          }
        ];
      };

      # Binario do guest das microVMs: mesmo pin do host (nix/no-mistakes.nix),
      # compilado para linux/arm64. Sai como output do flake — e nao como um
      # `nix build --impure --expr` dentro do shell script — para que o build
      # continue puro e travado pelo flake.lock, igual ao resto da maquina.
      # Consumido por scripts/shuru-base-image.sh.
      packages.aarch64-darwin.no-mistakes-guest =
        import ./nix/no-mistakes.nix {
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          forLinuxArm64 = true;
        };
    };
}
