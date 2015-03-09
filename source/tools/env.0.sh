#!/bin/bash

export WORKDIR=$(cd $(dirname $0); pwd)

croot() {
	cd ${WORKDIR}
}
export -f croot

unset LANG
export HOST=$(echo $MACHTYPE)
export BUILD=$HOST
export TARGET=i686-none-linux-gnu
export CROSS_TOOL=${WORKDIR}/cross-tool
export CROSS_GCC_TMP=${WORKDIR}/cross-gcc-tmp
export SYSROOT=${WORKDIR}/sysroot
export PATH=$CROSS_TOOL/bin:$CROSS_GCC_TMP/bin:/sbin:/usr/sbin:$PATH

# BUILDING
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

export -f kernel_bzImage
export -f kernel_modules
export -f kernel_packing
export -f initramfs_packing
export -f rootfs_packing
export -f la_remove
export -f sysroot_packing
