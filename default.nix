{
  coreutils,
  curl,
  ffmpeg,
  fzf,
  gnugrep,
  gnupatch,
  gnused,
  html-xml-utils,
  lib,
  makeWrapper,
  mpv,
  openssl,
  awk,
  stdenv,
  testers,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "lobster";
  version = "4.3.0";

  src = ./.;
  # src = fetchFromGitHub {
  #   owner = "justchokingaround";
  #   repo = "lobster";
  #   rev = "v${finalAttrs.version}";
  #   hash = "sha256-YBgZmdi3eIbXlhPzMNi6bGpX/vdxGNcvc1gMx98o354="; # 4.0.6
  # };

  nativeBuildInputs = [
    coreutils # wc
    curl
    ffmpeg
    fzf
    gnugrep
    gnupatch
    gnused
    html-xml-utils
    makeWrapper
    mpv
    openssl
    awk
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp lobster.sh $out/bin/lobster
    wrapProgram $out/bin/lobster \
      --prefix PATH : ${lib.makeBinPath [
      coreutils
      curl
      ffmpeg
      fzf
      gnugrep
      gnupatch
      gnused
      html-xml-utils
      mpv
      openssl
      awk
    ]}
  '';

  passthru.tests.version = testers.testVersion {
    package = finalAttrs.finalPackage;
  };

  meta = with lib; {
    description = "CLI to watch Movies/TV Shows from the terminal";
    homepage = "https://github.com/justchokingaround/lobster";
    license = licenses.gpl3;
    maintainers = with maintainers; [benediktbroich];
    platforms = platforms.unix;
  };
})
