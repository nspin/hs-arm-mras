#!/bin/sh

set -e

here="$(dirname "$0")"

. "$here/lib.sh"

root="$here/nix-results"

mkdir -p "$root"

go_r arm-mras.xml.sysreg
go_r arm-mras.xml.aarch64
go_r arm-mras.xml.aarch32
go_r arm-mras.patched-aarch64
go_r arm-mras.patched-aarch32
go_r arm-mras.dtd-src.sysreg
go_r arm-mras.dtd-src.aarch64
go_r arm-mras.dtd-src.aarch32
go_r arm-mras.arm-mras-values-src

go_r harm.harm-tables-src

go_r arm-mras.arm-mras
go_r asl
go_r harm.harm
