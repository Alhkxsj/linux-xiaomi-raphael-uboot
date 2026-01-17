#!/bin/bash

# 克隆指定版本的内核源码
echo "正在克隆内核源码..."
git clone https://github.com/GengWei1997/linux.git --branch raphael-$1 --depth 1 linux || {
  echo "错误: 克隆内核源码失败"
  exit 1
}
cd linux

# 下载内核配置文件
echo "正在下载内核配置文件..."
wget -P arch/arm64/configs https://raw.githubusercontent.com/GengWei1997/kernel-deb/refs/heads/main/raphael.config || {
  echo "错误: 下载配置文件失败"
  exit 1
}

# 生成内核配置
echo "正在生成内核配置..."
make -j$(nproc) ARCH=arm64 LLVM=1 defconfig raphael.config || {
  echo "错误: 内核配置生成失败"
  echo "检查配置文件内容:"
  cat arch/arm64/configs/raphael.config | head -50
  exit 1
}

# 编译内核
echo "正在编译内核..."
echo "编译参数: ARCH=arm64 LLVM=1 CC=clang LD=ld.lld"
echo "开始时间: $(date)"

# 使用 time 命令统计编译时间
{
  time make -j$(nproc) ARCH=arm64 LLVM=1 CC=clang LD=ld.lld 2>&1 | tee compile.log
} || {
  echo "错误: 内核编译失败"
  echo "显示最后100行编译日志:"
  tail -100 compile.log
  echo ""
  echo "检查编译环境:"
  which clang ld.lld
  clang --version | head -3
  ld.lld --version | head -3
  echo ""
  echo "检查系统资源:"
  free -h
  df -h
  exit 1
}

echo "结束时间: $(date)"
echo "编译成功完成！"

# 获取内核版本号
_kernel_version="$(make kernelrelease -s)"
_kernel_name="${_kernel_version}-raphael"

echo "内核版本: $_kernel_version"

# 准备包目录结构
mkdir -p ../linux-xiaomi-raphael-arch/boot/dtbs/qcom
mkdir -p ../linux-xiaomi-raphael-arch/usr/lib/modules/$_kernel_name

# 复制内核文件
cp arch/arm64/boot/vmlinuz.efi ../linux-xiaomi-raphael-arch/boot/vmlinuz-$_kernel_name
cp arch/arm64/boot/Image.gz-dtb ../linux-xiaomi-raphael-arch/boot/Image.gz-dtb
cp arch/arm64/boot/dts/qcom/sm8150*.dtb ../linux-xiaomi-raphael-arch/boot/dtbs/qcom
cp .config ../linux-xiaomi-raphael-arch/boot/config-$_kernel_name

# 安装内核模块
make -j$(nproc) ARCH=arm64 LLVM=1 INSTALL_MOD_PATH=../linux-xiaomi-raphael-arch modules_install
rm ../linux-xiaomi-raphael-arch/lib/modules/**/build
rm ../linux-xiaomi-raphael-arch/lib/modules/**/source

# 创建 PKGBUILD 文件
cat > ../linux-xiaomi-raphael-arch/PKGBUILD << EOF
# Maintainer: GengWei1997 <anonymous@localhost>
pkgname=linux-xiaomi-raphael
pkgver=${_kernel_version}
pkgrel=1
pkgdesc="Kernel and Modules for Xiaomi K20 Pro (Raphael)"
arch=('aarch64')
url="https://github.com/GengWei1997/linux"
license=('GPL2')
depends=('coreutils' 'linux-firmware')
makedepends=('git' 'llvm' 'clang' 'lld' 'python' 'bc' 'bison' 'flex' 'openssl' 'zlib')
options=('!strip')
backup=('boot/config-$_kernel_name')

package() {
  # 复制内核文件
  install -Dm644 boot/vmlinuz-$_kernel_name "\$pkgdir/boot/vmlinuz-$_kernel_name"
  install -Dm644 boot/Image.gz-dtb "\$pkgdir/boot/Image.gz-dtb"
  install -Dm644 boot/config-$_kernel_name "\$pkgdir/boot/config-$_kernel_name"

  # 复制设备树文件
  mkdir -p "\$pkgdir/boot/dtbs/qcom"
  install -m644 boot/dtbs/qcom/*.dtb "\$pkgdir/boot/dtbs/qcom/"

  # 复制内核模块
  cp -r usr/lib/modules/$_kernel_name "\$pkgdir/usr/lib/modules/"
}
EOF

# 创建 .SRCINFO 文件
cat > ../linux-xiaomi-raphael-arch/.SRCINFO << EOF
pkgbase = linux-xiaomi-raphael
pkgdesc = Kernel and Modules for Xiaomi K20 Pro (Raphael)
pkgver = ${_kernel_version}
pkgrel = 1
url = https://github.com/GengWei1997/linux
arch = aarch64
license = GPL2
depends = coreutils
depends = linux-firmware
makedepends = git
makedepends = llvm
makedepends = clang
makedepends = lld
makedepends = python
makedepends = bc
makedepends = bison
makedepends = flex
makedepends = openssl
makedepends = zlib
options = !strip
backup = boot/config-${_kernel_version}

pkgname = linux-xiaomi-raphael
EOF

cd ..

# 清理源码目录
rm -rf linux

# 创建包信息文件
mkdir -p linux-xiaomi-raphael-arch/.MTREE
mkdir -p linux-xiaomi-raphael-arch/.PKGINFO

# 构建 .pkg.tar.zst 包
cd linux-xiaomi-raphael-arch
tar --create --zstd --file ../linux-xiaomi-raphael-${_kernel_version}-1-aarch64.pkg.tar.zst --exclude='.PKGINFO' --exclude='.MTREE' --exclude='PKGBUILD' --exclude='.SRCINFO' .
cd ..

# 生成 .PKGINFO
cat > linux-xiaomi-raphael-arch/.PKGINFO << EOF
pkgname = linux-xiaomi-raphael
pkgver = ${_kernel_version}-1
pkgdesc = Kernel and Modules for Xiaomi K20 Pro (Raphael)
builddate = $(date +%s)
packager = Unknown Packager
size = $(du -sb linux-xiaomi-raphael-arch | cut -f1)
arch = aarch64
license = GPL2
EOF

# 添加 .PKGINFO 到包
cd linux-xiaomi-raphael-arch
tar --append --file ../linux-xiaomi-raphael-${_kernel_version}-1-aarch64.pkg.tar.zst .PKGINFO
cd ..

# 复制 firmware 包
cp -r firmware-xiaomi-raphael firmware-xiaomi-raphael-arch
cd firmware-xiaomi-raphael-arch

# 创建 firmware PKGBUILD
cat > PKGBUILD << EOF
# Maintainer: GengWei1997 <anonymous@localhost>
pkgname=firmware-xiaomi-raphael
pkgver=1.0
pkgrel=1
pkgdesc="Firmware for Xiaomi K20 Pro (Raphael)"
arch=('aarch64')
license=('unknown')

package() {
  cp -r usr "\$pkgdir/"
}
EOF

# 创建 firmware .SRCINFO
cat > .SRCINFO << EOF
pkgbase = firmware-xiaomi-raphael
pkgdesc = Firmware for Xiaomi K20 Pro (Raphael)
pkgver = 1.0
pkgrel = 1
url = https://github.com/GengWei1997/linux
arch = aarch64
license = unknown

pkgname = firmware-xiaomi-raphael
EOF

# 构建 firmware 包
tar --create --zstd --file ../firmware-xiaomi-raphael-1.0-1-aarch64.pkg.tar.zst --exclude='.PKGINFO' --exclude='.MTREE' --exclude='PKGBUILD' --exclude='.SRCINFO' .

# 生成 firmware .PKGINFO
cat > .PKGINFO << EOF
pkgname = firmware-xiaomi-raphael
pkgver = 1.0-1
pkgdesc = Firmware for Xiaomi K20 Pro (Raphael)
builddate = $(date +%s)
packager = Unknown Packager
size = $(du -sb firmware-xiaomi-raphael-arch | cut -f1)
arch = aarch64
license = unknown
EOF

# 添加 .PKGINFO 到包
tar --append --file ../firmware-xiaomi-raphael-1.0-1-aarch64.pkg.tar.zst .PKGINFO

cd ..

# 复制 alsa 包
cp -r alsa-xiaomi-raphael alsa-xiaomi-raphael-arch
cd alsa-xiaomi-raphael-arch

# 创建 alsa PKGBUILD
cat > PKGBUILD << EOF
# Maintainer: GengWei1997 <anonymous@localhost>
pkgname=alsa-xiaomi-raphael
pkgver=1.0
pkgrel=1
pkgdesc="ALSA configuration for Xiaomi K20 Pro (Raphael)"
arch=('aarch64')
license=('unknown')

package() {
  cp -r usr "\$pkgdir/"
}
EOF

# 创建 alsa .SRCINFO
cat > .SRCINFO << EOF
pkgbase = alsa-xiaomi-raphael
pkgdesc = ALSA configuration for Xiaomi K20 Pro (Raphael)
pkgver = 1.0
pkgrel = 1
url = https://github.com/GengWei1997/linux
arch = aarch64
license = unknown

pkgname = alsa-xiaomi-raphael
EOF

# 构建 alsa 包
tar --create --zstd --file ../alsa-xiaomi-raphael-1.0-1-aarch64.pkg.tar.zst --exclude='.PKGINFO' --exclude='.MTREE' --exclude='PKGBUILD' --exclude='.SRCINFO' .

# 生成 alsa .PKGINFO
cat > .PKGINFO << EOF
pkgname = alsa-xiaomi-raphael
pkgver = 1.0-1
pkgdesc = ALSA configuration for Xiaomi K20 Pro (Raphael)
builddate = $(date +%s)
packager = Unknown Packager
size = $(du -sb alsa-xiaomi-raphael-arch | cut -f1)
arch = aarch64
license = unknown
EOF

# 添加 .PKGINFO 到包
tar --append --file ../alsa-xiaomi-raphael-1.0-1-aarch64.pkg.tar.zst .PKGINFO

cd ..

# 清理临时目录
rm -rf linux-xiaomi-raphael-arch firmware-xiaomi-raphael-arch alsa-xiaomi-raphael-arch

echo "内核包构建完成:"
echo "  - linux-xiaomi-raphael-${_kernel_version}-1-aarch64.pkg.tar.zst"
echo "  - firmware-xiaomi-raphael-1.0-1-aarch64.pkg.tar.zst"
echo "  - alsa-xiaomi-raphael-1.0-1-aarch64.pkg.tar.zst"