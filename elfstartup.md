# Running dynamically linked programs on Linux

This section provides a high level overview of the startup process of a
dynamically linked program on Linux.

When using the `exec` system call to run a program, the kernel looks at the
first few bytes of the target file and tries to determine what kind of
executable. Based on the type of executable, some data structures are
parsed and the program is run. For a statically linked ELF program, this means
fiddling the entry point address out of the header and jumping to it (with
a kernel to user space transition of course).

The kernel also supports exec-ing programs that require an interpreter to be
run. This mechanism is also used for implementing dynamically linked programs.

Similar to how scripts have an interpreter field (`#!/bin/sh`
or `#!/usr/bin/perl`), ELF files can also have an interpreter section. For
dynamically linked ELF executables, the compiler sets the interpreter field
to the run time linker (`ld-linux.so` or similar), also known as "loader".

The `ld-linux.so` loader is typically provided by the `libc` implementation
(i.e. Musl, glibc, ...). It maps the actual executable into memory
with `mmap(2)`, parses the dynamic section and mmaps the used libraries
(possibly recursively since libraries may need other libraries), does
some relocations if applicable and then jumps to the entry point address.

The kernel itself actually has no concept of libraries. Thanks to this
mechanism, it doesn't even have to.

The whole process of using an interpreter is actually done recursively. An
interpreter can in-turn also have an interpreter. For instance if you exec
a shell script that starts with `#!/bin/sh`, the kernel detects it to be a
script (because it starts with `#!`), extracts the interpreter and then
runs `/bin/sh <script-path>` instead. The kernel then detects that `/bin/sh`
is an ELF binary (because it starts with `\x7fELF`) and extracts the
interpreter field, which is set to `/lib/ld-linux.so`. So now the kernel
tries to run `/lib/ld-linux.so /bin/sh <script-path>`. The `ld-linux.so` has
no interpreter field set, so the kernel maps it into memory, extracts the
entry point address and runs it.

If `/bin/sh` were statically linked, the last step would be missing and the
kernel would start executing right there. Linux actually has a hard limit for
interpreter recursion depth, typically set to 3 to support this exact standard
case (script, interpreter, loader).

The entry point of the ELF file that the loader jumps to is of course NOT
the `main` function of the C program. It points to setup code provided by
the libc implementation that does some initialization first, such as stack
setup, getting the argument vector, initializing malloc or whatever other
internals and then calls the `main` function. When `main` returns, the
startup code calls the `exit` system call with the return value from `main`.

The startup code is provided by the libc, typically in the form of an object
file in `/lib`, e.g. `/lib/crt0.o`. The C compiler links executable programs
against this object file and expects it to have a symbol called `_start`. The
entry point address of the ELF file is set to the location of `_start` and the
interpreter is set to the path of the loader.

Finally, somewhere inside the `main` function of `/bin/sh`, it eventually opens
the file it has been provided on the command line and starts interpreting your
shell script.

## Take Away Message

In summary, the compiler needs to know the following things about the libc:
 - The path to the loader for dynamically linked programs.
 - The path to the startup object code it needs to link against.
 - The path of the libc itself to link against.

If you try to run a program and you get the possibly most useless error
message `no such file or directory`, it could have the following reasons:
 - The kernel couldn't find the program you are trying to run.
 - The kernel couldn't find the interpreter set by the program.
 - The kernel couldn't find the interpreter of the interpreter.
 - The loader couldn't find a library used by either your program, the
   interpreter of your program, or another library that it loaded.

So if you see that error message, don't panic, try to figure out the root
cause by walking through this checklist. You can use the `ldd` program (that
is provided by the libc) to display libraries that the loader would try to
load. But **NEVER** use `ldd` on untrusted programs. Typical implementations
of ldd try to execute the interpreter with special options to collect
dependencies. An attacker could set this to something other than `ld-linux.so`
and gain code execution.
