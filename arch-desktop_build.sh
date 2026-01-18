#!/bin/sh
set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]
then
  log_error "rootfs can only be built as root"
  exit 1
fi

# 获取参数
DESKTOP_ENV="${1:-gnome}"
KERNEL_VERSION="${2:-6.18}"

# 验证参数
validate_params() {
  # 验证桌面环境
  case "$DESKTOP_ENV" in
    gnome|plasma|xfce|mate|lxqt|lxde|none)
      ;;
    *)
      log_error "无效的桌面环境: $DESKTOP_ENV"
      log_info "支持的桌面环境: gnome, plasma, xfce, mate, lxqt, lxde, none"
      exit 1
      ;;
  esac

  # 验证内核版本格式（简单的版本号验证）
  if ! echo "$KERNEL_VERSION" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
    log_error "无效的内核版本格式: $KERNEL_VERSION"
    log_info "正确格式: 6.18 或 6.18.1"
    exit 1
  fi
}

# 验证参数
validate_params

echo "=========================================="
echo "  Arch Linux 镜像构建"
echo "=========================================="
log_info "构建配置:"
echo "  桌面环境: $DESKTOP_ENV"
echo "  内核版本: $KERNEL_VERSION"
echo "  开始时间: $(date)"
echo ""

# 创建根文件系统镜像
log_info "创建根文件系统镜像..."
truncate -s 6G rootfs.img
mkfs.ext4 rootfs.img
mkdir rootdir
mount -o loop rootfs.img rootdir

# 使用 pacstrap 安装基础系统
log_info "使用 pacstrap 安装基础系统..."
pacstrap -K -C /dev/null -d rootdir base base-devel linux linux-firmware || {
  log_error "pacstrap 安装失败"
  exit 1
}

# 绑定系统目录
mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount --bind /proc rootdir/proc
mount --bind /sys rootdir/sys

# 配置网络和主机名
echo "nameserver 1.1.1.1" | tee rootdir/etc/resolv.conf
echo "xiaomi-raphael" | tee rootdir/etc/hostname
echo "127.0.0.1 localhost
127.0.1.1 xiaomi-raphael" | tee rootdir/etc/hosts

# 配置清华镜像源（正确的 Arch Linux ARM 格式）
cat > rootdir/etc/pacman.d/mirrorlist << 'EOF'
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/$arch/$repo
EOF

# Chroot 配置步骤
chroot rootdir pacman-key --init
chroot rootdir pacman-key --populate archlinuxarm

# 更新系统
chroot rootdir pacman -Syu --noconfirm

# 安装基础软件包
chroot rootdir pacman -S --noconfirm \
  bash-completion sudo openssh nano systemd chrony curl wget dnsmasq iptables iproute2 \
  networkmanager wireless_tools wpa_supplicant bluez bluez-utils \
  pulseaudio pulseaudio-alsa pipewire pipewire-pulse pipewire-alsa pipewire-jack \
  alsa-utils alsa-plugins alsa-lib zstd

# 安装设备特定软件包
chroot rootdir pacman -S --noconfirm \
  rmtfs tqftpserv

# 安装 ALSA 配置包（如果存在）
if [ -n "$ALSA_PKG" ]; then
  chroot rootdir pacman -U --noconfirm "/tmp/$(basename "$ALSA_PKG")" || {
    log_warn "安装 ALSA 配置包失败（非致命错误）"
  }
fi

# 根据桌面环境参数安装对应的桌面环境
case "$DESKTOP_ENV" in
  "gnome")
    log_info "安装 GNOME 桌面环境..."
    chroot rootdir pacman -S --noconfirm \
      gnome gnome-extra gdm \
      xorg xorg-server xorg-xinit xorg-drivers \
      gnome-terminal gnome-tweaks gnome-system-monitor \
      nautilus file-roller eog evince \
      firefox gnome-shell-extensions
    ;;
  "plasma")
    log_info "安装 KDE Plasma 桌面环境..."
    chroot rootdir pacman -S --noconfirm \
      plasma plasma-meta kde-applications \
      xorg xorg-server xorg-xinit xorg-drivers \
      konsole dolphin kate gwenview \
      firefox sddm
    ;;
  "xfce")
    log_info "安装 XFCE 桌面环境..."
    chroot rootdir pacman -S --noconfirm \
      xfce4 xfce4-goodies \
      xorg xorg-server xorg-xinit xorg-drivers \
      xfce4-terminal thunar mousepad \
      firefox lightdm lightdm-gtk-greeter
    ;;
  "mate")
    log_info "安装 MATE 桌面环境..."
    chroot rootdir pacman -S --noconfirm \
      mate mate-extra \
      xorg xorg-server xorg-xinit xorg-drivers \
      mate-terminal caja pluma \
      firefox lightdm lightdm-gtk-greeter
    ;;
  "lxqt")
    log_info "安装 LXQt 桌面环境..."
    chroot rootdir pacman -S --noconfirm \
      lxqt lxqt-meta \
      xorg xorg-server xorg-xinit xorg-drivers \
      qterminal pcmanfm-qt leafpad \
      firefox sddm
    ;;
  "lxde")
    log_info "安装 LXDE 桌面环境..."
    chroot rootdir pacman -S --noconfirm \
      lxde lxde-common \
      xorg xorg-server xorg-xinit xorg-drivers \
      lxterminal pcmanfm leafpad \
      firefox lightdm lightdm-gtk-greeter
    ;;
  "none")
    log_info "无桌面环境，仅安装基础系统..."
    # 不安装任何桌面环境
    ;;
  *)
    log_error "未知的桌面环境: $DESKTOP_ENV"
    log_info "支持的桌面环境: gnome, plasma, xfce, mate, lxqt, lxde, none"
    exit 1
    ;;
esac

# 安装中文字体和输入法
chroot rootdir pacman -S --noconfirm \
  noto-fonts-cjk noto-fonts noto-fonts-extra \
  wqy-microhei wqy-zenhei \
  fcitx5 fcitx5-chinese-addons fcitx5-gtk fcitx5-qt5 fcitx5-configtool \
  ibus ibus-pinyin ibus-libpinyin

# 安装语言包和设置默认语言为简体中文
chroot rootdir pacman -S --noconfirm \
  adobe-source-han-sans-cn-fonts \
  adobe-source-han-serif-cn-fonts

# 配置 locale
cat > rootdir/etc/locale.gen << 'EOF'
zh_CN.UTF-8 UTF-8
en_US.UTF-8 UTF-8
EOF
chroot rootdir locale-gen
echo "LANG=zh_CN.UTF-8" | tee rootdir/etc/locale.conf
echo "LC_ALL=zh_CN.UTF-8" | tee -a rootdir/etc/locale.conf

# 设置时区
chroot rootdir ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" | tee rootdir/etc/timezone

# 配置硬件时钟
chroot rootdir hwclock --systohc

# 复制并安装内核包（从预下载的目录）
log_info "安装内核包..."
KERNEL_DIR="xiaomi-raphael-debs_$KERNEL_VERSION"

# 检查内核包目录是否存在
if [ ! -d "$KERNEL_DIR" ]; then
  log_error "内核包目录不存在: $KERNEL_DIR"
  log_info "请先运行内核构建脚本或从 GitHub Release 下载内核包"
  exit 1
fi

# 检查必要的包文件是否存在
LINUX_PKG=$(ls "$KERNEL_DIR"/linux-xiaomi-raphael-*.pkg.tar.zst 2>/dev/null | head -n 1)
FIRMWARE_PKG=$(ls "$KERNEL_DIR"/firmware-xiaomi-raphael-*.pkg.tar.zst 2>/dev/null | head -n 1)
ALSA_PKG=$(ls "$KERNEL_DIR"/alsa-xiaomi-raphael-*.pkg.tar.zst 2>/dev/null | head -n 1)

if [ -z "$LINUX_PKG" ]; then
  log_error "未找到内核包: linux-xiaomi-raphael-*.pkg.tar.zst"
  exit 1
fi

if [ -z "$FIRMWARE_PKG" ]; then
  log_error "未找到固件包: firmware-xiaomi-raphael-*.pkg.tar.zst"
  exit 1
fi

log_info "找到的包:"
echo "  - $(basename "$LINUX_PKG")"
echo "  - $(basename "$FIRMWARE_PKG")"
[ -n "$ALSA_PKG" ] && echo "  - $(basename "$ALSA_PKG")"
echo ""

# 复制内核包到临时目录
cp "$LINUX_PKG" rootdir/tmp/
cp "$FIRMWARE_PKG" rootdir/tmp/
[ -n "$ALSA_PKG" ] && cp "$ALSA_PKG" rootdir/tmp/

# 使用 pacman 安装内核包
log_info "安装内核包..."
chroot rootdir pacman -U --noconfirm "/tmp/$(basename "$LINUX_PKG")" || {
  log_error "安装内核包失败"
  exit 1
}

chroot rootdir pacman -U --noconfirm "/tmp/$(basename "$FIRMWARE_PKG")" || {
  log_error "安装固件包失败"
  exit 1
}

if [ -n "$ALSA_PKG" ]; then
  chroot rootdir pacman -U --noconfirm "/tmp/$(basename "$ALSA_PKG")" || {
    log_warn "安装 ALSA 包失败（非致命错误）"
  }
fi

# 清理临时文件
rm -f rootdir/tmp/*.pkg.tar.zst
log_info "内核包安装完成"

# 配置 mkinitcpio
cat > rootdir/etc/mkinitcpio.conf << 'EOF'
# vim:set ft=sh
# MODULES
# The following modules are loaded before any boot hooks are
# run.  Advanced users may wish to specify all system modules
# in this array.  For instance:
#     MODULES=(piix ide_disk reiserfs)
MODULES=()

# BINARIES
# This setting includes any additional binaries a given user may
# wish into the CPIO image.  This is run last, so it may be used to
# override the actual binaries included by a given hook
# BINARIES are dependency parsed, so you may safely ignore libraries
BINARIES=()

# FILES
# This setting is similar to BINARIES above, however, files are added
# as-is and are not parsed in any way.  This is useful for config files.
FILES=()

# HOOKS
# This is the most important setting in this file.  The HOOKS control the
# modules and scripts added to the image, and what happens at boot time.
# Order is important, and hooks listed first will be executed before hooks
# listed later.
#
#   base:         sets up all basic directories (e.g. /proc, /dev) and
#                 installs base utilities and libraries.
#   udev:         copies /dev files from host, creates temporary devices.
#   autodetect:  shrinks your initramfs to a smaller size by autodetecting
#                 your needed modules. Be sure to verify this works for your
#                 system.
#   modconf:      adds modprobe from the command line.
#   block:        adds block device filesystem support.
#   filesystems:  adds filesystem support.
#   keyboard:     adds keyboard support (needed for encrypted systems).
#   keymap:       adds keymap support (needed for encrypted systems).
#   encrypt:      adds dm-crypt support (needed for encrypted systems).
#   fsck:         adds filesystem check support.
#   resume:       adds resume support (needed for hibernation).
#
# An example HOOKS setting is:
#   HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)
#
# For more information about mkinitcpio, please see:
#   https://wiki.archlinux.org/title/Mkinitcpio

HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)

# COMPRESSION
# Use this to compress the initramfs image. By default, gzip compression
# is used. Use 'cat' to create an uncompressed image.
#COMPRESSION="gzip"
#COMPRESSION="bzip2"
#COMPRESSION="lzma"
#COMPRESSION="xz"
#COMPRESSION="lzop"
#COMPRESSION="lz4"

# COMPRESSION_OPTIONS
# Additional options for the compressor
#COMPRESSION_OPTIONS=()
EOF

# 生成 initramfs
log_info "生成 initramfs..."
chroot rootdir mkinitcpio -P || {
  log_error "生成 initramfs 失败"
  exit 1
}

# 启用 systemd 服务
log_info "启用 systemd 服务..."
chroot rootdir systemctl enable NetworkManager || log_warn "启用 NetworkManager 失败"
chroot rootdir systemctl enable bluetooth || log_warn "启用 bluetooth 失败"
chroot rootdir systemctl enable sshd || log_warn "启用 sshd 失败"

# 根据桌面环境启用对应的显示管理器
case "$DESKTOP_ENV" in
  "gnome")
    chroot rootdir systemctl enable gdm || log_warn "启用 gdm 失败"
    ;;
  "plasma"|"lxqt")
    chroot rootdir systemctl enable sddm || log_warn "启用 sddm 失败"
    ;;
  "xfce"|"mate"|"lxde")
    chroot rootdir systemctl enable lightdm || log_warn "启用 lightdm 失败"
    ;;
  "none")
    log_info "无桌面环境，跳过显示管理器"
    ;;
esac

# 配置 NCM
cat > rootdir/etc/dnsmasq.d/usb-ncm.conf << 'EOF'
interface=usb0
bind-dynamic
port=0
dhcp-authoritative
dhcp-range=172.16.42.2,172.16.42.254,255.255.255.0,1h
dhcp-option=3,172.16.42.1
EOF
echo "net.ipv4.ip_forward=1" | tee rootdir/etc/sysctl.d/99-usb-ncm.conf
chroot rootdir systemctl enable dnsmasq
cat > rootdir/usr/local/sbin/setup-usb-ncm.sh << 'EOF'
#!/bin/sh
set -e
modprobe libcomposite
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
G=/sys/kernel/config/usb_gadget/g1
mkdir -p $G
echo 0x1d6b > $G/idVendor
echo 0x0104 > $G/idProduct
echo 0x0200 > $G/bcdUSB
mkdir -p $G/strings/0x409
echo xiaomi-raphael > $G/strings/0x409/manufacturer
echo NCM > $G/strings/0x409/product
echo $(cat /etc/machine-id) > $G/strings/0x409/serialnumber
mkdir -p $G/configs/c.1
mkdir -p $G/configs/c.1/strings/0x409
echo NCM > $G/configs/c.1/strings/0x409/configuration
mkdir -p $G/functions/ncm.usb0
ln -sf $G/functions/ncm.usb0 $G/configs/c.1/
UDC=$(ls /sys/class/udc | head -n 1)
echo $UDC > $G/UDC
ip link set usb0 up
ip addr add 172.16.42.1/24 dev usb0 || true
OUT=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -C POSTROUTING -o $OUT -j MASQUERADE || iptables -t nat -A POSTROUTING -o $OUT -j MASQUERADE
iptables -C FORWARD -i $OUT -o usb0 -m state --state RELATED,ESTABLISHED -j ACCEPT || iptables -A FORWARD -i $OUT -o usb0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -C FORWARD -i usb0 -o $OUT -j ACCEPT || iptables -A FORWARD -i usb0 -o $OUT -j ACCEPT
systemctl restart dnsmasq || true
EOF
chmod +x rootdir/usr/local/sbin/setup-usb-ncm.sh
cat > rootdir/etc/systemd/system/usb-ncm.service << 'EOF'
[Unit]
Description=USB CDC-NCM gadget setup
After=network.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/setup-usb-ncm.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
chroot rootdir systemctl enable usb-ncm

# 配置 fstab
echo "PARTLABEL=userdata / ext4 errors=remount-ro,x-systemd.growfs 0 1
PARTLABEL=cache /boot vfat umask=0077 0 1" | tee rootdir/etc/fstab

# 创建默认用户
echo "root:1234" | chroot rootdir chpasswd
chroot rootdir useradd -m -G wheel -s /bin/bash zl
echo "zl:1234" | chroot rootdir chpasswd

# 配置 sudo 权限
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" | tee rootdir/etc/sudoers.d/wheel

# 配置 SSH（允许 root 登录，无密码限制）
echo "PermitRootLogin yes" | tee -a rootdir/etc/ssh/sshd_config
echo "PasswordAuthentication yes" | tee -a rootdir/etc/ssh/sshd_config

# 配置输入法环境变量
cat >> rootdir/etc/profile << 'EOF'
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
EOF

# 清理包缓存
chroot rootdir pacman -Scc --noconfirm

# 注意：Arch Linux 内核文件路径与 Debian 不同
# 如果使用 Arch Linux ARM 官方内核，文件路径为：
# - /boot/vmlinuz-linux (内核)
# - /boot/initramfs-linux.img (initramfs)
# - /boot/initramfs-linux-fallback.img (备用 initramfs)
# 设备树文件需要从定制的内核包中获取

# 删除 wifi 证书
rm -f rootdir/lib/firmware/reg*

# 卸载所有挂载点
log_info "卸载挂载点并清理..."
umount rootdir/sys 2>/dev/null || log_warn "卸载 /sys 失败"
umount rootdir/proc 2>/dev/null || log_warn "卸载 /proc 失败"
umount rootdir/dev/pts 2>/dev/null || log_warn "卸载 /dev/pts 失败"
umount rootdir/dev 2>/dev/null || log_warn "卸载 /dev 失败"
umount rootdir 2>/dev/null || log_warn "卸载 rootdir 失败"

# 删除临时目录
if [ -d "rootdir" ]; then
  rm -rf rootdir || log_warn "删除 rootdir 目录失败"
fi

# 设置文件系统 UUID
log_info "设置文件系统 UUID..."
tune2fs -U ee8d3593-59b1-480e-a3b6-4fefb17ee7d8 rootfs.img

echo ""
echo "=========================================="
log_info "镜像构建完成！"
echo "=========================================="
echo "生成的文件:"
echo "  - rootfs.img (未压缩)"
echo "  - rootfs.7z (压缩后)"
echo ""
echo "启动参数:"
echo '  cmdline for legacy boot: "root=PARTLABEL=userdata"'
echo ""
echo "默认账号:"
echo "  root / 1234"
echo "  zl / 1234 (sudo 免密)"
echo ""
log_info "结束时间: $(date)"
echo "=========================================="

# 压缩 rootfs 镜像
log_info "压缩 rootfs 镜像..."
7z a rootfs.7z rootfs.img || {
  log_error "压缩镜像失败"
  exit 1
}

# 清理未压缩的镜像文件（可选，节省空间）
# rm -f rootfs.img