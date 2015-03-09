#!/bin/echo 'DO NOT RUN THIS SCRIPT DIRECTLY!'

# 工作目录: /home/gengs/develops/ILOS
# 目录结构:
	# .
	# |-- build
	# |-- cross-gcc-tmp
	# |-- cross-tool
	# |-- initramfs
	# |-- rootfs
	# |-- source
	# `-- sysroot

exit

function kernel_bzImage {
	cd build/linux-3.7.4/
	make bzImage -j8
	cp arch/x86/boot/bzImage ${SYSROOT}/boot/
	croot
}

function kernel_modules {
	cd build/linux-3.7.4/
	make modules -j8
	make INSTALL_MOD_PATH=${SYSROOT} modules_install
	croot
}

function kernel_packing {
	scp ${SYSROOT}/boot/bzImage root@192.168.56.101:/vita/boot/
}

# 打包压缩安装 initramfs
function initramfs_packing {
	cd initramfs/
	find . | cpio -o -H newc | gzip -9 > ${SYSROOT}/boot/initrd.img
	croot

	scp ${SYSROOT}/boot/initrd.img root@192.168.56.101:/vita/boot/
}

# 打包压缩安装根文件系统
function rootfs_packing {
	i686-none-linux-gnu-strip rootfs/lib/* rootfs/bin/*
	cd rootfs/
	tar zcvf ../rootfs.tgz *
	croot

	scp rootfs.tgz root@192.168.56.101:/vita/
}

# 禁用 libtool
function la_remove {
	find ${SYSROOT} -name "*.la" -exec rm -f '{}' \;
}

# 打包压缩安装根文件系统
function sysroot_packing {
	cd ${SYSROOT}
	tar zcvf ../sysroot.tgz *
	croot

	scp sysroot.tgz root@192.168.56.101:/root/
}

# 环境准备
cd /home/gengs/develops/ILOS
cp source/tools/env.0.sh ./env.sh
source env.sh
mkdir build ${CROSS_GCC_TMP} ${CROSS_TOOL} ${SYSROOT}
mkdir ${SYSROOT}/boot
croot

# 构建二进制工具
cd build/
tar xvf ../source/binutils-2.23.1.tar.bz2
mkdir binutils-build
cd binutils-build
../binutils-2.23.1/configure \
	--prefix=${CROSS_TOOL} \
	--target=${TARGET} \
	--with-sysroot=${SYSROOT}
make -j8
make install
croot

# 准备 gcc 编译环境
cd build/
tar xvf ../source/gcc-4.7.2.tar.bz2
cd gcc-4.7.2/
tar xvf ../../source/gmp-5.0.5.tar.bz2
mv gmp-5.0.5/ gmp
tar xvf ../../source/mpfr-3.1.1.tar.bz2
mv mpfr-3.1.1/ mpfr
tar xvf ../../source/mpc-1.0.1.tar.gz
mv mpc-1.0.1/ mpc
croot

# 编译 freestanding gcc
cd build/
mkdir gcc-build
cd gcc-build/
../gcc-4.7.2/configure \
	--prefix=${CROSS_GCC_TMP} \
	--target=${TARGET} \
	--with-sysroot=${SYSROOT} \
	--with-newlib \
	--enable-languages=c \
	--with-mpfr-include=${WORKDIR}/build/gcc-4.7.2/mpfr/src \
	--with-mpfr-lib=${WORKDIR}/build/gcc-build/mpfr/src/.libs \
	--disable-shared \
	--disable-threads \
	--disable-decimal-float \
	--disable-libquadmath \
	--disable-libmudflap \
	--disable-libgomp \
	--disable-nls \
	--disable-libssp
make -j8
make install
cd ../
ln -s libgcc.a ../cross-gcc-tmp/lib/gcc/i686-none-linux-gnu/4.7.2/libgcc_eh.a
croot

# 安装内核头文件
cd build/
tar xvf ../source/linux-3.7.4.tar.xz
cd linux-3.7.4/
make mrproper
make ARCH=i386 headers_check
make ARCH=i386 INSTALL_HDR_PATH=${SYSROOT}/usr/ headers_install
croot

# 编译目标系统 C 库
cd build/
tar xvf ../source/glibc-2.15.tar.xz
patch -p0 < ../source/patchs/glibc-2.15_cpuid_ifdef.patch

mkdir glibc-build
cd glibc-build/
../glibc-2.15/configure \
	--prefix=/usr \
	--host=${TARGET} \
	--enable-kernel=3.7.4 \
	--enable-add-ons \
	--with-headers=${SYSROOT}/usr/include \
	libc_cv_forced_unwind=yes \
	libc_cv_c_cleanup=yes \
	libc_cv_ctors_header=yes
make -j8
make install_root=${SYSROOT} install
croot

# 编译 cross compiler gcc
cd build/gcc-build/
rm -rf *
../gcc-4.7.2/configure \
	--prefix=${CROSS_TOOL} \
	--target=${TARGET} \
	--with-sysroot=${SYSROOT} \
	--with-mpfr-include=${WORKDIR}/build/gcc-4.7.2/mpfr/src \
	--with-mpfr-lib=${WORKDIR}/build/gcc-build/mpfr/src/.libs \
	--enable-languages=c,c++ \
	--enable-threads=posix
make -j8
make install
croot

# 定义工具链环境变量
cp source/tools/env.1.sh ./env.sh
source env.sh
cp source/tools/pkg-config ${CROSS_TOOL}/bin/

# 配置内核编译环境变量
cd build/linux-3.7.4/
sed -r -i 's/^(ARCH\s+\?=\s+).*/\1i386/' Makefile
sed -r -i 's/^(CROSS_COMPILE\s+\?=\s+).*/\1i686-none-linux-gnu-/' Makefile
make allnoconfig
croot

# 编译 bzImage
#DO: kernel menuconfig 配置处理器
#DO: kernel menuconfig 配置内核支持模块
#DO: kernel menuconfig 配置硬盘控制器驱动
#DO: kernel menuconfig 配置文件系统
#DO: kernel menuconfig 配置内核支持 ELF 文件格式
kernel_bzImage

# 部署 kernel
kernel_packing

# 构建根文件系统
mkdir rootfs
mkdir rootfs/lib
mkdir rootfs/bin

# 安装 C 库
cp -d ${SYSROOT}/lib/* rootfs/lib/
cp -d ${CROSS_TOOL}/i686-none-linux-gnu/lib/lib*.so.*[0-9] rootfs/lib/

# 安装 shell
cd build/
tar xvf ../source/bash-4.2.tar.gz
mkdir bash-build
cd bash-build
../bash-4.2/configure \
	--prefix=/usr \
	--bindir=/bin \
	--without-bash-malloc
make -j8
make install DESTDIR=${SYSROOT}
croot

cp ${SYSROOT}/bin/bash rootfs/bin/
ln -s bash rootfs/bin/sh

# 动态库依赖检查工具
cp source/tools/ldd cross-tool/bin/

# 打包压缩安装根文件系统
rootfs_packing

#DO: kernel menuconfig 配置内核支持 initramfs
kernel_bzImage

# 构建 initramfs
mkdir initramfs
cd initramfs/
cp ../source/tools/init.initramfs.0 ./init
mkdir bin
cp ${SYSROOT}/bin/bash bin/
mkdir lib
cp -d ${SYSROOT}/lib/libdl* lib/
cp ${SYSROOT}/lib/libc-2.15.so lib/
cp -d ${SYSROOT}/lib/libc.so.6 lib/
cp ${CROSS_TOOL}/i686-none-linux-gnu/lib/libgcc_s.so.1 lib/
cp -d ${SYSROOT}/lib/ld-* lib/
croot

# 打包压缩安装 initramfs
initramfs_packing
kernel_packing

# 配置 devtmpfs : ls
cd build/
tar xvf ../source/coreutils-8.20.tar.xz
cd coreutils-8.20/
./configure --prefix=/usr
make install
croot

cp ${SYSROOT}/usr/bin/ls initramfs/bin/
cp -d ${SYSROOT}/lib/librt* initramfs/lib/
cp -d ${SYSROOT}/lib/libpthread* initramfs/lib/

# 配置 devtmpfs : mount
cd build/
tar xvf ../source/util-linux-2.22.tar.xz
cd util-linux-2.22/
./configure \
	--prefix=/usr \
	--disable-use-tty-group \
	--disable-login \
	--disable-sulogin \
	--disable-su \
	--without-ncurses
make -j8
make install
croot

la_remove

# install mount
cp ${SYSROOT}/bin/mount initramfs/bin/
cp -d ${SYSROOT}/lib/libmount.so.1* initramfs/lib/
cp -d ${SYSROOT}/lib/libblkid.so.1* initramfs/lib/
cp -d ${SYSROOT}/lib/libuuid.so.1* initramfs/lib/

#DO: kernel menuconfig 配置内核支持 devtmpfs
kernel_bzImage

cp ./source/tools/init.initramfs.1 ./initramfs/init

initramfs_packing
kernel_packing

#DO: kernel menuconfig 配置硬盘驱动为模块
kernel_bzImage
kernel_modules

mkdir -p initramfs/lib/modules/3.7.4/kernel/drivers/ata/
cp ${SYSROOT}/lib/modules/3.7.4/kernel/drivers/ata/* initramfs/lib/modules/3.7.4/kernel/drivers/ata/

# kmod
cd build/
tar xvf ../source/kmod-12.tar.xz
cd kmod-12
./configure --prefix=/usr
make
make install
croot

la_remove

mkdir -p initramfs/usr/bin/
cp ${SYSROOT}/usr/bin/kmod initramfs/usr/bin/
cp -d ${SYSROOT}/usr/lib/libkmod.so.2* initramfs/lib/

cd ${SYSROOT}/sbin/
ln -s ../usr/bin/kmod insmod
ln -s ../usr/bin/kmod rmmod
ln -s ../usr/bin/kmod modinfo
ln -s ../usr/bin/kmod lsmod
ln -s ../usr/bin/kmod modprobe
ln -s ../usr/bin/kmod depmod
croot

mkdir initramfs/sbin/
cd ${SYSROOT}/sbin/
cp -d insmod rmmod modinfo lsmod modprobe depmod ../../initramfs/sbin/
croot

cp ${SYSROOT}/lib/modules/3.7.4/modules.dep.bin initramfs/lib/modules/3.7.4/

mkdir initramfs/proc initramfs/sys
cp ./source/tools/init.initramfs.2 ./initramfs/init

initramfs_packing
kernel_packing

# 编译安装 udev
cd build/
tar xvf ../source/udev-173.tar.xz
cd udev-173/
./configure \
	--prefix=/usr \
	--sysconfdir=/etc \
	--sbindir=/sbin \
	--libexecdir=/lib/udev \
	--disable-hwdb \
	--disable-introspection \
	--disable-keymap \
	--disable-gudev
make
make install
croot

la_remove

cp ${SYSROOT}/sbin/udevd initramfs/bin/
cp ${SYSROOT}/sbin/udevadm initramfs/bin/
mkdir -p initramfs/lib/udev/rules.d/
cp ${SYSROOT}/lib/udev/rules.d/80-drivers.rules initramfs/lib/udev/rules.d/

#DO: kernel menuconfig 配置内核支持 NETLINK
#DO: kernel menuconfig 配置内核支持 inotify
kernel_bzImage

# 安装 modules.alias.bin 文件
cp ${SYSROOT}/lib/modules/3.7.4/modules.alias.bin initramfs/lib/modules/3.7.4/

# 编译安装 pciutils
cd build/
tar xvf ../source/pciutils-3.1.10.tar.xz
cd pciutils-3.1.10
make PREFIX=/usr ZLIB=no SHARED=yes PCI_COMPRESSED_IDS=0 CROSS_COMPILE=${TARGET}- all
make PREFIX=/usr ZLIB=no SHARED=yes PCI_COMPRESSED_IDS=0 CROSS_COMPILE=${TARGET}- install
croot

cp ${SYSROOT}/usr/sbin/lspci initramfs/bin/
cp -d ${SYSROOT}/usr/lib/libpci.so.3* initramfs/lib/
cp -d ${SYSROOT}/lib/libresolv* initramfs/lib/
mkdir -p initramfs/usr/share
cp ${SYSROOT}/usr/share/pci.ids initramfs/usr/share/

cp ${SYSROOT}/usr/bin/cat initramfs/bin/

# 启动 udev 和模拟热插拔
cp ./source/tools/init.initramfs.3 ./initramfs/init

initramfs_packing
kernel_packing

# 挂载根文件系统
cp ./source/tools/init.initramfs.4 ./initramfs/init

# switch_root
cd build/
tar xvf ../source/switch_root.tar.xz
cd switch_root
make
cp switch_root ../../initramfs/bin/
croot

mkdir rootfs/sys rootfs/proc rootfs/dev rootfs/run rootfs/sbin
cp ./source/tools/init.rootfs.0 ./rootfs/sbin/init
cp ${SYSROOT}/usr/bin/cat rootfs/bin/
cp ${SYSROOT}/usr/bin/ls rootfs/bin/

cp ./source/tools/init.initramfs.5 ./initramfs/init

rootfs_packing

# 初始根文件系统
mkdir ${SYSROOT}/sys ${SYSROOT}/proc ${SYSROOT}/dev ${SYSROOT}/run ${SYSROOT}/root
cp ./source/tools/init.sysroot.0 ${SYSROOT}/sbin/init
cp ./source/tools/profile.sysroot.0 ${SYSROOT}/etc/profile

# SUID
cd ${SYSROOT}/bin/
sudo chown root.root mount umount
sudo chmod 4755 mount umount
croot

sysroot_packing

#DO: 配置内核支持网络
kernel_bzImage
kernel_modules

# 启动 udev
cp ./source/tools/init.sysroot.1 ${SYSROOT}/sbin/init

sysroot_packing

# 安装网络配置工具 : ip
cd build/
tar xvf ../source/iproute2-3.8.0.tar.xz
cd iproute2-3.8.0/
#EDIT: Makefile: ^SUBDIRS=lib ip
sed -i -r 's/^(SUBDIRS=).*/\1lib ip/' Makefile
make CC=$CC
make install
croot

# 安装网络配置工具 : ping
cd build/
tar xvf ../source/iputils-s20121221.tar.bz2
cd iputils-s20121221/
sed -i -r 's/^(IPV4_TARGETS=).*/\1ping/' Makefile
sed -i -r 's/^(TARGETS=).*/\1$(IPV4_TARGETS)/' Makefile
sed -i -r 's/^(USE_CAP=).*/\1no/' Makefile
make CC=$CC
cp ping ${SYSROOT}/bin/
croot

cp ./source/tools/init.sysroot.2 ${SYSROOT}/sbin/init

kernel_bzImage
kernel_modules
sysroot_packing

# ssh
cd build/
tar xvf ../source/zlib-1.2.7.tar.bz2
cd zlib-1.2.7/
./configure --prefix=/usr
make -j8
make install
croot

la_remove

cd build/
tar xvf ../source/openssl-1.0.1e.tar.gz
cd openssl-1.0.1e/
./Configure linux-elf --prefix=/usr --openssldir=/etc/ssl
make -j8
make install MANDIR=/usr/share/man INSTALL_PREFIX=${SYSROOT}
croot

la_remove

cd build/
tar xvf ../source/openssh-6.1p1.tar.gz
cd openssh-6.1p1/
LD=i686-none-linux-gnu-gcc ./configure --prefix=/usr --sysconfdir=/etc/ssh --without-openssl-header-check
make -j8
make install DESTDIR=${SYSROOT}
croot

la_remove

sed -i -r 's/^(#?UsePrivilegeSeparation\s+).*/\1no/' ${SYSROOT}/etc/ssh/sshd_config
sed -i -r 's/^(#?PermitRootLogin\s+).*/\1yes/' ${SYSROOT}/etc/ssh/sshd_config
sed -i -r 's/^(#?PermitEmptyPasswords\s+).*/\1yes/' ${SYSROOT}/etc/ssh/sshd_config

echo 'root::0:0::/root:/bin/bash' > ${SYSROOT}/etc/passwd
echo 'root::0:' > ${SYSROOT}/etc/group

cp ./source/tools/init.sysroot.3 ${SYSROOT}/sbin/init

sysroot_packing

# tar
cd build/
tar xvf ../source/tar-1.26.tar.xz
cd tar-1.26/
./configure --prefix=/usr
make -j8
make install
croot

# grep
cd build/
tar xvf ../source/grep-2.18.tar.xz
cd grep-2.18/
./configure --prefix=/usr
make
make install
croot

sysroot_packing

# procps
cd build/
tar xvf ../source/procps-ng-3.3.6.tar.xz
cd procps-ng-3.3.6/
./configure --prefix=/usr --without-ncurses
make -j8
make install
croot

# M4
mkdir build/X7.7

cd build/X7.7/
tar xvf ../../source/X7.7/util-macros-1.17.tar.bz2
cd util-macros-1.17/
./configure --prefix=/usr
make install
croot

# 安装 X 协议和扩展
packs=('xproto-7.0.23.tar.bz2' 'xextproto-7.2.1.tar.bz2' 'kbproto-1.0.6.tar.bz2' \
	'inputproto-2.2.tar.bz2' 'xcb-proto-1.8.tar.bz2' 'glproto-1.4.15.tar.bz2' \
	'dri2proto-2.8.tar.bz2' 'fixesproto-5.0.tar.bz2' 'damageproto-1.2.1.tar.bz2' \
	'xcmiscproto-1.2.2.tar.bz2' 'bigreqsproto-1.1.2.tar.bz2' 'randrproto-1.4.0.tar.bz2' \
	'renderproto-0.11.tar.bz2' 'fontsproto-2.1.2.tar.bz2' 'videoproto-2.3.1.tar.bz2' \
	'compositeproto-0.4.tar.bz2' 'resourceproto-1.2.0.tar.bz2' 'xf86dgaproto-2.1.tar.bz2')
for src in ${packs[@]}; do
	path=$(echo $src | sed -rn 's/([a-z0-9\-]+-([0-9]+\.)+[0-9]+)\.tar\.bz2/\1/p')
	cd build/X7.7/
	tar xvf ../../source/X7.7/${src}
	cd ${path}
	./configure --prefix=/usr
	make install
	croot
done

# 安装 X 相关库和工具
mkdir build/X7.7lib

packs=('pixman-0.28.0.tar.gz' 'xtrans-1.2.7.tar.bz2' 'libXau-1.0.7.tar.bz2' \
	'libpthread-stubs-0.3.tar.bz2' 'libxcb-1.8.1.tar.bz2' 'libX11-1.5.0.tar.bz2' \
	'libxkbfile-1.0.8.tar.bz2' 'xkbcomp-1.2.4.tar.bz2' 'xkeyboard-config-2.6.tar.bz2' \
	'freetype-2.4.10.tar.bz2' 'libfontenc-1.1.1.tar.bz2' 'libXfont-1.4.5.tar.bz2' \
	'libpciaccess-0.13.1.tar.bz2' 'libdrm-2.4.39.tar.bz2' 'libXdamage-1.1.3.tar.bz2' \
	'libXfixes-5.0.tar.bz2' 'libXext-1.3.1.tar.bz2')
for src in ${packs[@]}; do
	path=$(echo $src | sed -rn 's/([a-z0-9\-]+-([0-9]+\.)+[0-9]+)\.tar\.(bz2|gz)/\1/p')
	cd build/X7.7lib/
	tar xvf ../../source/X7.7lib/${src}
	cd ${path}/
	./configure --prefix=/usr
	make -j8
	make install
	croot
	la_remove
done

cd build/X7.7lib/
tar xvf ../../source/X7.7lib/expat-2.1.0.tar.gz
cd expat-2.1.0/
./configure --prefix=/usr
make -j8
make install INSTALL_ROOT=$SYSROOT
croot
la_remove

cd build/X7.7lib/
tar xvf ../../source/X7.7lib/MesaLib-8.0.3.tar.bz2
cd Mesa-8.0.3/
./configure \
	--prefix=/usr \
	--with-dri-drivers=swrast,i915,i965 \
	--disable-gallium-llvm \
	--without-gallium-drivers \
	--enable-32-bit
make -j8
make install
croot
la_remove

# X server
cd build/X7.7/
tar xvf ../../source/X7.7/xorg-server-1.12.2.tar.bz2
cd xorg-server-1.12.2/
./configure \
	--prefix=/usr \
	--enable-dri2 \
	--disable-dri \
	--disable-xnest \
	--disable-xephyr \
	--disable-xvfb \
	--disable-record \
	--disable-xinerama \
	--disable-screensaver \
	--with-xkb-output=/var/lib/xkb \
	--with-log-dir=/var/log
make -j8
make install
croot
la_remove

# GPU 2D
cd build/X7.7/
tar xvf ../../source/X7.7/xf86-video-vesa-2.3.1.tar.bz2
cd xf86-video-vesa-2.3.1/
./configure --prefix=/usr
make
make install
croot
la_remove

#DO: kernel menuconfig 安装 X 的输入设备驱动
kernel_bzImage
mkdir -p ${SYSROOT}/tmp ${SYSROOT}/var/log
sysroot_packing

# hello X
cd build/
tar xvf ../source/hello_x.tar.zx
cd hello_x/
make
scp hello_x root@192.168.56.2:/root/
croot

# grep
cd build/
tar xvf ../source/grep-2.18.tar.xz
cd grep-2.18/
./configure --prefix=/usr
make
make install
croot

# 安装图形库
mkdir build/GTK/

cd build/GTK/
tar xvf ../../source/GTK/libffi-3.0.11.tar.gz
cd libffi-3.0.11/
./configure --prefix=/usr
make -j8
make install
croot
la_remove

cd build/GTK/
tar xvf ../../source/GTK/glib-2.32.4.tar.xz
cd glib-2.32.4/
./configure --prefix=/usr
make -j8
make install
croot
la_remove

sudo apt-get install libglib2.0-dev

cd build/GTK/
tar xvf ../../source/GTK/atk-2.4.0.tar.xz
cd atk-2.4.0/
./configure --prefix=/usr
make -j8
make install
croot
la_remove

cd build/GTK/
tar xvf ../../source/GTK/libpng-1.5.12.tar.xz
cd libpng-1.5.12/
./configure --prefix=/usr
make -j8
make install
croot
la_remove

cd build/GTK/
tar xvf ../../source/GTK/gdk-pixbuf-2.26.3.tar.xz
patch -p0 < ../../source/patchs/gdk-pixbuf-2.26.3_disable-test.patch
cd gdk-pixbuf-2.26.3/
./configure \
	--prefix=/usr \
	--without-libtiff \
	--without-libjpeg
make -j8
make install
croot
la_remove

cd build/GTK/
tar xvf ../../source/GTK/fontconfig-2.10.1.tar.bz2
cd fontconfig-2.10.1/
./configure \
	--prefix=/usr \
	--sysconfdir=/etc \
	--localstatedir=/var \
	--disable-docs \
	--without-add-fonts
make -j8
make install
croot
la_remove

cd build/GTK/
tar xvf ../../source/GTK/cairo-1.12.2.tar.xz
cd cairo-1.12.2/
./configure --prefix=/usr
make -j8
make install
croot
la_remove

cd build/GTK/
tar xvf ../../source/GTK/pango-1.30.1.tar.xz
cd pango-1.30.1/
./configure --prefix=/usr
make -j8
make install
croot
la_remove

cd cd build/X7.7lib/
tar xvf ../../source/X7.7lib/libXi-1.6.1.tar.bz2
cd libXi-1.6.1/
./configure --prefix=/usr
make -j8
make install
croot
la_remove

cd build/GTK/
tar xvf ../../source/GTK/gtk+-3.4.4.tar.xz
cd gtk+-3.4.4/
./configure --prefix=/usr
make -j8
make install
croot
la_remove

# 安装图形库的善后工作

cp -d ${CROSS_TOOL}/${TARGET}/lib/libstdc++.so.* ${SYSROOT}/usr/lib/
mkdir ${SYSROOT}/usr/share/fonts/
cp /usr/share/fonts/truetype/wqy/wqy-microhei.ttc ${SYSROOT}/usr/share/fonts/

cd build/
tar xvf ../source/hello_gtk.tar.xz
cd hello_gtk/
make
make install
croot

sysroot_packing

#TARGET CMD: pango-querymodules > '/usr/etc/pango/pango.modules'
#TARGET CMD: gdk-pixbuf-query-loaders --update-cache
