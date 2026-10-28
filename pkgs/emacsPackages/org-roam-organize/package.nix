{
  lib,
  src,
  melpaBuild,
  org,
  org-roam,
}:
melpaBuild {
  inherit src;
  pname = "org-roam-organize";
  version = "0.8.0";
  melpaVersion = "0.8.0";
  files = "(:defaults)";
  packageRequires = [
    org
    org-roam
  ];
  turnCompilationWarningToError = true;

  meta = {
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.all;
  };
}
