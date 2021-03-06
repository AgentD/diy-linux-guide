# Building a small Raspberry Pi System from Scratch

What you are looking at right now is a collection of instructions on how to
bootstrap a tiny system for a Raspberry Pi 3 board.

We will bootstrap the system by building our own cross compiler toolchain
and then using it to cross compile everything we need for a working Linux
based OS.

In contrast to similar guides, I try to explain why we are doing the things
the way we are doing them, instead of just throwing a bunch of copy-paste
command lines around (I'm looking at you, LFS).

This guide is divided into the following parts:

* [Basic Setup](00_setup.md). Lists some tools that you should have
  installed and walks through the steps of setting up the directory tree that
  we work in, as well as a few handy environment variables.
* [Building a cross compiler toolchain](01_crosscc.md).
* [Cross compiling a statically linked BusyBox and the kernel](02_kernel.md).
  The BusyBox is packaged into a small initramfs. We will make it boot on the
  Rapsberry Pi and explore some parts of the Linux boot process.
* [Building a simple userland](03_basic_usr.md). Mostly a
  Linux-From-Scratch-Style walkthrough to building some packages for a simple
  GNU userland. The userland is packed into a SquashFS image. The BusyBox
  based initrd is modified to mount it and switch into it.
