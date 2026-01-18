#!/bin/bash
set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

log_step() {
  echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查系统资源
check_resources() {
  log_step "检查系统资源..."
  
  # 检查内存 (至少 4GB)
  local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
  if [ "$mem_gb" -lt 4 ]; then
    log_warn "内存不足 4GB，编译可能很慢或失败 (当前: ${mem_gb}GB)"
  else
    log_info "内存充足: ${mem_gb}GB"
  fi
  
  # 检查磁盘空间 (至少 20GB)
  local disk_gb=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
  if [ "$disk_gb" -lt 20 ]; then
    log_error "磁盘空间不足 20GB，请清理空间 (当前: ${disk_gb}GB)"
    exit 1
  fi
  
  # 检查可用磁盘空间
  local available_gb=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
  log_info "可用磁盘空间: ${available_gb}GB"
}

# 清理临时文件
cleanup() {
  log_step "清理临时文件..."
  rm -rf linux linux-xiaomi-raphael firmware-xiaomi-raphael alsa-xiaomi-raphael
  log_info "清理完成"
}

# 保存当前目录
ORIGINAL_DIR="$(pwd)"

# 检查参数
if [ -z "$1" ]; then
  log_error "请指定内核版本号，例如: $0 6.18"
  exit 1
fi

KERNEL_VERSION="$1"

# 显示开始信息
echo "=========================================="
log_step "Xiaomi Raphael 内核构建 (Debian) 开始"
echo "=========================================="
log_info "内核版本: $KERNEL_VERSION"
log_info "开始时间: $(date)"
echo ""

# 检查系统资源
check_resources

# 清理旧的临时文件
cleanup

# 克隆内核源码
log_step "克隆内核源码 (分支: raphael-$KERNEL_VERSION)..."
git clone https://github.com/GengWei1997/linux.git --branch raphael-$KERNEL_VERSION --depth 1 linux || {
  log_error "克隆内核源码失败"
  exit 1
}

cd linux || {
  log_error "进入 linux 目录失败"
  exit 1
}

# 下载内核配置文件
log_step "下载内核配置文件..."
wget -P arch/arm64/configs https://raw.githubusercontent.com/GengWei1997/kernel-deb/refs/heads/main/raphael.config || {
  log_error "下载配置文件失败"
  cleanup
  exit 1
}

# 生成内核配置
log_step "生成内核配置..."
make -j$(nproc) ARCH=arm64 LLVM=1 defconfig raphael.config || {
  log_error "内核配置生成失败"
  cleanup
  exit 1
}

# 编译内核
log_step "开始编译内核..."
log_info "编译参数: ARCH=arm64 LLVM=1"
log_info "并行任务数: $(nproc)"
log_info "开始时间: $(date)"
echo ""

# 使用 timeout 限制编译时间 (6小时)
if ! timeout 6h make -j$(nproc) ARCH=arm64 LLVM=1 2>&1 | tee compile.log; then
  log_error "内核编译失败"
  echo ""
  log_warn "最后100行编译日志:"
  tail -100 compile.log
  cleanup
  exit 1
fi

log_info "编译成功完成！"
log_info "结束时间: $(date)"
echo ""

# 获取内核版本号
_kernel_version="$(make kernelrelease -s)"
_kernel_name="${_kernel_version}-raphael"

log_info "内核版本: $_kernel_version"
echo ""

# 准备 deb 包目录结构
log_step "准备 deb 包目录结构..."
mkdir -p ../linux-xiaomi-raphael/boot/dtbs/qcom

# 复制内核文件
log_step "复制内核文件..."
cp arch/arm64/boot/vmlinuz.efi ../linux-xiaomi-raphael/boot/vmlinuz-$_kernel_version || log_error "复制 vmlinuz 失败"
cp arch/arm64/boot/dts/qcom/sm8150*.dtb ../linux-xiaomi-raphael/boot/dtbs/qcom || log_warn "未找到设备树文件"
cp .config ../linux-xiaomi-raphael/boot/config-$_kernel_version || log_error "复制配置文件失败"

# 更新 deb 包控制文件中的版本号
log_step "更新包控制文件..."
sed -i "s/Version:.*/Version: ${_kernel_version}/" ../linux-xiaomi-raphael/DEBIAN/control || log_error "更新版本号失败"

# 安装内核模块
log_step "安装内核模块..."
make -j$(nproc) ARCH=arm64 LLVM=1 INSTALL_MOD_PATH=../linux-xiaomi-raphael modules_install || log_error "安装内核模块失败"
rm -rf ../linux-xiaomi-raphael/lib/modules/**/build

# 返回原始目录
cd "$ORIGINAL_DIR" || {
  log_warn "无法返回原始目录，继续清理..."
}

# 构建 deb 包
log_step "构建 deb 包..."
dpkg-deb --build --root-owner-group linux-xiaomi-raphael || log_error "构建 linux-xiaomi-raphael 包失败"
dpkg-deb --build --root-owner-group firmware-xiaomi-raphael || log_error "构建 firmware-xiaomi-raphael 包失败"
dpkg-deb --build --root-owner-group alsa-xiaomi-raphael || log_error "构建 alsa-xiaomi-raphael 包失败"

# 清理源码目录
cleanup

# 最终输出
echo ""
echo "=========================================="
log_info "内核包构建完成！"
echo "=========================================="
log_info "生成的包:"
ls -lh ../linux-xiaomi-raphael-*.deb 2>/dev/null | awk '{print "  - " $9 " (" $5 ")"}'
echo ""
log_info "结束时间: $(date)"
echo "=========================================="