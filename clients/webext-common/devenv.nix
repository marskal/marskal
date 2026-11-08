{ pkgs, ... }:
{
  # Code the capture extensions share (ADR 0024, ADR 0035): type-checked and
  # tested here, bundled by each extension.
  languages.javascript = {
    enable = true;
    npm.enable = true;
  };

  packages = [
    pkgs.changie # changelog fragments (ADR 0038)
  ];
}
