# Pin UNICO do no-mistakes. O host (home.nix) e a imagem-base das microVMs
# (scripts/shuru-base-image.sh) importam este mesmo arquivo, com alvos
# diferentes. Nao duplique version/rev/hash em outro lugar: o fm-bootstrap valida
# a versao parseando `no-mistakes --version` contra um minimo, e se o rev morasse
# longe da version um bump pela metade passaria no build e falharia so no check.
# Atualizar = trocar version + rev e limpar os dois hashes, aqui e so aqui.
#
# forLinuxArm64 = true produz o binario do guest (Debian 13 aarch64). Mesmo
# fonte, mesmo commit, mesmos ldflags — a unica diferenca e o alvo.
{
  pkgs,
  forLinuxArm64 ? false,
}:

let
  version = "1.41.2";

  # buildGoModule le GOOS/GOARCH do pacote `go` e SOBRESCREVE qualquer `env` que
  # o chamador passe: em pkgs/build-support/go/module.nix a linha e
  # `env = args.env or { } // { inherit (go) GOOS GOARCH; ... }` — o lado direito
  # do `//` ganha. Entao mudar o alvo exige trocar o proprio `go`, e nao ha como
  # fazer isso por `env` nem por `overrideAttrs`.
  #
  # Por que `pkgs.go // { ... }` e nao `pkgs.pkgsCross.aarch64-multiplatform`: o
  # cross stdenv arrastaria um toolchain gcc darwin->linux inteiro, que nao esta
  # no cache binario e que este pacote nao usaria para nada — o no-mistakes e Go
  # puro e vai com CGO desligado. O `//` mantem o stdenv nativo (darwin) e apenas
  # instrui o compilador do Go, que ja e cross-compilador por construcao.
  # A derivacao sobrevive ao `//` (outPath e type continuam la), entao ela ainda
  # funciona como nativeBuildInput.
  goFor =
    if forLinuxArm64 then
      pkgs.go
      // {
        GOOS = "linux";
        GOARCH = "arm64";
        CGO_ENABLED = 0;
      }
    else
      pkgs.go;

  buildGoModule = pkgs.buildGoModule.override { go = goFor; };
in
buildGoModule {
  pname = "no-mistakes";
  inherit version;
  src = pkgs.fetchFromGitHub {
    owner = "kunchenguid";
    repo = "no-mistakes";
    rev = "867d64d9c2df89f3f204ad1f5528e5bf7b460caa"; # tag v1.41.2
    hash = "sha256-taoeI58AZ8mlAYhxlvD+fxU6ZX/WBdM9ghplnkjXZqU=";
  };
  vendorHash = "sha256-NZOYxNYvt4192uqKBdKRxdgrKFvWx3585psdCnRdPSM=";

  # O `gh` desta maquina e o build da Automic Vault, que escreve
  # "automic vault: human approval required" em stderr a CADA chamada e sai 0 —
  # aviso de auditoria, nao recusa. O no-mistakes le tres comandos com
  # CombinedOutput() e trata a saida como dado, entao a linha entra no valor:
  #
  #   FindPR     gh pr list --json    -> Unmarshal falha -> "nenhuma PR", e o
  #                                      pipeline abre uma segunda PR pra branch
  #   CreatePR   gh pr create         -> a URL nasce com a linha colada nela
  #   GetChecks  gh pr checks --json  -> "invalid character 'a'"; e o que matou
  #                                      o passo `ci` em 01/ago/2026
  #
  # Nenhum dos tres da erro barulhento: dois falham em silencio. A correcao le
  # stdout sozinho e vai buscar o stderr no ExitError so quando o comando falha,
  # preservando o "no checks reported" (que o gh escreve em stderr com exit != 0).
  # Presente identica no HEAD upstream (1.44.2), nao e defasagem do nosso pin.
  # Reportado em kunchenguid/no-mistakes#630 com este mesmo diff; este patch sai
  # daqui quando o upstream aceitar.
  patches = [ ./patches/no-mistakes-gh-stderr.patch ];

  # Sem isto o build tenta compilar .no-mistakes/evidence/**, que nao compila
  # (assinatura desatualizada de github.New) e derruba a derivacao inteira.
  subPackages = [ "cmd/no-mistakes" ];

  # O Makefile injeta a versao por ldflags; sem isso buildinfo.Version fica "dev",
  # o parse do fm-bootstrap nao acha semver e a ferramenta e reportada MISSING
  # mesmo instalada. Medido: `--version` responde "v1.41.2" e o sed do bootstrap
  # extrai "1 41 2".
  ldflags = [
    "-X github.com/kunchenguid/no-mistakes/internal/buildinfo.Version=v${version}"
  ];
  # Os ldflags de telemetria (TelemetryHost/TelemetryWebsiteID) ficam vazios de
  # proposito: build do source sem endpoint de telemetria embutido.

  doCheck = false;

  # O stdenv aqui e o de darwin, entao o fixup roda `strip` do darwin — que nao
  # entende ELF e aborta a derivacao no alvo do guest.
  dontStrip = forLinuxArm64;

  # Quando GOOS/GOARCH diferem do nativo, o Go instala em $GOPATH/bin/GOOS_GOARCH
  # e o $out/bin sai com um nivel a mais. O buildGoModule tem um passo que achata
  # isso, mas ele so roda quando `stdenv.hostPlatform != stdenv.buildPlatform` —
  # e aqui os dois continuam darwin de proposito (trocamos so o `go`). Sem este
  # achatamento o binario sai em bin/linux_arm64/no-mistakes e o `install` do
  # provisionamento nao o encontra.
  postInstall = pkgs.lib.optionalString forLinuxArm64 ''
    mv "$out/bin/linux_arm64/no-mistakes" "$out/bin/no-mistakes"
    rmdir "$out/bin/linux_arm64"
  '';
}
