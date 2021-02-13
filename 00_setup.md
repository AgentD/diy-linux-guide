# Prerequisites and Directory Setup

This section deals with the packages we need on our system to cross bootstrap
our mini distro, as well as the basic directory setup before we get started.

## Prerequisites

For compiling the packages you will need:

* gcc
* g++
* make
* flex
* bison
* gperf
* makeinfo
* ncurses (with headers)
* awk
* automake
* help2man
* curl
* pkg-config
* libtool
* openssl (with headers)


In case you wonder: even if you don't build any C++ package, you need the C++
compiler to build GCC. The GCC code base mainly uses C99, but with some
additional C++ features. `makeinfo` is used by the GNU utilities that generate
info pages from texinfo. ncurses is mainly needed by the kernel build system
for `menuconfig`. OpenSSL is also requried to compile the kernel later on.

The list should be fairly complete, but I can't guarantee that I didn't miss
something. Normally I work on systems with tons of development tools and
libraries already installed, so if something is missing, please install it
and maybe let me know.

## Directory Setup

First of all, you should create an empty directory somewhere where you want
to build the cross toolchain and later the entire system.

For convenience, we will store the absolute path to this directory inside a
shell variable called **BUILDROOT** and create a few directories to organize
our stuff in:

    BUILDROOT=$(pwd)

    mkdir -p "build" "src" "download" "toolchain/bin" "sysroot"

I stored the downloaded packages in the **download** directory and extracted
them to a directory called **src**.

We will later build packages outside the source tree (GCC even requires that
nowadays), inside a sub directory of **build**.

Our final toolchain will end up in a directory called **toolchain**.

We store the toolchain location inside another shell variable that I called
**TCDIR** and prepend the executable path of our toolchain to the **PATH**
variable:

    TCDIR="$BUILDROOT/toolchain"
    export PATH="$TCDIR/bin:$PATH"


The **sysroot** directory will hold the cross compiled binaries for our target
system, as well as headers and libraries used for cross compiling stuff. It is
basically the `/` directory of the system we are going to build. For
convenience, we will also store its absolute path in a shell variable:

    SYSROOT="$BUILDROOT/sysroot"
