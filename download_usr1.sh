#!/bin/sh

set -e

NCURSES="ncurses-6.2.tar.gz"
READLINE="readline-8.1.tar.gz"
BASH="bash-5.1.tar.gz"
COREUTILS="coreutils-8.32.tar.xz"
DIFFUTILS="diffutils-3.7.tar.xz"
FINDUTILS="findutils-4.8.0.tar.xz"
UTILLINUX="util-linux-2.36.tar.xz"
GAWK="gawk-5.1.0.tar.xz"
GREP="grep-3.6.tar.xz"
SED="sed-4.8.tar.xz"
TAR="tar-1.34.tar.xz"
NANO="nano-5.6.1.tar.xz"
XZ="xz-5.2.5.tar.xz"
GZIP="gzip-1.10.tar.xz"
BZIP2="bzip2-1.0.8.tar.gz"
ZLIB="zlib-1.2.11.tar.gz"
LESS="less-563.tar.gz"
FILE="file-5.40.tar.gz"
PROCPS="procps-v3.3.16.tar.bz2"
PSMISC="psmisc-v22.21.tar.bz2"
SQFSNG="squashfs-tools-ng-1.1.0.tar.xz"

mkdir -p "download" "src"

download() {
	if [ ! -f "download/$2" ]; then
		curl -L "https://$1/$2" > "download/$2"
	fi
}

download "ftp.gnu.org/gnu/readline" "$READLINE"
download "ftp.gnu.org/gnu/bash" "$BASH"
download "ftp.gnu.org/gnu/coreutils" "$COREUTILS"
download "ftp.gnu.org/gnu/diffutils" "$DIFFUTILS"
download "ftp.gnu.org/gnu/findutils" "$FINDUTILS"
download "ftp.gnu.org/gnu/gawk" "$GAWK"
download "ftp.gnu.org/gnu/grep" "$GREP"
download "ftp.gnu.org/gnu/sed" "$SED"
download "ftp.gnu.org/gnu/tar" "$TAR"
download "ftp.gnu.org/gnu/nano" "$NANO"
download "ftp.gnu.org/gnu/gzip" "$GZIP"
download "sourceware.org/pub/bzip2" "$BZIP2"
download "zlib.net" "$ZLIB"
download "invisible-mirror.net/archives/ncurses" "$NCURSES"
download "downloads.sourceforge.net/project/lzmautils" "$XZ"
download "mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.36" "$UTILLINUX"
download "www.greenwoodsoftware.com/less" "$LESS"
download "astron.com/pub/file" "$FILE"
download "gitlab.com/procps-ng/procps/-/archive/v3.3.16" "$PROCPS"
download "gitlab.com/psmisc/psmisc/-/archive/v22.21" "$PSMISC"
download "infraroot.at/pub/squashfs" "$SQFSNG"

cat > download_usr1.sha256 <<_EOF
30306e0c76e0f9f1f0de987cf1c82a5c21e1ce6568b9227f7da5b71cbea86c9d  download/$NCURSES
f8ceb4ee131e3232226a17f51b164afc46cd0b9e6cef344be87c65962cb82b02  download/$READLINE
cc012bc860406dcf42f64431bcd3d2fa7560c02915a601aba9cd597a39329baa  download/$BASH
4458d8de7849df44ccab15e16b1548b285224dbba5f08fac070c1c0e0bcc4cfa  download/$COREUTILS
b3a7a6221c3dc916085f0d205abf6b8e1ba443d4dd965118da364a1dc1cb3a26  download/$DIFFUTILS
57127b7e97d91282c6ace556378d5455a9509898297e46e10443016ea1387164  download/$FINDUTILS
9e4b1c67eb13b9b67feb32ae1dc0d50e08ce9e5d82e1cccd0ee771ad2fa9e0b1  download/$UTILLINUX
cf5fea4ac5665fd5171af4716baab2effc76306a9572988d5ba1078f196382bd  download/$GAWK
667e15e8afe189e93f9f21a7cd3a7b3f776202f417330b248c2ad4f997d9373e  download/$GREP
f79b0cfea71b37a8eeec8490db6c5f7ae7719c35587f21edb0617f370eeff633  download/$SED
63bebd26879c5e1eea4352f0d03c991f966aeb3ddeb3c7445c902568d5411d28  download/$TAR
760d7059e0881ca0ee7e2a33b09d999ec456ff7204df86bee58eb6f523ee8b09  download/$NANO
ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269  download/$BZIP2
8425ccac99872d544d4310305f915f5ea81e04d0f437ef1a230dc9d1c819d7c0  download/$GZIP
3e1e518ffc912f86608a8cb35e4bd41ad1aec210df2a47aaa1f95e7f5576ef56  download/$XZ
c3e5e9fdd5004dcb542feda5ee4f0ff0744628baf8ed2dd5d66f8ca1197cb1a1  download/$ZLIB
ce5b6d2b9fc4442d7a07c93ab128d2dff2ce09a1d4f2d055b95cf28dd0dc9a9a  download/$LESS
167321f43c148a553f68a0ea7f579821ef3b11c27b8cbe158e4df897e4a5dd57  download/$FILE
720caf307ab5dfe6d1cf4fc3e6ce786d749c69baa088627dbe1b01828f2528b1  download/$PROCPS
1ec96d8f88905f01c857c0bbef1694aa913c5de91bc7b6f51296699df4cef389  download/$PSMISC
110794124b268e92e28e6a95f0781d1338f48c338434ef746f5de68c64e19aeb  download/$SQFSNG
_EOF

sha256sum -c download_usr1.sha256

tar -xf "download/$NCURSES" -C "src"
tar -xf "download/$READLINE" -C "src"
tar -xf "download/$BASH" -C "src"
tar -xf "download/$COREUTILS" -C "src"
tar -xf "download/$DIFFUTILS" -C "src"
tar -xf "download/$FINDUTILS" -C "src"
tar -xf "download/$GREP" -C "src"
tar -xf "download/$GAWK" -C "src"
tar -xf "download/$SED" -C "src"
tar -xf "download/$TAR" -C "src"
tar -xf "download/$UTILLINUX" -C "src"
tar -xf "download/$NANO" -C "src"
tar -xf "download/$XZ" -C "src"
tar -xf "download/$GZIP" -C "src"
tar -xf "download/$BZIP2" -C "src"
tar -xf "download/$ZLIB" -C "src"
tar -xf "download/$LESS" -C "src"
tar -xf "download/$FILE" -C "src"
tar -xf "download/$PROCPS" -C "src"
tar -xf "download/$PSMISC" -C "src"
tar -xf "download/$SQFSNG" -C "src"
