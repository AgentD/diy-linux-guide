# Building a More Sophisticated Userspace

## Helper Functions

Because we are going to build a bunch of autotools based packages, I am going to
use two simple helper functions to make things a lot easier.

For simplicity, I added a script called `util.sh` that already contains those
functions. You can simply source it in your shell using `. <path>/util.sh`.

The first helper function runs the `configure` script for us with some
default options:

    run_configure() {
        "$srcdir/configure" --host="$TARGET" --prefix="" --sbindir=/bin \
                            --includedir=/usr/include --datarootdir=/usr/share\
                            --libexecdir=/lib/libexec --disable-static \
                            --enable-shared $@
    }

The host-touple is set to our target machine touple, the prefix is left empty,
which means install everything into `/` of our target filesystem.

In case the package wants to install programs into `/sbin`, we explicitly tell
it that sbin-programs go into `/bin`.

However, despite having `/` as our prefix, we want headers to go
into `/usr/include` and any possible data files into `/usr/share`.

If a package wants to install helper programs that are regular executables, but
not intended to be used by a user on the command line, those are usually
installed into a `libexec` sub directory. We explicitly tell the configure
script to install those in the historic `/lib/libexec` location instead of
clobbering the filesystem root with an extra directory.

The last two switches **--disable-static** and **--enable-shared** tell any
libtool based packages to prefer building shared libraries over static ones.

If a package doesn't use libtool and maybe doesn't even install libraries, it
will simply issue a warning that it doesn't know those switches, but will
otherwise ignore them and compile just fine.

The `$@` at the end basically paste any arguments passed to this function, so we
can still pass along package specific configure switches.

The second function encapsulates the entire dance for building a package that
we already did several times:

    auto_build() {
        local pkgname="$1"
        shift

        mkdir -p "$BUILDROOT/build/$pkgname"
        cd "$BUILDROOT/build/$pkgname"
        srcdir="$BUILDROOT/src/$pkgname"

        run_configure $@
        make -j `nproc`
        make DESTDIR="$SYSROOT" install
        cd "$BUILDROOT"
    }

The package name is specified as first argument, the remaining arguments are
passed to `run_configure`, again using `$@`. The `shift` command removes the
first argument, so we can do this without passing the package name along.

Another noticable difference is the usage of `nproc` to determine the number of
available CPU cores and pass it to `make -j` to speed up the build.

## About pkg-config and libtool

We will build a bunch of packages that either provide libraries, or depend on
libraries provided by other packages. This also means that the programs that
require libraries need a way to locate them, i.e. find out what compiler flags
to add in order to find the headers and what linker flags to add in order to
actually link against a library. Especially since a library may itself have
dependencies that the program needs to link against.

The [pkg-config program](https://en.wikipedia.org/wiki/Pkg-config) tries to
provide a unified solution for this problem. Packages that provide a library
can install a configuration file at a special location (in our
case `$SYSROOT/lib/pkgconfig`) and packages that need a library can
use `pkg-config` to query if the library is present, and what compiler/linker
flags are required to use it.

With most autotools based packages, this luckily isn't that much of an issue.
Most of them use standard macros for querying `pkg-config` that automagically
generate `configure` flags and variables that can be used to override the
results from `pkg-config`.

We are basically going to use the `pkg-config` version installed on our build
system and just need to set a few environment variables to instruct it to look
at the right place instead of the system defaults. The `util.sh` script also
sets those:

    export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
    export PKG_CONFIG_LIBDIR="$SYSROOT/lib/pkgconfig"
    export PKG_CONFIG_PATH="$SYSROOT/lib/pkgconfig"

The later two are actually *both* paths where `pkg-config` looks for its input
files, the LIBDIR has nothing to do with shared libraries. Setting
the `PKG_CONFIG_SYSROOT_DIR` variable instructs `pkg-config` to re-target any
paths it generates to point to the correct root filesystem directory.

The GNU `libtool` is a wrapper script for building shared libraries in an
autotools project and takes care of providing reasonable fallbacks on ancient
Unix systems where this works either qurky or not at all.

At the same time, it also tries to serve a similar purpose as `pkg-config` and
install libtool archives (with an `.la` file extension) to the `/lib`
directory. However, the way it does this is horribly broken and when using
`make install` with a `DESTDIR` argument, it will *always* store full path in
the `.la` file, which breaks the linking step of any other `libtool` based
package that happens to pick it up.

We will go with the easy solution and simply delete those files when they are
installed. Since we have `pkg-config` and a flat `/lib` directory, most
packages will find their libraries easily (except for `ncurses`, where,
historical reason, some programs stubbornly try their own way for).


## Building GNU Bash

In order to build Bash, we first build two support libraries: `ncurses`
and `readline`.

### Ncurses

The `ncurses` library is itself an extension/reimplementation of the `pcurses`
and `curses` libraries dating back to the System V and BSD era. At the time
that they were around, the landscape of terminals was much more diverse,
compared to nowadays, where everyone uses a different variant of Frankensteins
DEC VTxxx emulator.

As a result `curses` internally used the `termcap` library for handling terminal
escape codes, which was later replaced with `terminfo`. Both of those libraries
have their own configuration formats for storing terminal capabilities.

The `ncurses` library can work with both `termcap` and `terminfo` files and
thankfully provides the later for a huge number of terminals.

We can build ncurses as follows:

    auto_build "ncurses-6.2" --disable-stripping --with-shared --without-debug \
               --enable-pc-files --with-pkg-config-libdir=/lib/pkgconfig \
               --enable-widec --with-termlib

A few configure clutches are required, because it is one of those packages where
the maintainer tried to be clever and work around autotools semantics, so we
have to explicitly tell it to *not strip debug symbols* when installing the
binaries and explicitly tell it to generate shared libraries. We also need to
tell it to generate pkg-config files and where to put them.

If the **--disable-stripping** flag wasn't set, the `make install` would fail
later, because it would try to strip the debug information using the host
systems `strip` program, which will choke on the ARM binaries.

The **--enable-widec** flag instructs the build system to generate an `ncurses`
version with multi byte, wide character unicode support. The **--with-termlib**
switch instructs it to generate build the `terminfo` library as a separate
library instead of having it built into ncurses.

In addition to a bunch of libraries and header files, `ncurses` also installs
a few programs for handling `terminfo` files, such as the terminfo
compiler `tic` or the `tset` program for querying the database
(e.g. `tput reset` fully resets your terminal back into a sane state, in a way
that is supported by your terminal).

It also installs the terminal database files into `$SYSROOT/usr/share/terminfo`
and `$SYSROOT/usr/share/tabset`, as well as a hand full of man pages
to `$SYSROOT/usr/share/man`. For historical/backwards compatibillity reasons,
a symlink to the `terminfo` directory is also added to `$SYSROOT/lib`.

Because we installed the version with wide charater and unicode support, the
libraries that `ncurses` installs all have a `w` suffix at the end (as well as
the `pkg-config` files it installs), so it's particularly hard for other
programs to find the libraries.

So we add a bunch of symlinks for the programs that don't bother to check both:

    ln -s "$SYSROOT/lib/pkgconfig/formw.pc" "$SYSROOT/lib/pkgconfig/form.pc"
    ln -s "$SYSROOT/lib/pkgconfig/menuw.pc" "$SYSROOT/lib/pkgconfig/menu.pc"
    ln -s "$SYSROOT/lib/pkgconfig/ncursesw.pc" "$SYSROOT/lib/pkgconfig/ncurses.pc"
    ln -s "$SYSROOT/lib/pkgconfig/panelw.pc" "$SYSROOT/lib/pkgconfig/panel.pc"
    ln -s "$SYSROOT/lib/pkgconfig/tinfow.pc" "$SYSROOT/lib/pkgconfig/tinfo.pc"

In addition to `pkg-config` scripts, the `ncurses` package also provides a
shell script that tries to implement the same functionality.

Some packages (like `util-linux`) try to run that first and may accidentally
pick up a version you have installed on your host system.

So we copy that over from the `$SYSROOT/bin` directory to `$TCDIR/bin`:

    cp "$SYSROOT/bin/ncursesw6-config" "$TCDIR/bin/ncursesw6-config"
    cp "$SYSROOT/bin/ncursesw6-config" "$TCDIR/bin/$TARGET-ncursesw6-config"

### Readline

Having built the ncurses library, we can now build the `readline` library,
which implements a highly configurable command prompt with a search-able
history, auto completion and Emacs style key bindings.

Unlike `ncurses` that it is based on, it does not requires any special
configure flags:

    auto_build "readline-8.1"

It only installs the library (`libreadline` and `libhistory`) and headers
for the libraries, but no programs.

A bunch of documentation files are installed to `$SYSROOT/usr/share`, including
not only man pages, but info pages, plain text documentation in a `doc` sub
directory.

### Bash

For Bash itself, I used only two extra configure flags:

    auto_build "bash-5.1" --without-bash-malloc --with-installed-readline

The **--without-bash-malloc** flag tells it to use the standard `libc` malloc
instead of its own implementation and the **--with-installed-readline** flag
tells it to use the readline library that we just installed, instead of an
outdated, internal stub implementation.

The `make install` step installs bash to `$SYSROOT/bin/bash`, but also adds an
additional script `$SYSROOT/bin/bashbug` which is intended to report bugs you
may encounter back to the bash developers.

Bash has a plugin style support for builtin commands, which in can load as
libraries from a special directory (in our case `$SYSROOT/lib/bash`). So it will
install a ton of builtins there by default, as well as development headers
in `$SYSROOT/usr/include` that for third party packages that implement their own
builtins.

Just like readline, Bash brings along a bunch of documentation that it installs
to `$SYSROOT/usr/share`. Namely HTML documentation in `doc`, more info pages
and man pages.

Bash is also the first program we build that installs localized text messages
in the `$SYSROOT/usr/share/locale` directory.

Of course we are no where near done with Bash yet, as we still have some
plumbing to do regarding the bash start-up script, but we will get back to that
later when we put everything together.


## Basic Command Line Programs

### Basic GNU Packages

The standard comamnd line programs, such as `ls`, `cat`, `rm` and many more are
provided by the [GNU Core Utilities](https://www.gnu.org/software/coreutils/)
package.

It is fairly simple to build and install:

    auto_build "coreutils-8.32" --enable-single-binary=symlinks

The **--enable-single-binary** configure switch is a relatively recent feature
that instructs coreutils to build a single, monolithic binary in the same style
as BusyBox and install a bunch of symlinks to it, instead of installing dozens
of separate programs.

A few additional, very useful programs are provided by the [GNU diffutils](https://www.gnu.org/software/diffutils/)
and [GNU findutils](https://www.gnu.org/software/findutils/).

Namely, the diffutils provide `diff`, `patch` and `cmp`, while the findutils
provide `find`, `locate`, `updatedb` and `xargs`.

The GNU implementation of the `grep` program, as well as the `less` pager are
packaged separately.

All of those are relatively easy to build and install:

    auto_build "diffutils-3.7"
    auto_build "findutils-4.8.0"
    auto_build "grep-3.6"
    auto_build "less-563"

Again those packages also install a bunch of documentation in the `/usr/share`
directory in addition to the program binaries.

Coreutils installs a helper library in `$SYSROOT/lib/libexec/coretuils` and
findutils installs a libexec helper program as well (`frcode`).

The findutils package also creates an empty `$SYSROOT/var` directory, because
this is where `locate` expects to find a filesystem index database that can be
generated using `updatedb`.

### Sed and AWK

We have already used `sed`, the *stream editor* for simple file substitution
in the previous sections for building the kernel and BusyBox.

AWK is a much more advanced stream editing program that actually implements a
powerful scripting language for the purpose.

For both programs, we will use the GNU implementations (the GNU AWK
implementation is called `gawk`).

Both are fairly straight forward to build for our system:

    auto_build "sed-4.8"
    auto_build "gawk-5.1.0"

Again, we not only get the programs, but also a plethora of documentation and
extra files.

In fact, gawk will install an entire AWK library in `$SYSROOT/usr/share/awk` as
well as a number of plugin libraries in `$SYSROOT/lib/gawk`, some helper
programs in `$SYSROOT/lib/libexec/awk` and necessary development headers to
build external plugins.


### procps aka procps-ng

As the name suggests, the `procps` package supplies a few handy command line
programs for managing processes. More precisely, we install the following
list of programs:

 - `free`
 - `watch`
 - `w`
 - `vmstat`
 - `uptime`
 - `top`
 - `tload`
 - `sysctl`
 - `slabtop`
 - `pwdx`
 - `ps`
 - `pmap`
 - `pkill`
 - `pidof`
 - `pgrep`
 - `vmstat`

And their common helper library `libprocps.so` plus accompanying documentation.
The package would also supply the `kill` program, but we don't install that
here, sine it is also provided by the `util-linux` package and the later has a
few extra features.

Sadly, we don't get a propper release tarball for `procps`, but only a dump from
the git repository. Because the `configure` script and Makefile templates are
generated by autoconf and automake, they are not checked into the repository.

Many autotools based projects have a `autogen.sh` scrip that checks for the
required tools and takes care of generating the actual build system from the
configuration.

So the frist thing we do, is goto into the `procps` source tree and generate
the build system ourselves:

    cd "$BUILDROOT/src/procps-v3.3.16"
    ./autogen.sh
    cd "$BUILDROOT"

Now, we can build `procps`:

    export ac_cv_func_malloc_0_nonnull=yes
    export ac_cv_func_realloc_0_nonnull=yes
    auto_build "procps-v3.3.16" --enable-watch8bit --disable-kill --with-gnu-ld

As you can see, some clutches are required here. First of all, the configure
script attempts to find out if `malloc(0)` and `realloc(0)` return NULL or
something else.

Technically, when trying to allocate 0 bytes of memory, the C standard permits
the standard library to return a `NULL` pointer instead of a valid pointer to
some place in memory. Some libraries like the widely used `glibc` opted to
instead return a valid point. Many programs pass a programatically generated
size to `malloc` and assume that `NULL` means "out of memory" or similar
dramatic failure, especially if `glibc` behaviour encourages this.

Instead of fixing this, some programs instead decided to add a compile time
check and add a wrappers for `malloc`, `realloc` and `free` if it
returns `NULL`. Since we are cross compiling, this check cannot be run. So
we set the result variables manually, the `configure` script "sees" that and
skips the check.

The `--enable-watch8bit` flag enables propper UTF-8 support for the `watch`
program, for which it requires `ncursesw` instead of regular `ncurses` (but
ironically this is one of the packages that fails without the symlink
of `ncurses` to `ncursesw`).

The other flag `--disable-kill` compiles the package without the `kill` program
for the reasons stated above and the final flag `--with-gnu-ld` tells it that
the linker is the GNU version of `ld` which it, by default, assumes to not be
the case.


### psmisc

The `psmisc` package contains a hand full of extra programs for process
management that aren't already in `procps`, namely it contains `fuser`,
`killall`, `peekfd`, `prtstat` and `pstree`.

Similar to `procps`, we need to generate the build system ourselves, but we will
also take the opertunity to apply some changes using `sed`:

    cd "$BUILDROOT/src/psmisc-v22.21"
    sed -i 's/ncurses/ncursesw/g' configure.ac
    sed -i 's/tinfo/tinfow/g' configure.ac
    sed -i "s#./configure \"\$@\"##" autogen.sh
    ./autogen.sh
    cd "$BUILDROOT"

The frist two `sed` lines patch the configure script to try `ncursesw`
and `tinfow` instead of `ncruses` and `tinfo` respectively.

The third `sed` line makes sure that the `autogen.sh` _does not_ run the
configure script once it is done.

With that done, we can now build `psmisc` with largely the similar fixes:

    export ac_cv_func_malloc_0_nonnull=yes
    export ac_cv_func_realloc_0_nonnull=yes
    export CFLAGS="-O2 -include limits.h -include sys/sysmacros.h"
    auto_build "psmisc-v22.21"

The first two are explained in the `procps` build, the final `export CFLAGS`
line passes some additional flags to the C compiler. The underlying problem
is that this release of `psmisc` uses the `PATH_MAX` macro from `limits.h`
in some places and the `makedev` macro from `sys/sysmacros.h`, but includes
neither of those headers. This works for them, because `glibc` includes those
from other headers that they include, but `musl` doesn't. Using the `-incldue`
option, we force `gcc` to include those headers before processign any C file.

When you are don with this, don't forget to

    unset CFLAGS

Lastly, we get rid of the `libtool` archive installed by `procps`:

    rm "$SYSROOT/lib/libprocps.la"

### The GNU nano text editor

GNU nano is an `ncurses` based text editor that is fairly user friendly and
installed by default on many Debian based distributions. Being a GNU program,
it knows how to use autotools and is fairly simple to build and install:

    auto_build "nano-5.6.1"

Along with the program itself it also installs a lot of scripts for syntax
highlighting. There is not much more to say here, other than maybe that it
has an easter egg, that we could disable through a `configure` flag.


## Archival and Compression Programs

### GNU tar and friends

On Unix-like systems `tar`, the **t**ape **ar**chive program, is
basically *the standard* archival program.

The tar format itself is dead simple. Files are simply glued together with
a 512 byte header in front of every file and null bytes at the end to round
it up to a multiple of 512 bytes. Directories and the like simply use a single
header with no content following. This is also the reason why you can't create
an empty tar file: it would simply be an empty file. Also, tarballs have no
index. You cannot do random access and in order to unpack a single file,
the `tar` program has to scan across the entire file.

Tar itself doesn't do compression. When you see a compressed tarball, such
as a `*.tar.gz` file, it has been fed through a compression program like `gzip`
and must be uncompressed before the `tar` program can handle it. Programs
like `gzip` only do compression of individual files and have no idea what they
process. As a result, `gzip` will compress across tar headers and you really
need to unpack and scan the entire thing when you want to unpack a single file.

The `tar` program *can* actually work with compressed tar archives, but what
it does (or at least what GNU tar does) internally is, checking at run time if
the compressor program is available and starting it as a child process that it
through which it feeds the data.

Compression formats typically used together with `tar` are `xz`, `gzip`
and `bzip2`. Nowadays `Zstd` is also slowly gaining adoption.

The xz-uilities, GNU gzip and GNU tar are fairly simple to build, since they
all use the GNU build system:

    auto_build "xz-5.2.5"
    auto_build "gzip-1.10"
    auto_build "tar-1.34"

Of course, they will also install development headers, libraries, a bunch of
wrapper shell script that allow using `grep`, `less` or `diff` on compressed
files, and a lot of documentation.

The `xz` package installs a `libtool` archive that we simply remove:

    rm "$SYSROOT/lib/liblzma.la"

The GNU tar package also installs a `libexec` helper called `rmt`,
the **r**e**m**ote **t**ape drive server.


Of course, the `bzip2` program is a bit more involved, since it uses a custom
Makefile.

We first setup our build directory in the usual way:

    mkdir -p "$BUILDROOT/build/bzip2-1.0.8"
    cd "$BUILDROOT/build/bzip2-1.0.8"
    srcdir="$BUILDROOT/src/bzip2-1.0.8"

Then we copy over the source files:

    cp "$srcdir"/*.c .
    cp "$srcdir"/*.h .
	cp "$srcdir"/words* .
    cp "$srcdir/Makefile" .

We manually compile the Makefile targets that we are interested in:

    make CFLAGS="-Wall -Winline -O2 -D_FILE_OFFSET_BITS=64 -O2 -Os" \
         CC=${TARGET}-gcc AR=${TARGET}-ar \
         RANLIB=${TARGET}-ranlib libbz2.a bzip2 bzip2recover

The compiler, archive tool `ar` for building static libraries, and `ranlib`
(indexing tool for static libraries) are manually specified on the command
line.

We copy the programs, library and header over manually:

    cp bzip2 "$SYSROOT/bin"
    cp bzip2recover "$SYSROOT/bin"
    cp libbz2.a "$SYSROOT/lib"
    cp bzlib.h "$SYSROOT/usr/include"
    ln -s bzip2 "$SYSROOT/bin/bunzip2"
    ln -s bzip2 "$SYSROOT/bin/bzcat"

The symlinks `bunzip2` and `bzcat` both point to the `bzip2` binary which
when run deduces from the path that it should act as a decompression tool
instead.

Bzip2 also provides a bunch of wrapper scripts like gzip and xz:

    cp "$srcdir/bzdiff" "$SYSROOT/bin"
    cp "$srcdir/bzdiff" "$SYSROOT/bin"
    cp "$srcdir/bzmore" "$SYSROOT/bin"
    cp "$srcdir/bzgrep" "$SYSROOT/bin"
    ln -s bzgrep "$SYSROOT/bin/bzegrep"
    ln -s bzgrep "$SYSROOT/bin/bzfgrep"
    ln -s bzmore "$SYSROOT/bin/bzless"
    ln -s bzdiff "$SYSROOT/bin/bzcmp"
    cd "$BUILDROOT"


### Zlib

Zlib is a library that implements the deflate compression algorithm that is used
for data compression in formats like `gzip` or `zip` (and thanks to `zlib` also
in a bunch of other formats).

In case you are wondering why we install `zlib` this after `gzip` if it uses the
same base compression algorithm: the later has it's own implmentation and won't
benefit from an installed version of zlib.

Because `zlib` also rolls it's own configure script, we do the same dance again
with copying the required stuff over into our build directory:

    mkdir -p "$BUILDROOT/build/zlib-1.2.11"
    cd "$BUILDROOT/build/zlib-1.2.11"
    srcdir="$BUILDROOT/src/zlib-1.2.11"

    cp "$srcdir"/*.c "$srcdir"/*.h "$srcdir"/zlib.pc.in .
    cp "$srcdir"/configure "$srcdir"/Makefile* .

We can then proceed to cross compile the static `libz.a` library:

    CROSS_PREFIX="${TARGET}-" prefix="/usr" ./configure
    make libz.a

The target is named explicitly here, because by default the `Makefile` would
try to compile a couple test programs as well.

With everything compiled, we can then copy the result over into our
sysroot directory and go back to the build root:

    cp libz.a "$SYSROOT/usr/lib/"
    cp zlib.h "$SYSROOT/usr/include/"
    cp zconf.h "$SYSROOT/usr/include/"
    cp zlib.pc "$SYSROOT/usr/lib/pkgconfig/"
	cd "$BUILDROOT"


## Miscellaneous

### The file program

The `file` command line program can magically identify and describe tons of
file types. The core functionallity is actually implemented in a library
called `libmagic` that comes with a data base of magic numbers.

There is one little quirk tough, in order to cross compile `file`, we need
the same version of `file` already installed, so it can build the magic data
base.

So first, we manually compile `file` and install it in our toolchain directory:

    srcdir="$BUILDROOT/src/file-5.40"
    mkdir -p "$BUILDROOT/build/file-host"
    cd "$BUILDROOT/build/file-host"

    unset PKG_CONFIG_SYSROOT_DIR
    unset PKG_CONFIG_LIBDIR
    unset PKG_CONFIG_PATH

    $srcdir/configure --prefix="$TCDIR" --build="$HOST" --host="$HOST"
    make
    make install

At this point, it should be fairly straight forward to understand what this
does. The 3 `unset` lines revert the `pkg-config` paths so that we can propperly
link it against our host libraries.

After that, we of course need to reset the `pkg-config` exports:

    export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
    export PKG_CONFIG_LIBDIR="$SYSROOT/lib/pkgconfig"
    export PKG_CONFIG_PATH="$SYSROOT/lib/pkgconfig"

After that, we can simply install `file`, `libmagic` and the data base:

    auto_build "file-5.40"

Of course, `libmagic` installs a `libtool` archive, so we delete that:

    rm "$SYSROOT/lib/libmagic.la"

The reason for building this after all the other tools is that `file` can make
use of the compressor libraries we installed previously to peek into compressed
files, so for instance, it can identify a gzip compressed tarball as such
instead of telling you it's a gzip compressed whatever.

### The util-linux collection

The `util-linux` pacakge contains a large collection of command line tools that
implement Linux specific functionallity that is missing from more generic
collections like the GNU core utilities. Among them are essentials like
the `mount` program, loop back device control or `rfkill`. I won't list all of
them, since we individually enable them throught he `configure` script, so a you
can see a detailed list below.

The package can easily be built with our autotools helper:

    auto_build "util-linux-2.36" --without-systemd --without-udev \
        --disable-all-programs --disable-bash-completion --disable-pylibmount \
        --disable-makeinstall-setuid --disable-makeinstall-chown \
        --enable-mount --enable-losetup --enable-fsck --enable-mountpoint \
        --enable-fallocate --enable-unshare --enable-nsenter \
        --enable-hardlink --enable-eject --enable-agetty --enable-wdctl \
        --enable-cal --enable-switch_root --enable-pivot_root \
        --enable-lsmem --enable-ipcrm --enable-ipcs --enable-irqtop \
        --enable-lsirq --enable-rfkill --enable-kill --enable-last \
        --enable-mesg --enable-raw --enable-rename --enable-ul --enable-more \
        --enable-setterm --enable-libmount --enable-libblkid --enable-libuuid \
        --enable-libsmartcols --enable-libfdisk

As mentioned before, the lengthy list of `--enable-<foo>` is only there because
of the `--disable-all-programs` switch that turns everything off that we don't
excplicitly enable.

Among the things we skip are programs like `login` or `su` that handle user
authentication. However, the `agetty` program which implements the typical
terminal login promt is explicitly enabled. We will get back to that later
on, when setting up an init system and `shadow-utils` for the user
authentication.

After the build is done, some cleanup steps need to be taken care of:

    mv "$SYSROOT"/sbin/* "$SYSROOT/bin"
    rm "$SYSROOT/lib"/*.la
    rmdir "$SYSROOT/sbin"

Even when configuring util-linux to install into `/bin` instead of `/sbin`,
it will still stubbornly install `rfkill` into `/sbin`.

The `*.la` files that are removed are from the helper libraries `libblkid.so`,
`libsmartcols.so`, `libuuid.so` and`libfdisk.so`.


## Cleaning up

A signifficant portion of the compiled binaries consists of debugging symbols
that a can easily be removed using a strip command.

The following command line uses the `find` command to locate all regular
files `-type f`, i.e. it won't print symlinks or directories and for each of
them runs the `file` command to identify their file type. The list is fed
through `grep ELF` to filter out the ones identified as ELF files (because
there are also some shell scripts in there, which we obviously can't strip)
and then fed through`'sed` to remove the `: ELF...` description.

The resulting list of excutable files is then passed on to the `${TARGET}-strip`
program from our toolchain using `xargs`:

    find "$SYSROOT/bin" -type f -exec file '{}' \; | \
    grep ELF | sed 's/: ELF.*$//' | xargs ${TARGET}-strip -xs

On my Fedora system, this drastically cuts the size of the `/bin` directory
from ~67.5 MiB (28,595,781 bytes) down to ~7 MiB (7,346,105 bytes).

We do the same thing a second time for the `/lib` directory. Please note the
extra argument `! -path '*/lib/modules/*'` for the `find` command to make sure
we skip the kernel modules.

    find "$SYSROOT/lib" -type f ! -path '*/lib/modules/*' -exec file '{}' \; |\
    grep ELF | sed 's/: ELF.*$//' | xargs ${TARGET}-strip -xs

On my system, this reduces the size of the `/lib` directory
from ~67 MiB (70,574,158 bytes) to ~60 MiB (63,604,818 bytes).

If you are the kind of person who loves to ramble about "those pesky shared
libraries" and insist on statically linking everything, you should take a look
of what uses up that much space:

The largest chunk of the `/lib` directory, is kernel modules. On my system
those make up ~54.5 MiB (57,114,381 bytes) of the two numbers above. So if you
are bent on cutting the size down, you should start by tossing out modules you
don't need.


## Packing into a SquashFS Filesystem

SquashFS is a highly compressed, read-only filesystem that is packed offline
into an archive that can than be mounted by Linux.

Besides the high compression, which drastically reduces the on-disk memory
footprint, being immutable and read-only has a number of advantages in itself.
Our system will stay in a well defined state and the lack of write operations
reduces wear on the SD card. Writable directories (e.g. for temporary files
in `/tmp` or for things like log files that you actually want to write) are
typically achieved by mounting another filesystem to a directory on the
SquashFS root (e.g. from another SD card partition, or simply mounting
a `tmpfs`).

This can also be combined with an `overlayfs`, where a directory on the
SquashFS can be merged with a directory from a writable filesystem. Any changes
to existing files are implemented by transparentyl copying the file to the
writable filesystem first and editing it there. Erasing the writable directory
essentially causes a "factory reset" to the initial content.

We will revisit this topic later on, for now we are just interested in packing
the filesystem and testing it out.

For packing a SquashFS image, we use [squashfs-tools-ng](https://github.com/AgentD/squashfs-tools-ng).

The reason for using `squashfs-tools-ng` is that it contains a handy tool
called `gensquashfs` that takes an input listing similar to `gen_init_cpio`.

On some systems, you can just install it from the package repository. But be
aware that I'm going to use a few features that were introduced in version 1.1,
which currently isn't packaged on some systems.

If you are building the package yourself, you need the devlopment packages for
at least one of the compressors that SquashFS supports (e.g. xz-utils or Zstd).

Because we compile a host tool again, we need to unset the `pkg-config` path
variables first:

    unset PKG_CONFIG_SYSROOT_DIR
    unset PKG_CONFIG_LIBDIR
    unset PKG_CONFIG_PATH

We build the package the same way as other host tools and install it into
the toolchain directory:

    srcdir="$BUILDROOT/src/squashfs-tools-ng-1.1.0"
    mkdir -p "$BUILDROOT/build/squashfs-tools-ng-1.1.0"

    cd "$BUILDROOT/build/squashfs-tools-ng-1.1.0"
    $srcdir/configure --prefix=$TCDIR --host=$HOST --build=$HOST

    make
    make install
    cd "$BUILDROOT"

The listing file for the SquashFS archive is a little bit longer than the
one for the initital ramfs. I included [a prepared version](list.txt).

If you examine the list, you will find that many files of the sysroot aren't
packed. Specifically the header files, man pages (plus other documentation)
and static libraries. The development files are omitted, because without
development tools (e.g. gcc, ...) they are useless on the target system.
Likewise, we don't have any tools yet to actually view the documentation files.
Omitting those safes us some space.

Using the listing, we can pack the root filesystem using `gensquashfs`:

    gensquashfs --pack-dir "$SYSROOT" --pack-file list.txt -f rootfs.sqfs


On my system, the resulting archive is ~18.3 MiB in size (19,238,912 bytes).

For comparison, I also tried the unstripped binaries, resuling in a SquashFS
archive of ~26.7 MiB (27,971,584 bytes) and packing without any kernel modules,
resulting in only ~4.4 MiB (4,583,424 bytes).


## Testing it on Hardware

First of, we will revise the `/init` script of our initial ram filesystem as
follows:

    cd "$BUILDROOT/build/initramfs"

    cat > init <<_EOF
    #!/bin/sh

    PATH=/bin

    /bin/busybox --install
    /bin/busybox mount -t proc none /proc
    /bin/busybox mount -t sysfs none /sys
    /bin/busybox mount -t devtmpfs none /dev

    boot_part="mmcblk0p1"
    root_sfs="rootfs.sqfs"

    while [ ! -e "/dev/$boot_part" ]; do
        echo "Waiting for device $boot_part"
        busybox sleep 1
    done

    mount "/dev/$boot_part" "/boot"

    if [ ! -e "/boot/${root_sfs}" ]; then
        echo "${root_sfs} not found!"
        exec /bin/busybox sh
        exit 1
    fi

    mount -t squashfs /boot/${root_sfs} /newroot
    umount -l /boot

    umount -l /dev
    umount /sys
    umount /proc

    unset -v root_sfs boot_part

    exec /bin/busybox switch_root /newroot /bin/bash
    _EOF

This new init script starts out pretty much the same way, but instead of
dropping directly into a `busybox` shell, we first mount the primrary
partition of the SD card (in my case `/dev/mmcblk0p1`) to `/boot`.

As the device node may not be present yet in the `/dev` filesystem, we wait
in a loop for it to pop up.

From the SD card, we then mount the `rootfs.sqfs` that we just generated,
to `/newroot`. There is a bit of trickery involved here, because traditional,
Unix-like operating systems can only mount devices directly. The mount point
has a filesystem driver associated with it, and an underlying device number.
In order to mount an archive from a file, Linux has a loop back block device,
which works like a regular block device, but reflects read/write access back
to an existing file in the filesystem. The `mount` command transparently takes
care of setting up the loop device for us, and then actually.

After that comes a bit of a mind screw. We cleanup after ourselves, i.e. unset
the environment variables, but also unmount everything, *including* the `/boot`
directory, from which the SquashFS archive was mounted.

Note the `-l` parameter for the mount, which means *lazy*. The kernel detaches
the filesystem from the hierarchy, but keeps it open until the last reference
is removed (in our case, held by the loop back block device).

The final `switch_root` works somewhat similar to a `chroot`, except that it
actually does change the underlying mountpoints and also gets rid of the
initial ram filesystem for us.

After extending the init script, we can rebuild the initramfs:

    ./gen_init_cpio initramfs.files | xz --check=crc32 > initramfs.xz
    cp initramfs.xz "$SYSROOT/boot"
    cd "$BUILDROOT"

We, again, copy everything over to the SD card (don't forget the rootfs.sqfs)
and boot up the Raspberry Pi.

This should now drop you directly into a `bash` shell on the SquashFS image.

If you try to run certain commands like `mount`, keep in mind that `/proc`
and `/sys` aren't mounted, causing the resulting error messages. But if you
manually mount them again, everything should be fine again.
