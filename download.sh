#!/bin/sh

set -e

KERNEL="raspberrypi-kernel_1.20190925-1.tar.gz"
MUSL="musl-1.1.24.tar.gz"
BINUTILS="binutils-2.33.1.tar.xz"
GCC="gcc-9.2.0.tar.xz"
BUSYBOX="busybox-1.31.1.tar.bz2"

mkdir -p "download" "src"

curl -L "https://github.com/raspberrypi/linux/archive/$KERNEL" > \
     "download/$KERNEL"
curl -L "https://www.musl-libc.org/releases/$MUSL" > "download/$MUSL"
curl -L "https://ftp.gnu.org/gnu/binutils/$BINUTILS" > "download/$BINUTILS"
curl -L "https://ftp.gnu.org/gnu/gcc/gcc-9.2.0/$GCC" > "download/$GCC"
curl -L "https://busybox.net/downloads/$BUSYBOX" > "download/$BUSYBOX"

cat > download.sha256 <<_EOF
ab66fc2d1c3ec0359b8e08843c9f33b63e8707efdff5e4cc5c200eae24722cbf  download/binutils-2.33.1.tar.xz
ea6ef08f121239da5695f76c9b33637a118dcf63e24164422231917fa61fb206  download/gcc-9.2.0.tar.xz
1370c9a812b2cf2a7d92802510cca0058cc37e66a7bedd70051f0a34015022a3  download/musl-1.1.24.tar.gz
295651137abfaf3f1817d49051815a5eb0cc197d0100003d10e46f5eb0f45173  download/raspberrypi-kernel_1.20190925-1.tar.gz
d0f940a72f648943c1f2211e0e3117387c31d765137d92bd8284a3fb9752a998  download/busybox-1.31.1.tar.bz2
_EOF

sha256sum -c download.sha256

tar -xf "download/$KERNEL" -C "src"
tar -xf "download/$MUSL" -C "src"
tar -xf "download/$BINUTILS" -C "src"
tar -xf "download/$GCC" -C "src"
tar -xf "download/$BUSYBOX" -C "src"
