run_configure() {
	"$srcdir/configure" --host="$TARGET" --prefix="" --sbindir=/bin \
			    --includedir=/usr/include --datarootdir=/usr/share\
			    --libexecdir=/lib/libexec --disable-static \
			    --enable-shared $@
}

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

export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$SYSROOT/lib/pkgconfig"
export PKG_CONFIG_PATH="$SYSROOT/lib/pkgconfig"
