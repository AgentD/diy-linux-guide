#!/bin/sh

set -e

KERNEL="raspberrypi-kernel_1.20201201-1.tar.gz"
MUSL="musl-1.2.2.tar.gz"
BINUTILS="binutils-2.36.tar.xz"
GCC="gcc-10.2.0.tar.xz"
BUSYBOX="busybox-1.32.1.tar.bz2"

mkdir -p "download" "src"

curl -L "https://github.com/raspberrypi/linux/archive/$KERNEL" > \
     "download/$KERNEL"
curl -L "https://musl.libc.org/releases/$MUSL" > "download/$MUSL"
curl -L "https://ftp.gnu.org/gnu/binutils/$BINUTILS" > "download/$BINUTILS"
curl -L "https://ftp.gnu.org/gnu/gcc/gcc-10.2.0/$GCC" > "download/$GCC"
curl -L "https://busybox.net/downloads/$BUSYBOX" > "download/$BUSYBOX"

cat > download.sha256 <<_EOF
5788292cc5bbcca0848545af05986f6b17058b105be59e99ba7d0f9eb5336fb8  download/$BINUTILS
b8dd4368bb9c7f0b98188317ee0254dd8cc99d1e3a18d0ff146c855fe16c1d8c  download/$GCC
9b969322012d796dc23dda27a35866034fa67d8fb67e0e2c45c913c3d43219dd  download/$MUSL
78760205e85a47fdf99515fc227173e1ff3cee2bbf13c344a77d85efb2ee9ec4  download/$KERNEL
9d57c4bd33974140fd4111260468af22856f12f5b5ef7c70c8d9b75c712a0dee  download/$BUSYBOX
_EOF

sha256sum -c download.sha256

tar -xf "download/$KERNEL" -C "src"
tar -xf "download/$MUSL" -C "src"
tar -xf "download/$BINUTILS" -C "src"
tar -xf "download/$GCC" -C "src"
tar -xf "download/$BUSYBOX" -C "src"
