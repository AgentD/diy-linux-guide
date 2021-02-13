# Building a Cross Compiler Toolchain

As it turns out, building a cross compiler toolchain with recent GCC and
binutils is a lot easier nowadays than it used to be.

I'm building the toolchain on an AMD64 (aka x86_64) system. The steps have
been tried on [Fedora](https://getfedora.org/) as well as on
[OpenSUSE](https://www.opensuse.org/).

The toolchain we are building generates 32 bit ARM code intended to run on
a Raspberry Pi 3. [Musl](https://www.musl-libc.org/) is used as a C standard
library implementation.

## Downloading and unpacking everything

The following source packages are required for building the toolchain. The
links below point to the exact versions that I used.

* [Linux](https://github.com/raspberrypi/linux/archive/raspberrypi-kernel_1.20201201-1.tar.gz).
  Linux is a very popular OS kernel that we will use on our target system.
  We need it to build the the C standard library for our toolchain.
* [Musl](https://www.musl-libc.org/releases/musl-1.2.2.tar.gz). A tiny
  C standard library implementation.
* [Binutils](https://ftp.gnu.org/gnu/binutils/binutils-2.36.tar.xz). This
  contains the GNU assembler, linker and various tools for working with
  executable files.
* [GCC](https://ftp.gnu.org/gnu/gcc/gcc-10.2.0/gcc-10.2.0.tar.xz), the GNU
  compiler collection. Contains compilers for C and other languages.

Simply download the packages listed above into `download` and unpack them
into `src`.

For convenience, I provided a small shell script called `download.sh` that,
when run inside `$BUILDROOT` does this and also verifies the `sha256sum`
of the packages, which will further make sure that you are using the **exact**
same versions as I am.

Right now, you should have a directory tree that looks something like this:

* build/
* toolchain/
   * bin/
* src/
   * binutils-2.36/
   * gcc-10.2.0/
   * musl-1.2.2/
   * linux-raspberrypi-kernel_1.20201201-1/
* download/
   * binutils-2.36.tar.xz
   * gcc-10.2.0.tar.xz
   * musl-1.2.2.tar.gz
   * raspberrypi-kernel_1.20201201-1.tar.gz
* sysroot/

For building GCC, we will need to download some additional support libraries.
Namely gmp, mfpr, mpc and isl that have to be unpacked inside the GCC source
tree. Luckily, GCC nowadays provides a shell script that will do that for us:

	cd "$BUILDROOT/src/gcc-10.2.0"
	./contrib/download_prerequisites
	cd "$BUILDROOT"


# Overview

From now on, the rest of the process itself consists of the following steps:

1. Installing the kernel headers to the sysroot directory.
2. Compiling cross binutils.
3. Compiling a minimal GCC cross compiler with minimal `libgcc`.
4. Cross compiling the C standard library (in our case Musl).
5. Compiling a full version of the GCC cross compiler with complete `libgcc`.

The main reason for compiling GCC twice is the inter-dependency between the
compiler and the standard library.

First of all, the GCC build system needs to know *what* kind of C standard
library we are using and *where* to find it. For dynamically linked programs,
it also needs to know what loader we are going to use, which is typically
also provided by the C standard library. For more details, you can read this
high level overview [how dyncamically linked ELF programs are run](elfstartup.md).

Second, there is [libgcc](https://gcc.gnu.org/onlinedocs/gccint/Libgcc.html).
`libgcc` contains low level platform specific helpers (like exception handling,
soft float code, etc.) and is automatically linked to programs built with GCC.
Libgcc source code comes with GCC and is compiled by the GCC build system
specifically for our cross compiler & libc combination.

However, some functions in the `libgcc` need functions from the C standard
library. Some libc implementations directly use utility functions from `libgcc`
such as stack unwinding helpers (provided by `libgcc_s`).

After building a GCC cross compiler, we need to cross compile `libgcc`, so we
can *then* cross compile other stuff that needs `libgcc` **like the libc**. But
we need an already cross compiled libc in the first place for
compiling `libgcc`.

The solution is to build a minimalist GCC that targets an internal stub libc
and provides a minimal `libgcc` that has lots of features disabled and uses
the stubs instead of linking against libc.

We can then cross compile the libc and let the compiler link it against the
minimal `libgcc`.

With that, we can then compile the full GCC, pointing it at the C standard
library for the target system and build a fully featured `libgcc` along with
it. We can simply install it *over* the existing GCC and `libgcc` in the
toolchain directory (dynamic linking for the rescue).

## Autotools and the canonical target tuple

Most of the software we are going to build is using autotools based build
systems. There are a few things we should know when working with autotools
based packages.

GNU autotools makes cross compilation easy and has checks and workarounds for
the most bizarre platforms and their misfeatures. This was especially important
in the early days of the GNU project when there were dozens of incompatible
Unices on widely varying hardware platforms and the GNU packages were supposed
to build and run on all of them.

Nowadays autotools offers *decades* of being used in practice and is in my
experience a lot more mature than more modern build systems. Also, having a
semi standard way of cross compiling stuff with standardized configuration
knobs is very helpful.

In contrast to many modern build systems, you don't need Autotools to run an
Autotools based build system. The final build system it generates for the
release tarballs just uses shell and `make`.

### The configure script

Pretty much every novice Ubuntu user has probably already seen this on Stack
Overflow (and copy-pasted it) at least once:

    ./configure
    make
    make install


The `configure` shell script generates the actual `Makefile` from a
template (`Makefile.in`) that is then used for building the package.

The `configure` script itself and the `Makefile.in` are completely independent
from autotools and were generated by `autoconf` and `automake`.

If we don't want to clobber the source tree, we can also build a package
*outside the source tree* like this:

    ../path/to/source/configure
    make

The `configure` script contains *a lot* of system checks and default flags that
we can use for telling the build system how to compile the code.

The main ones we need to know about for cross compiling are the following
three options:

* The **--build** option specifies what system we are *building* the
  package on.
* The **--host** option specifies what system the binaries will run on.
* The **--target** option is specific for packages that contain compilers
  and specify what system to generate output for.

Those options take as an argument a dash seperated tuple that describes
a system and is made up the following way:

	<architecture>-<vendor>-<kernel>-<userspace>

The vendor part is completely optional and we will only use 3 components to
discribe our toolchain. So for our 32 bit ARM system, running a Linux kernel
with a Musl based user space, is described like this:

	arm-linux-musleabihf

The user space component itself specifies that we use `musl` and we want to
adhere to the ARM embedded ABI specification (`eabi` for short) with hardware
float `hf` support.

If you want to determine the tuple for the system *you are running on*, you can
use the script [config.guess](https://git.savannah.gnu.org/gitweb/?p=config.git;a=tree):

	$ HOST=$(./config.guess)
	$ echo "$HOST"
	x86_64-pc-linux-gnu

There are reasons for why this script exists and why it is that long. Even
on Linux distributions, there is no consistent way, to pull a machine triple
out of a shell one liner.

Some guides out there suggest using a shell builtin **MACHTYPE**:

    $ echo "$MACHTYPE"
    x86_64-redhat-linux-gnu

The above is what I got on Fedora, however on Arch Linux I got this:

    $ echo "$MACHTYPE"
    x86_64

Some other guides suggest using `uname` and **OSTYPE**:

    $ HOST=$(uname -m)-$OSTYPE
    $ echo $HOST
    x86_64-linux-gnu

This works on Fedora and Arch Linux, but fails on OpenSuSE:

	$ HOST=$(uname -m)-$OSTYPE
    $ echo $HOST
    x86_64-linux

If you want to safe yourself a lot of headache, refrain from using such
adhockery and simply use `config.guess`. I only listed this here to warn you,
because I have seen some guides and tutorials out there using this nonsense.

As you saw here, I'm running on an x86_64 system and my user space is `gnu`,
which tells autotools that the system is using `glibc`.

You also saw that the `vendor` is sometimes used for branding, so use that
field if you must, because the others have exact meaning and are parsed by
the buildsystem.

### The Installation Path

When running `make install`, there are two ways to control where the program
we just compiled is installed to.

First of all, the `configure` script has an option called `--prefix`. That can
be used like this:

	./configure --prefix=/usr
	make
	make install

In this case, `make install` will e.g. install the program to `/usr/bin` and
install resources to `/usr/share`. The important thing here is that the prefix
is used to generate path variables and the program "knows" what it's prefix is,
i.e. it will fetch resource from `/usr/share`.

But if instead we run this:

	./configure --prefix=/opt/yoyodyne
	make
	make install

The same program is installed to `/opt/yoyodyne/bin` and its resource end up
in `/opt/yoyodyne/share`. The program again knows to look in the later path for
its resources.

The second option we have is using a Makefile variable called `DESTDIR`, which
controls the behavior of `make install` *after* the program has been compiled:

	./configure --prefix=/usr
	make
	make DESTDIR=/home/goliath/workdir install

In this example, the program is installed to `/home/goliath/workdir/usr/bin`
and the resources to `/home/goliath/workdir/usr/share`, but the program itself
doesn't know that and "thinks" it lives in `/usr`. If we try to run it, it
thries to load resources from `/usr/share` and will be sad because it can't
find its files.

## Building our Toolchain

At first, we set a few handy shell variables that will store the configuration
of our toolchain:

    TARGET="arm-linux-musleabihf"
	HOST="x86_64-linux-gnu"
    LINUX_ARCH="arm"
    MUSL_CPU="arm"
    GCC_CPU="armv6"

The **TARGET** variable holds the *target triplet* of our system as described
above.

We also need the triplet for the local machine that we are going to build
things on. For simplicity, I also set this manually.

The **MUSL_CPU**, **GCC_CPU** and **LINUX_ARCH** variables hold the target
CPU architecture. The variables are used for musl, gcc and linux respecitively,
because they cannot agree on consistent architecture names (except sometimes).

### Installing the kernel headers

We create a build directory called **$BUILDROOT/build/linux**. Building the
kernel outside its source tree works a bit different compared to autotools
based stuff.

To keep things clean, we use a shell variable **srcdir** to remember where
we kept the kernel source. A pattern that we will repeat later:

    export KBUILD_OUTPUT="$BUILDROOT/build/linux"
    mkdir -p "$KBUILD_OUTPUT"

    srcdir="$BUILDROOT/src/linux-raspberrypi-kernel_1.20201201-1"

    cd "$srcdir"
    make O="$KBUILD_OUTPUT" ARCH="$LINUX_ARCH" headers_check
    make O="$KBUILD_OUTPUT" ARCH="$LINUX_ARCH" INSTALL_HDR_PATH="$SYSROOT/usr" headers_install
    cd "$BUILDROOT"


According to the Makefile in the Linux source, you can either specify an
environment variable called **KBUILD_OUTPUT**, or set a Makefile variable
called **O**, where the later overrides the environment variable. The snippet
above shows both ways.

The *headers_check* target runs a few trivial sanity checks on the headers
we are going to install. It checks if a header includes something nonexistent,
if the declarations inside the headers are sane and if kernel internals are
leaked into user space. For stock kernel tar-balls, this shouldn't be
necessary, but could come in handy when working with kernel git trees,
potentially with local modifications.

Lastly (before switching back to the root directory), we actually install the
kernel headers into the sysroot directory where the libc later expects them
to be.

The `sysroot` directory should now contain a `usr/include` directory with a
number of sub directories that contain kernel headers.

Since I've seen the question in a few forums: it doesn't matter if the kernel
version exactly matches the one running on your target system. The kernel
system call ABI is stable, so you can use an older kernel. Only if you use a
much newer kernel, the libc might end up exposing or using features that your
kernel does not yet support.

If you have some embedded board with a heavily modified vendor kernel (such as
in our case) and little to no upstream support, the situation is a bit more
difficult and you may prefer to use the exact kernel.

Even then, if you have some board where the vendor tree breaks the
ABI **take the board and burn it** (preferably outside; don't inhale
the fumes).

### Compiling cross binutils

We will compile binutils outside the source tree, inside the directory
**build/binutils**. So first, we create the build directory and switch into
it:

    mkdir -p "$BUILDROOT/build/binutils"
    cd "$BUILDROOT/build/binutils"

    srcdir="$BUILDROOT/src/binutils-2.36"

From the binutils build directory we run the configure script:

    $srcdir/configure --prefix="$TCDIR" --target="$TARGET" \
                      --with-sysroot="$SYSROOT" \
                      --disable-nls --disable-multilib

We use the **--prefix** option to actually let the toolchain know that it is
being installed in our toolchain directory, so it can locate its resources and
helper programs when we run it.

We also set the **--target** option to tell the build system what target the
assembler, linker and other tools should generate **output** for. We don't
explicitly set the **--host** or **--build** because we are compiling binutils
to run on the local machine.

We would only set the **--host** option to cross compile binutils itself with
an existing toolchain to run on a different system than ours.

The **--with-sysroot** option tells the build system that the root directory
of the system we are going to build is in `$SYSROOT` and it should look inside
that to find libraries.

We disable the feature **nls** (native language support, i.e. cringe worthy
translations of error messages to your native language, such as Deutsch
or 中文), mainly because we don't need it and not doing something typically
saves time.

Regarding the multilib option: Some architectures support executing code for
other, related architectures (e.g. an x86_64 machine can run 32 bit x86 code).
On GNU/Linux distributions that support that, you typically have different
versions of the same libraries (e.g. in *lib/* and *lib32/* directories) with
programs for different architectures being linked to the appropriate libraries.
We are only interested in a single architecture and don't need that, so we
set **--disable-multilib**.


Now we can compile and install binutils:

    make configure-host
    make
    make install
    cd "$BUILDROOT"

The first make target, *configure-host* is binutils specific and just tells it
to check out the system it is *being built on*, i.e. your local machine and
make sure it has all the tools it needs for compiling. If it reports a problem,
**go fix it before continuing**.

We then go on to build the binutils. You may want to speed up compilation by
running a parallel build with **make -j NUMBER-OF-PROCESSES**.

Lastly, we run *make install* to install the binutils in the configured
toolchain directory and go back to our root directory.

The `toolchain/bin` directory should now already contain a bunch of executables
such as the assembler, linker and other tools that are prefixed with the host
triplet.

There is also a new directory called `toolchain/arm-linux-musleabihf` which
contains a secondary system root with programs that aren't prefixed, and some
linker scripts.

### First pass GCC

Similar to above, we create a directory for building the compiler, change
into it and store the source location in a variable:

    mkdir -p "$BUILDROOT/build/gcc-1"
    cd "$BUILDROOT/build/gcc-1"

    srcdir="$BUILDROOT/src/gcc-10.2.0"

Notice, how the build directory is called *gcc-1*. For the second pass, we
will later create a different build directory. Not only does this out of tree
build allow us to cleanly start afresh (because the source is left untouched),
but current versions of GCC will *flat out refuse* to build inside the
source tree.

    $srcdir/configure --prefix="$TCDIR" --target="$TARGET" --build="$HOST" \
                      --host="$HOST" --with-sysroot="$SYSROOT" \
                      --disable-nls --disable-shared --without-headers \
                      --disable-multilib --disable-decimal-float \
                      --disable-libgomp --disable-libmudflap \
                      --disable-libssp --disable-libatomic \
                      --disable-libquadmath --disable-threads \
                      --enable-languages=c --with-newlib \
                      --with-arch="$GCC_CPU" --with-float=hard \
                      --with-fpu=neon-vfpv3

The **--prefix**, **--target** and **--with-sysroot** work just like above for
binutils.

This time we explicitly specify **--build** (i.e. the system that we are going
to compile GCC on) and **--host** (i.e. the system that the GCC will run on).
In our case those are the same. I set those explicitly for GCC, because the GCC
build system is notoriously fragile. Yes, *I have seen* older versions of GCC
throw a fit or assume complete nonsense if you don't explicitly specify those
and at this point I'm no longer willing to trust it.

The option **--with-arch** gives the build system slightly more specific
information about the target processor architecture. The two options after that
are specific for our target and tell the buildsystem that GCC should use the
hardware floating point unit and can emit neon instructions for vectorization.

We also disable a bunch of stuff we don't need. I already explained *nls*
and *multilib* above. We also disable a bunch of optimization stuff and helper
libraries. Among other things, we also disable support for dynamic linking and
threads as we don't have the libc yet.

The option **--without-headers** tells the build system that we don't have the
headers for the libc *yet* and it should use minimal stubs instead where it
needs them. The **--with-newlib** option is *more of a hack*. It tells that we
are going to use the [newlib](http://www.sourceware.org/newlib/) as C standard
library. This isn't actually true, but forces the build system to disable some
[libgcc features that depend on the libc](https://gcc.gnu.org/ml/gcc-help/2009-07/msg00368.html).

The option **--enable-languages** accepts a comma separated list of languages
that we want to build compilers for. For now, we only need a C compiler for
compiling the libc.

If you are interested: [Here is a detailed list of all GCC configure options.](https://gcc.gnu.org/install/configure.html)

Now, lets build the compiler and `libgcc`:

    make all-gcc all-target-libgcc
    make install-gcc install-target-libgcc

    cd "$BUILDROOT"

We explicitly specify the make targets for *GCC* and *cross-compiled libgcc*
for our target. We are not interested in anything else.

For the first make, you **really** want to specify a *-j NUM-PROCESSES* option
here. Even the first pass GCC we are building here will take a while to compile
on an ordinary desktop machine.

### C standard library

We create our build directory and change there:

    mkdir -p "$BUILDROOT/build/musl"
    cd "$BUILDROOT/build/musl"

    srcdir="$BUILDROOT/src/musl-1.2.2"

Musl is quite easy to build but requires some special handling, because it
doesn't use autotools. The configure script is actually a hand written shell
script that tries to emulate some of the typical autotools handling:

    CC="${TARGET}-gcc" $srcdir/configure --prefix=/ --includedir=/usr/include \
                                         --target="$TARGET"

We override the shell variable **CC** to point to the cross compiler that we
just built. Remember, we added **$TCDIR/bin** to our **PATH**.

We also set the compiler for actually compiling musl and we explicitly set
the **DESTDIR** variable for installing:

    CC="${TARGET}-gcc" make
    make DESTDIR="$SYSROOT" install

    cd "$BUILDROOT"

The important part here, that later also applies for autotools based stuff, is
that we don't set **--prefix** to the sysroot directory. We set the prefix so
that the build system "thinks" it compiles the library to be installed
in `/`, but then we install the compiled binaries and headers to the sysroot
directory.

The `sysroot/usr/include` directory should now contain a bunch of standard
headers. Likewise, the `sysroot/usr/lib` directory should now contain a
`libc.so`, a bunch of dummy libraries, and the startup object code provided
by Musl.

The prefix is set to `/` because we want the libraries to be installed
to `/lib` instead of `/usr/lib`, but we still want the header files
in `/usr/include`, so we explicitly specifiy the **--includedir**.

### Second pass GCC

We are reusing the same source code from the first stage, but in a different
build directory:

    mkdir -p "$BUILDROOT/build/gcc-2"
    cd "$BUILDROOT/build/gcc-2"

    srcdir="$BUILDROOT/src/gcc-10.2.0"

Most of the configure options should be familiar already:

    $srcdir/configure --prefix="$TCDIR" --target="$TARGET" --build="$HOST" \
                      --host="$HOST" --with-sysroot="$SYSROOT" \
                      --disable-nls --enable-languages=c,c++ \
                      --enable-c99 --enable-long-long \
                      --disable-libmudflap --disable-multilib \
                      --disable-libsanitizer --with-arch="$CPU" \
                      --with-native-system-header-dir="/usr/include" \
                      --with-float=hard --with-fpu=neon-vfpv3

For the second pass, we also build a C++ compiler. The options **--enable-c99**
and **--enable-long-long** are actually C++ specific. When our final compiler
runs in C++98 mode, we allow it to expose C99 functions from the libc through
a GNU extension. We also allow it to support the *long long* data type
standardized in C99.

You may wonder why we didn't have to build a **libstdc++** between the
first and second pass, like the libc. The source code for the *libstdc++*
comes with the **g++** compiler and is built automatically like `libgcc`.
On the one hand, it is really just a library that adds C++ stuff
*on top of libc*, mostly header only code that is compiled with the actual
C++ programs. On the other hand, C++ does not have a standard ABI and it is
all compiler and OS specific. So compiler vendors will typically ship their
own `libstdc++` implementation with the compiler.

We **--disable-libsanitizer** because it simply won't build for musl. I tried
fixing it, but it simply assumes too much about the nonstandard internals
of the libc. A quick Google search reveals that it has **lots** of similar
issues with all kinds of libc & kernel combinations, so even if I fix it on
my system, you may run into other problems on your system or with different
versions of packets. It even has different problems with different versions
of glibc. Projects like buildroot simply disable it when using musl. It "only"
provides a static code analysis plugin for the compiler.

The option **--with-native-system-header-dir** is of special interest for our
cross compiler. We explicitly tell it to look for headers in `/usr/include`,
relative to our **$SYSROOT** directory. We could just as easily place the
headers somewhere else in the previous steps and have it look there.

All that's left now is building and installing the compiler:

    make
    make install

    cd "$BUILDROOT"

This time, we are going to build and install *everything*. You *really* want to
do a parallel build here. On my AMD Ryzen based desktop PC, building with
`make -j 16` takes about 3 minutes. On my Intel i5 laptop it takes circa 15
minutes. If you are using a laptop, you might want to open a window (assuming
it is cold outside, i.e. won't help if you are in Taiwan).

### Testing the Toolchain

We quickly write our average hello world program into a file called **test.c**:

    #include <stdio.h>

    int main(void)
    {
        puts("Hello, world");
        return 0;
    }

We can now use our cross compiler to compile this C file:

    $ ${TARGET}-gcc test.c

Running the program `file` on the resulting `a.out` will tell us that it has
been properly compiled and linked for our target machine:

    $ file a.out
    a.out: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-musl-armhf.so.1, not stripped

Of course, you won't be able to run the program on your build system. You also
won't be able to run it on Raspbian or similar, because it has been linked
against our cross compiled Musl.

Statically linking it should solve the problem:

    $ ${TARGET}-gcc -static test.c
    $ file a.out
    a.out: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, with debug_info, not stripped
    $ readelf -d a.out

    There is no dynamic section in this file.

This binary now does not require any libraries, any interpreters and does
system calls directly. It should now run on your favourite Raspberry Pi
distribution as-is.
