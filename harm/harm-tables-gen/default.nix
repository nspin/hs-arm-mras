{ mkDerivation, arm-mras, attoparsec, base, bytestring, directory
, filepath, harm-types, haskell-src-exts, lens, stdenv
}:
mkDerivation {
  pname = "harm-tables-gen";
  version = "0.1";
  src = ./.;
  isLibrary = false;
  isExecutable = true;
  executableHaskellDepends = [
    arm-mras attoparsec base bytestring directory filepath harm-types
    haskell-src-exts lens
  ];
  license = stdenv.lib.licenses.mit;
}
