# Building a More Sophisticated Userspace

After revisiting the structure of our `sysroot` directory, we will build
and install some basic packages:

* `tzdata`
* `ncurses`
* `readline`
* `zlib`
* `bash`
* `bash-completion` scripts from Debian
* `coreutils`
* `diffutils`
* `findutils`
* `util-linux`
* `grep`
* `less`
* `xz`
* `gzip`
* `bzip2`
* `tar`
* `sed`
* `gawk`
* `procps-ng`
* `psmisc`
* `file`
* `shadow`
* `inetutils`
* `nano`
* [gcron](https://github.com/pygos/cron)
* [usyslog](https://github.com/pygos/usyslog)
* [pygos init](https://github.com/pygos/init)
* `init-scripts`

Those should provide us with a pretty decent base system and GNU/Linux command
line environment to work in. It's a lot of stuff, so I'd advise you to automate
most of setps in some way using shell scripts. I will also provide some usefull
utility functions below.

I chose `nano` as text editor because it's dead simple to use. Furthermore, I
used the init system from Pygos because it's configuration is a little more
sophisticated and simpler than having to write dozens of shell scripts for a
System V style init. Also, it requires basically no dependencies.

Although networking is listed below, we need at least the `hostname` program
from the `inetutils` package, so I added it to the list of the base system.

After building this base system, we will again put it all together, i.e.
package the whole thing into a SquashFS image, modify and rebuild the initrd,
and take a closer look at the bootstrap processes through our `init` all the
way to spawning `getty` instances on the console (remember, the goal here is
to actually understand what's going on in the end).

Once everything is working, we build a few more packages for wired networking:

* `openssl`
* `ldns`
* `ntp`
* `iana-etc`
* `libmnl`
* `libnftnl`
* `gmp`
* `iproute2`
* `nftables`
* `dhcpcd`
* `libnl3`
* `libpcup`
* `tcpdump`
* `openssh`

We will modify the init scripts to obtain an IPv4 network configuration via
DHCP on the wired Ethernet interface, configure basic firewalling
through `nftables`, discussing a little bit of Linux network configuration
and debugging along the way.

An init script and a script for `dhcpcd` are added to fetch current date
and time via `ntp`, since the Raspberry Pi does not have a real time clock
on board.

As a final step, we will take a look at setting up a wireless access point
that NAT forwards traffic from its clients via the wired Ethernet port. This
requires the following additional packages:

* `libbsd`
* `expat`
* `unbound`
* `dnsmasq`
* `hostapd`
* `iw`

# TODO: write the remaining documentation
