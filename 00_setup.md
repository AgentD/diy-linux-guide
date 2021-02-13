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


### The Filesystem Hierarchy

You might be familiar with the [Linux Filesyste Hiearchy Standard](https://en.wikipedia.org/wiki/Filesystem_Hierarchy_Standard)
which strives to standardize the root filesytem layout across GNU/Linux distros.

This layout of course goes back to the [directory hierarchy on Unix Systems](https://en.wikipedia.org/wiki/Unix_directory_structure)
which in turn hasn't been designed in any particular way, but evolved over the
course of history.

One issue that we will run into is that there are multiple possible places that
libraries and program binaries could be installed to:
 - `/bin`
 - `/sbin`
 - `/lib`
 - `/usr/bin`
 - `/usr/sbin`
 - `/usr/lib`

Yes, I know that there is an additional `/usr/local` sub-sub-hierarchy, but we'll
ignore that once, since *nowadays** nobody outside the BSD world actually uses
that.

The split between `/` and `/usr` has historical reasons. The `/usr` directory
used to be the home directory for the system users (e.g. `/usr/ken` was Ken
Thompsons and `/usr/dmr` that of Dennis M. Ritchie) and was mounted from a
separate disk during boot. At some point space on the primary disk grew tight
and programs that weren't essential for system booting were moved from `/bin`
to `/usr/bin` to free up some space. The home directories were later moved to
an additional disk, mounted to `/home`. [So basically this split is a historic artifact](http://lists.busybox.net/pipermail/busybox/2010-December/074114.html).

Anyway, for the system we are building, I will get rid of the pointless `/bin`
and `/sbin` split, as well as the `/usr` sub-hiearchy split, but some programs
are stubborn and use hard coded paths (remember the last time you
used `#!/usr/bin/env` to make a script "portable"? You just replaced one
portabillity problem with another one). So we will set up symlinks in `/usr`
pointing back to `/bin` and `/lib`.

Enough for the ranting, lets setup our directory hierarchy:

    mkdir -p "$SYSROOT/bin" "$SYSROOT/lib"
    mkdir -p "$SYSROOT/usr/share" "$SYSROOT/usr/include"

    ln -s "../bin" "$SYSROOT/usr/bin"
    ln -s "../lib" "$SYSROOT/usr/lib"
