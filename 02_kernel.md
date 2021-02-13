# Building a Bootable Kernel and Initial RAM Filesystem

This section outlines how to use the cross compiler toolchain you just built
for cross-compiling a bootable kernel, and how to get the kernel to run on
the Raspberry Pi.

## The Linux Boot Process at a High Level

When your system is powered on, it usually won't run the Linux kernel directly.
Even on a very tiny embedded board that has the kernel baked into a flash
memory soldered directly next to the CPU. Instead, a chain of boot loaders will
spring into action that do basic board bring-up and initialization. Part of this
chain is typically comprised of proprietary blobs from the CPU or board vendor
that considers hardware initialization as a mystical secret that must not be
shared. Each part of the boot loader chain is typically very restricted in what
it can do, hence the need to chain load a more complex loader after doing some
hardware initialization.

The chain of boot loaders typically starts with some mask ROM baked into the
CPU and ends with something like [U-Boot](https://www.denx.de/wiki/U-Boot),
[BareBox](https://www.barebox.org/), or in the case of an x86 system like your
PC, [Syslinux](https://syslinux.org/) or (rarely outside of the PC world)
[GNU GRUB](https://www.gnu.org/software/grub/).

The final stage boot loader then takes care of loading the Linux kernel into
memory and executing it. The boot loader typically generates some informational
data structures in memory and passes a pointer to the kernel boot code. Besides
system information (e.g. RAM layout), this typically also contains a command
line for the kernel.

On a very high level, after the boot loader jumps into the kernel, the kernel
decompresses itself and does some internal initialization, initializes built-in
hardware drivers and then attempts to mount the root filesystem. After mounting
the root filesystem, the kernel creates the very first process with PID 1.

At this point, boot strapping is done as far as the kernel is concerned. The
process with PID 1 usually spawns (i.e. `fork` + `exec`) and manages a bunch
of daemon processes. Some of them allowing users to log in and get a shell.

### Initial RAM Filesystem

For very simple setups, it can be sufficient to pass a command line option to
the kernel that tells it what device to mount for the root filesystem. For more
complex setups, Linux supports mounting an *initial RAM filesystem*.

This basically means that in addition to the kernel, the boot loader loads
a compressed archive into memory. Along with the kernel command line, the boot
loader gives the kernel a pointer to archive start in memory.

The kernel then mounts an in-memory filesystem as root filesystem, unpacks the
archive into it and runs the PID 1 process from there. Typically this is a
script or program that then does a more complex mount setup, transitions to
the actual root file system and does an `exec` to start the actual PID 1
process. If it fails at some point, it usually drops you into a tiny rescue
shell that is also packed into the archive.

For historical reasons, Linux uses [cpio](https://en.wikipedia.org/wiki/Cpio)
archives for the initial ram filesystem.

Systems typically use [BusyBox](https://busybox.net/) as a tiny shell
interpreter. BusyBox is a collection of tiny command line programs that
implement basic commands available on Unix-like system, ranging from `echo`
or `cat` all the way to a small `vi` and `sed` implementation and including
two different shell implementations to choose from.

BusyBox gets compiled into a single, monolithic binary. For the utility
programs, symlinks or hard links are created that point to the binary.
BusyBox, when run, will determine what utility to execute from the path
through which it has been started.

**NOTE**: The initial RAM filesystem, or **initramfs** should not be confused
with the older concept of an initial RAM disk, or **initrd**. The initial RAM
disk actually uses a disk image instead of an archive and the kernel internally
emulates a block device that reads blocks from RAM. A regular filesystem driver
is used to mount the RAM backed block device as root filesystem.

### Device Tree

On a typical x86 PC, your hardware devices are attached to the PCI bus and the
kernel can easily scan it to find everything. The devices have nice IDs that
the kernel can query and the drivers tell the kernel what IDs that they can
handle.

On embedded machines running e.g. ARM based SoCs, the situation is a bit
different. The various SoC vendors buy licenses for all the hardware "IP cores",
slap them together and multiplex them onto the CPU cores memory bus. The
hardware registers end up mapped to SoC specific memory locations and there is
no real way to scan for possibly present hardware.

In the past, Linux had something called "board files" that where SoC specific
C files containing SoC & board specific initialization code, but this was
considered too inflexible.

Linux eventually adopted the concept of a device tree binary, which is
basically a binary blob that hierarchically describes the hardware present on
the system and how the kernel can interface with it.

The boot loader loads the device tree into memory and tells the kernel where it
is, just like it already does for the initial ramfs and command line.

In theory, a kernel binary can now be started on a number of different boards
with the same CPU architecture, without recompiling (assuming it has all the
drivers). It just needs the correct device tree binary for the board.

The device tree binary (dtb) itself is generated from a number of source
files (dts) located in the kernel source tree under `arch/<cpu>/boot/dts`.
They are compiled together with the kernel using a device tree compiler that
is also part of the kernel source.

On a side note, the device tree format originates from the BIOS equivalent
of SPARC workstations. The format is now standardized through a specification
provided by the Open Firmware project and Linux considers it part of its ABI,
i.e. a newer kernel should *always* work with an older DTB file.

## Overview

In this section, we will cross compile BusyBox, build a small initial ramfs,
cross compile the kernel and get all of this to run on the Raspberry Pi.

Unless you have used the `download.sh` script from [the cross toolchain](01_crosscc.md),
you will need to download and unpack the following:

* [BusyBox](https://busybox.net/downloads/busybox-1.32.1.tar.bz2)
* [Linux](https://github.com/raspberrypi/linux/archive/raspberrypi-kernel_1.20201201-1.tar.gz)

You should still have the following environment variables set from building the
cross toolchain:

    BUILDROOT=$(pwd)
    TCDIR="$BUILDROOT/toolchain"
    SYSROOT="$BUILDROOT/sysroot"
    TARGET="arm-linux-musleabihf"
	HOST="x86_64-linux-gnu"
    LINUX_ARCH="arm"
    export PATH="$TCDIR/bin:$PATH"


## Building BusyBox

The BusyBox build system is basically the same as the Linux kernel build system
that we already used for [building a cross toolchain](01_crosscc.md).

Just like the kernel (which we haven't built yet), BusyBox uses has a
configuration file that contains a list of key-value pairs for enabling and
tuning features.

I prepared a file `bbstatic.config` with the configuration that I used. I
disabled a lot of stuff that we don't need inside an initramfs, but most
importantly, I changed the following settings:

 - **CONFIG_INSTALL_NO_USR** set to yes, so BusyBox creates a flat hierarchy
   when installing itself.
 - **CONFIG_STATIC** set to yes, so BusyBox is statically linked and we don't
   need to pack any libraries or a loader into our initramfs.

If you want to customize my configuration, copy it into a freshly extracted
BusyBox tarball, rename it to `.config` and run the menuconfig target:

    mv bbstatic.config .config
    make menuconfig

The `menuconfig` target builds and runs an ncurses based dialog that lets you
browse and configure features.

Alternatively you can start from scratch by creating a default configuration:

    make defconfig
    make menuconfig

To compile BusyBox, we'll first do the usual setup for the out-of-tree build:

    srcdir="$BUILDROOT/src/busybox-1.32.1"
    export KBUILD_OUTPUT="$BUILDROOT/build/bbstatic"

    mkdir -p "$KBUILD_OUTPUT"
    cd "$KBUILD_OUTPUT"

At this point, you have to copy the BusyBox configuration into the build
directory. Either use your own, or copy my `bbstatic.config` over, and rename
it to `.config`.

By running `make oldconfig`, we let the buildsystem sanity check the config
file and have it ask what to do if any option is missing.

    make -C "$srcdir" CROSS_COMPILE="${TARGET}-" oldconfig

We need to edit 2 settings in the config file: The path to the sysroot and
the prefix for the cross compiler executables. This can be done easily with
two lines of `sed`:

    sed -i "$KBUILD_OUTPUT/.config" -e 's,^CONFIG_CROSS_COMPILE=.*,CONFIG_CROSS_COMPILE="'$TARGET'-",'
    sed -i "$KBUILD_OUTPUT/.config" -e 's,^CONFIG_SYSROOT=.*,CONFIG_SYSROOT="'$SYSROOT'",'

What is now left is to compile BusyBox.

    make -C "$srcdir" CROSS_COMPILE="${TARGET}-"

Before returning to the build root directory, I installed the resulting binary
to the sysroot directory as `bbstatic`.

    cp busybox "$SYSROOT/bin/bbstatic"
    cd "$BUILDROOT"

## Compiling the Kernel

First, we do the same dance again for the kernel out of tree build:

    srcdir="$BUILDROOT/src/linux-raspberrypi-kernel_1.20201201-1"
    export KBUILD_OUTPUT="$BUILDROOT/build/linux"

    mkdir -p "$KBUILD_OUTPUT"
    cd "$KBUILD_OUTPUT"

I provided a configuration file in `linux.config` which you can simply copy
to `$KBUILD_OUTPUT/.config`.

Or you can do the same as I did and start out by initializing a default
configuration for the Raspberry Pi and customizing it:

    make -C "$srcdir" ARCH="$LINUX_ARCH" bcm2709_defconfig
    make -C "$srcdir" ARCH="$LINUX_ARCH" menuconfig

I mainly changed **CONFIG_SQUASHFS** and **CONFIG_OVERLAY_FS**, turning them
both from `<M>` to `<*>`, so they get built in instead of being built as
modules.

Hint: you can also search for things in the menu config by typing `/` and then
browsing through the popup dialog. Pressing the number printed next to any
entry brings you directly to the option. Be aware that names in the menu
generally don't contain **CONFIG_**.

Same as with BusyBox, we insert the cross compile prefix into the configuration
file:

    sed -i "$KBUILD_OUTPUT/.config" -e 's,^CONFIG_CROSS_COMPILE=.*,CONFIG_CROSS_COMPILE="'$TARGET'-",'

And then finally build the kernel:

    make -C "$srcdir" ARCH="$LINUX_ARCH" CROSS_COMPILE="${TARGET}-" oldconfig
    make -C "$srcdir" ARCH="$LINUX_ARCH" CROSS_COMPILE="${TARGET}-" zImage dtbs modules

The `oldconfig` target does the same as on BusyBox. More intersting are the
three make targets in the second line. The `zImage` target is the compressed
kernel binary, the `dtbs` target builds the device tree binaries and `modules`
are the loadable kernel modules (i.e. drivers). You really want to insert
a `-j NUMBER_OF_JOBS` in the second line, or it may take a considerable amount
of time.

Also, you *really* want to specify an argument after `-j`, otherwise the kernel
build system will spawn processes until kingdome come (i.e. until your system
runs out of resources and the OOM killer steps in).

Lastly, I installed all of it into the sysroot for convenience:

    mkdir -p "$SYSROOT/boot"
    cp arch/arm/boot/zImage "$SYSROOT/boot"
    cp -r arch/arm/boot/dts "$SYSROOT/boot"

    make -C "$srcdir" ARCH="$LINUX_ARCH" CROSS_COMPILE="${TARGET}-" INSTALL_MOD_PATH="$SYSROOT" modules_install
    cd $BUILDROOT

The `modules_install` target creates a directory hierarchy `sysroot/lib/modules`
containing a sub directory for each kernel version with the kernel modules and
dependency information.

The kernel binary will be circa 6 MiB in size and produce another circa 55 MiB
worth of modules because the Raspberry Pi default configuration has all bells
and whistles turned on. Fell free to adjust the kernel configuration and throw
out everything you don't need.

## Building an Inital RAM Filesystem

First of all, although we do everything by hand here, we are going to create a
build directory to keep everything neatly separated:

    mkdir -p "$BUILDROOT/build/initramfs"
	cd "$BUILDROOT/build/initramfs"

Technically, the initramfs image is a simple cpio archive. However, there are
some pitfalls here:

* There are various versions of the cpio format, some binary, some text based.
* The `cpio` command line tool is utterly horrible to use.
* Technically, the POSIX standard considers it lagacy. See the big fat warning
  in the man page.

So instead of the `cpio` tool, we are going to use a tool from the Linux kernel
tree called `gen_init_cpio`:

    gcc "$BUILDROOT/src/linux-raspberrypi-kernel_1.20201201-1/usr/gen_init_cpio.c" -o gen_init_cpio

This tool allows us to create a cpio image from a very simple file listing and
produces exactely the format that the kernel understands.

Here is the simple file listing that I used:

    cat > initramfs.files <<_EOF
    dir boot 0755 0 0
    dir dev 0755 0 0
    dir lib 0755 0 0
    dir bin 0755 0 0
    dir sys 0755 0 0
    dir proc 0755 0 0
    dir newroot 0755 0 0
    slink sbin bin 0777 0 0
    nod dev/console 0600 0 0 c 5 1
    file bin/busybox $SYSROOT/bin/bbstatic 0755 0 0
    slink bin/sh /bin/busybox 0777 0 0
    file init $BUILDROOT/build/initramfs/init 0755 0 0
    _EOF

In case you are wondering about the first and last line, this is called a
[heredoc](https://en.wikipedia.org/wiki/Here_document) and can be copy/pasted
into the shell as is.

The format itself is actually pretty self explantory. The `dir` lines are
directories that we want in our archive with the permission and ownership
information after the name. The `slink` entry creates a symlink, namely
redirecting `/sbin` to `/bin`.

The `nod` entry creates a devices file. In this case, a character
device (hence `c`) with device number `5:1`. Just like how symlinks are special
files that have a target string stored in them and get special treatment from
the kernel, a device file is also just a special kind of file that has a device
number stored in it. When a program opens a device file, the kernel maps the
device number to a driver and redirects file I/O to that driver.

This decice number `5:1` refers to a special text console on which the kernel
prints out messages during boot. BusyBox will use this as standard input/output
for the shell.

Next, we actually pack our statically linked BusyBox, into the archive, but
under the name `/bin/busybox`. We then create a symlink to it, called `bin/sh`.

The last line packs a script called `init` (which we haven't written yet) into
the archive as `/init`.

The script called `/init` is what we later want the kernel to run as PID 1
process. For the moment, there is not much to do and all we want is to get
a shell when we power up our Raspberry Pi, so we start out with this stup
script:

    cat > init <<_EOF
    #!/bin/sh

    PATH=/bin

    /bin/busybox --install
    /bin/busybox mount -t proc none /proc
    /bin/busybox mount -t sysfs none /sys
    /bin/busybox mount -t devtmpfs none /dev

    exec /bin/busybox sh
    _EOF

Running `busybox --install` will cause BusyBox to install tons of symlinks to
itself in the `/bin` directory, one for each utility program. The next three
lines run the `mount` utiltiy of BusyBox to mount the following pseudo
filesystems:

* `proc`, the process information filesystem which maps processes and other
  various kernel variables to a directory hierchy. It is mounted to `/proc`.
  See `man 5 proc` for more information.
* `sysfs` a more generic, cleaner variant than `proc` for exposing kernel
  objects to user space as a filesystem hierarchy. It is mounted to `/sys`.
  See `man 5 sysfs` for more information.
* `devtmpfs` is a pseudo filesystem that takes care of managing device files
  for us. We mount it over `/dev`.

We can now finally put everything together into an XZ compressed archive:

    ./gen_init_cpio initramfs.files | xz --check=crc32 > initramfs.xz
    cp initramfs.xz "$SYSROOT/boot"
    cd "$BUILDROOT"

The option `--check=crc32` forces the `xz` utility to create CRC-32 checksums
instead of using sha256. This is necessary, because the kernel built in
xz library cannot do sha256, will refuse to unpack the image otherwise and the
system won't boot.


## Putting everything on the Raspberry Pi and Booting it

Remember how I mentioned earlier that the last step of our boot loader chain
would involve something sane, like U-Boot or BareBox? Well, not on the
Raspberry Pi.

In addition to the already bizarro hardware, the Raspberry Pi has a lot of
proprietary magic baked directly into the hardware. The boot process is
controlled by the GPU, since the SoC is basically a GPU with an ARM CPU slapped
on to it.

The GPU loads a binary called `bootcode.bin` from the SD card, which contains a
proprietary boot loader blob for the GPU. This in turn does some initialization
and chain loads `start.elf` which contains a firmware blob for the GPU. The GPU
is running an RTOS called [ThreadX OS](https://en.wikipedia.org/wiki/ThreadX)
and somewhere around [>1M lines](https://www.raspberrypi.org/forums/viewtopic.php?t=53007#p406247)
worth of firmware code.

There are different versions of `start.elf`. The one called `start_x.elf`
contains an additional driver for the camera interface, `start_db.elf` is a
debug version and `start_cd.elf` is a version with a cut-down memory layout.

The `start.elf` file uses an aditional file called `fixup.dat` to configure
the RAM partitioning between the GPU and the CPU.

In the end, the GPU firmware loads and parses a file called `config.txt` from
the SD card, which contains configuration parameters, and `cmdline.txt` which
contains the kernel command line. After parsing the configuration, it finally
loads the kernel, the initramfs, the device tree binaries and runs the kernel.

Depending on the configuration, the GPU firmway may patch the device tree
in-memory before running the kernel.

### Copying the Files Over

First, we need a micro SD card with a FAT32 partition on it. How to create the
partition is left as an exercise to the reader.

Onto this partition, we copy the proprietary boot loader blobs:

* [bootcode.bin](firmware/bootcode.bin)
* [fixup.dat](firmware/fixup.data)
* [start.elf](firmware/start.elf)

We create a minimal [config.txt](firmware/config.txt) in the root directory:

	dtparam=
	kernel=zImage
	initramfs initramfs.xz followkernel

The first line makes sure the boot loader doesn't mangle the device tree. The
second one specifies the kernel binary that should be loaded and the last one
specifies the initramfs image. Note that there is no `=` sign in the last
line. This field has a different format and the boot loader will ignore it if
there is an `=` sign. The `followkernel` attribute tells the boot loader to put
the initramfs into memory right after the kernel binary.

Then, we'll put the [cmdline.txt](firmware/cmdline.txt) onto the SD card:

	console=tty0

The `console` parameter tells the kernel the tty where it prints its boot
messages and that it uses as the standard input/output tty for our init script.
We tell it to use the first video console which is what we will get at the HDMI
output of the Raspberry Pi.

Whats left are the device tree binaries and lastly the kernel and initramfs:

    mkdir -p overlays
    cp $SYSROOT/boot/dts/*-rpi-3-*.dtb .
    cp $SYSROOT/boot/dts/overlays/*.dtbo overlays/

    cp $SYSROOT/boot/initramfs.xz .
    cp $SYSROOT/boot/zImage .

If you are done, unmount the micro SD card and plug it into your Raspberr Pi.


### Booting It Up

If you connect the HDMI port and power up the Raspberry Pi, it should boot
directly into the initramfs and you should get a BusyBox shell.

The PATH is propperly set and the most common shell commands should be there, so
you can poke around the root filesystem which is in memory and has been unpacked
from the `initramfs.xz`.

Don't be alarmed by the kernel boot prompt suddenly stopping. Even after the
BusyBox shell starts, the kernel continues spewing messages for a short while
and you may not see the shell prompt. Just hit the enter key a couple times.

Also, the shell itself is running as PID 1. If you exit it, the kernel panics
because PID 1 just died.
