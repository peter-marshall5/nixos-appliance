# Help systemd to find our boot device

{ config, ... }:
{
  systemd.services."link-volatile-root" = {
    description = "Register boot device on volatile root";
    script = ''
      ln -s /dev/root /run/systemd/volatile-root
    '';
    wantedBy = [ "local-fs-pre.target" ];
    before = [ "local-fs-pre.target" ];
  };
}
