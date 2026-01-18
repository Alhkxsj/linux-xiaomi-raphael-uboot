#!/bin/bash
set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# 检查必要的工具
check_dependencies() {
  log_info "检查编译依赖..."
  
  local missing_deps=()
  
  for cmd in git wget make clang ld.lld llvm-ar llvm-nm llvm-objcopy bc bison flex openssl python3; do
    if ! command -v $cmd 2>&1 >/dev/null; then
      missing_deps+=("$cmd")
    fi
  done
  
  if [ ${#missing_deps[@]} -ne 0 ]; then
    log_error "缺少必要的依赖: ${missing_deps[*]}"
    log_info "请安装: sudo apt install -y build-essential clang llvm lld bc bison flex openssl python3 git wget zstd"
    exit 1
  fi
  
  log_info "所有依赖已安装"
}

# 检查系统资源
check_system_resources() {
  log_info "检查系统资源..."
  
  local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
  local disk_gb=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
  
  if [ "$mem_gb" -lt 4 ]; then
    log_warn "内存不足 4GB，编译可能很慢或失败"
  fi
  
  if [ "$disk_gb" -lt 15 ]; then
    log_error "磁盘空间不足 15GB，请清理空间"
    exit 1
  fi
  
  log_info "内存: ${mem_gb}GB, 可用磁盘: ${disk_gb}GB"
}

# 检查编译环境
check_compile_environment() {
  log_info "检查编译环境..."
  
  # 检查编译器
  if command -v clang &> /dev/null; then
    log_info "Clang 版本: $(clang --version | head -n1)"
  else
    log_error "未找到 clang 编译器"
    exit 1
  fi
  
  # 检查链接器
  if command -v ld.lld &> /dev/null; then
    log_info "LLD 链接器版本: $(ld.lld --version | head -n1)"
  else
    log_error "未找到 lld 链接器"
    exit 1
  fi
  
  # 检查可用内存
  local available_mem=$(free -g | awk '/^Mem:/{print $7}')
  log_info "可用内存: ${available_mem}GB"
  
  # 检查可用磁盘空间
  local available_disk=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
  log_info "可用磁盘空间: ${available_disk}GB"
}

# 克隆指定版本的内核源码
echo "=========================================="
echo "  Xiaomi Raphael 内核构建 (Arch Linux)  "
echo "=========================================="

KERNEL_VERSION="${1:-6.18}"

log_info "内核版本: $KERNEL_VERSION"
log_info "开始时间: $(date)"
echo ""

# 检查依赖和系统资源
check_dependencies
check_system_resources
check_compile_environment

# 克隆指定版本的内核源码
log_info "克隆内核源码 (分支: raphael-$KERNEL_VERSION)..."
if [ -d "linux" ]; then
  log_warn "linux 目录已存在，删除旧目录..."
  rm -rf linux
fi

git clone https://github.com/GengWei1997/linux.git --branch raphael-$KERNEL_VERSION --depth 1 linux || {
  log_error "克隆内核源码失败"
  exit 1
}

# 保存当前目录
ORIGINAL_DIR="$(pwd)"
cd linux || {
  log_error "进入 linux 目录失败"
  exit 1
}

# 下载内核配置文件
log_info "下载内核配置文件..."
wget -P arch/arm64/configs https://raw.githubusercontent.com/GengWei1997/kernel-deb/refs/heads/main/raphael.config || {
  log_error "下载配置文件失败"
  exit 1
}

# 生成内核配置
log_info "生成内核配置..."
make -j$(nproc) ARCH=arm64 LLVM=1 defconfig raphael.config || {
  log_error "内核配置生成失败"
  echo "配置文件内容:"
  cat arch/arm64/configs/raphael.config | head -50
  exit 1
}

# 编译内核
log_info "开始编译内核..."
log_info "编译参数: ARCH=arm64 LLVM=1"
log_info "开始时间: $(date)"
echo ""

# 使用 LLVM 工具链编译
if ! make -j$(nproc) ARCH=arm64 LLVM=1 2>&1 | tee compile.log; then
  log_error "内核编译失败"
  echo ""
  echo "最后100行编译日志:"
  tail -100 compile.log
  exit 1
fi

log_info "编译成功完成！"
log_info "结束时间: $(date)"
echo ""

# 获取内核版本号
_kernel_version="$(make kernelrelease -s)"
_kernel_name="${_kernel_version}-raphael"

log_info "内核版本: $_kernel_version"
log_info "包名: linux-xiaomi-raphael-${_kernel_version}-1-aarch64.pkg.tar.zst"
echo ""

# 准备包目录结构
log_info "准备包目录结构..."
mkdir -p ../linux-xiaomi-raphael-arch/boot/dtbs/qcom

# 复制内核文件
log_info "复制内核文件..."
cp arch/arm64/boot/vmlinuz.efi ../linux-xiaomi-raphael-arch/boot/vmlinuz-$_kernel_name
cp arch/arm64/boot/Image.gz-dtb ../linux-xiaomi-raphael-arch/boot/Image.gz-dtb
cp arch/arm64/boot/dts/qcom/sm8150*.dtb ../linux-xiaomi-raphael-arch/boot/dtbs/qcom || log_warn "未找到设备树文件"
cp .config ../linux-xiaomi-raphael-arch/boot/config-$_kernel_name

# 安装内核模块
log_info "安装内核模块..."
make -j$(nproc) ARCH=arm64 LLVM=1 INSTALL_MOD_PATH=../linux-xiaomi-raphael-arch modules_install
rm -rf ../linux-xiaomi-raphael-arch/lib/modules/*/build
rm -rf ../linux-xiaomi-raphael-arch/lib/modules/*/source

# 生成 .MTREE 文件
log_info "生成包元数据..."
cd ../linux-xiaomi-raphael-arch
mtree -c -K sha256digest > .MTREE 2>/dev/null || {
  log_warn "mtree 命令不可用，跳过 .MTREE 生成"
}

# 生成 .PKGINFO 文件
cat > .PKGINFO << EOF
pkgname = linux-xiaomi-raphael
pkgver = ${_kernel_version}-1
pkgdesc = Kernel and Modules for Xiaomi K20 Pro (Raphael)
url = https://github.com/GengWei1997/linux
builddate = $(date +%s)
packager = Unknown Packager
size = $(du -sb . | cut -f1)
arch = aarch64
license = GPL2
depend = coreutils
depend = linux-firmware
backup = boot/config-${_kernel_version}
EOF

# 构建 .pkg.tar.zst 包
log_info "构建内核包..."
tar --create --zstd --file ../linux-xiaomi-raphael-${_kernel_version}-1-aarch64.pkg.tar.zst \
  --exclude='.PKGINFO' --exclude='.MTREE' --exclude='PKGBUILD' --exclude='.SRCINFO' . || {
  log_error "构建内核包失败"
  exit 1
}

# 添加 .PKGINFO 到包
tar --append --file ../linux-xiaomi-raphael-${_kernel_version}-1-aarch64.pkg.tar.zst .PKGINFO

cd ..

# 复制 firmware 包
log_info "构建 firmware 包..."
cp -r firmware-xiaomi-raphael firmware-xiaomi-raphael-arch
cd firmware-xiaomi-raphael-arch

# 生成 firmware .PKGINFO
cat > .PKGINFO << EOF
pkgname = firmware-xiaomi-raphael
pkgver = 1.0-1
pkgdesc = Firmware for Xiaomi K20 Pro (Raphael)
url = https://github.com/GengWei1997/linux
builddate = $(date +%s)
packager = Unknown Packager
size = $(du -sb . | cut -f1)
arch = aarch64
license = unknown
EOF

# 构建 firmware 包
tar --create --zstd --file ../firmware-xiaomi-raphael-1.0-1-aarch64.pkg.tar.zst \
  --exclude='.PKGINFO' --exclude='.MTREE' --exclude='PKGBUILD' --exclude='.SRCINFO' .

# 添加 .PKGINFO 到包
tar --append --file ../firmware-xiaomi-raphael-1.0-1-aarch64.pkg.tar.zst .PKGINFO

cd ..

# 复制 alsa 包
log_info "构建 alsa 包..."
cp -r alsa-xiaomi-raphael alsa-xiaomi-raphael-arch
cd alsa-xiaomi-raphael-arch

# 生成 alsa .PKGINFO
cat > .PKGINFO << EOF
pkgname = alsa-xiaomi-raphael
pkgver = 1.0-1
pkgdesc = ALSA configuration for Xiaomi K20 Pro (Raphael)
url = https://github.com/GengWei1997/linux
builddate = $(date +%s)
packager = Unknown Packager
size = $(du -sb . | cut -f1)
arch = aarch64
license = unknown
EOF

# 构建 alsa 包
tar --create --zstd --file ../alsa-xiaomi-raphael-1.0-1-aarch64.pkg.tar.zst \
  --exclude='.PKGINFO' --exclude='.MTREE' --exclude='PKGBUILD' --exclude='.SRCINFO' .

# 添加 .PKGINFO 到包
tar --append --file ../alsa-xiaomi-raphael-1.0-1-aarch64.pkg.tar.zst .PKGINFO

cd ..

# 返回原始目录
cd "$ORIGINAL_DIR" || {
  log_warn "无法返回原始目录，继续清理..."
}

# 清理临时目录
log_info "清理临时文件..."
rm -rf linux linux-xiaomi-raphael-arch firmware-xiaomi-raphael-arch alsa-xiaomi-raphael-arch

# 最终输出
echo ""
echo "=========================================="
log_info "内核包构建完成！"
echo "=========================================="
echo "生成的包:"
echo "  - linux-xiaomi-raphael-${_kernel_version}-1-aarch64.pkg.tar.zst"
echo "  - firmware-xiaomi-raphael-1.0-1-aarch64.pkg.tar.zst"
echo "  - alsa-xiaomi-raphael-1.0-1-aarch64.pkg.tar.zst"
echo ""
log_info "结束时间: $(date)"
echo "=========================================="
