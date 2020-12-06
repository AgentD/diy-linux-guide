#!/bin/sh

set -e

KERNEL="raspberrypi-kernel_1.20201201-1.tar.gz"
MUSL="musl-1.2.1.tar.gz"
BINUTILS="binutils-2.35.tar.xz"
GCC="gcc-10.2.0.tar.xz"
BUSYBOX="busybox-1.32.0.tar.bz2"

mkdir -p "download" "src"

curl -L "https://github.com/raspberrypi/linux/archive/$KERNEL" > \
     "download/$KERNEL"
curl -L "https://www.musl-libc.org/releases/$MUSL" > "download/$MUSL"
curl -L "https://ftp.gnu.org/gnu/binutils/$BINUTILS" > "download/$BINUTILS"
curl -L "https://ftp.gnu.org/gnu/gcc/gcc-10.2.0/$GCC" > "download/$GCC"
curl -L "https://busybox.net/downloads/$BUSYBOX" > "download/$BUSYBOX"

cat > download.sha256 <<_EOF
1b11659fb49e20e18db460d44485f09442c8c56d5df165de9461eb09c8302f85  download/$BINUTILS
b8dd4368bb9c7f0b98188317ee0254dd8cc99d1e3a18d0ff146c855fe16c1d8c  download/$GCC
68af6e18539f646f9c41a3a2bb25be4a5cfa5a8f65f0bb647fd2bbfdf877e84b  download/$MUSL
78760205e85a47fdf99515fc227173e1ff3cee2bbf13c344a77d85efb2ee9ec4  download/$KERNEL
c35d87f1d04b2b153d33c275c2632e40d388a88f19a9e71727e0bbbff51fe689  download/$BUSYBOX
_EOF

sha256sum -c download.sha256

tar -xf "download/$KERNEL" -C "src"
tar -xf "download/$MUSL" -C "src"
tar -xf "download/$BINUTILS" -C "src"
tar -xf "download/$GCC" -C "src"
tar -xf "download/$BUSYBOX" -C "src"
