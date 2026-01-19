#!/bin/sh
set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查必要的工具
check_dependencies() {
  echo -e "${GREEN}[INFO]${NC} 检查编译依赖..."
  
  missing_deps=""
  
  for cmd in debootstrap truncate mkfs.ext4 wget mount umount cp rm; do
    if ! command -v $cmd >/dev/null 2>&1; then
      missing_deps="$missing_deps $cmd"
    fi
  done
  
  if [ -n "$missing_deps" ]; then
    echo -e "${RED}[ERROR]${NC} 缺少必要的依赖:$missing_deps"
    echo "请安装: sudo apt install -y debootstrap qemu-user-static binfmt-support"
    exit 1
  fi
  
  echo -e "${GREEN}[INFO]${NC} 所有依赖已安装"
}

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]
then
  echo -e "${RED}[ERROR]${NC} rootfs can only be built as root"
  exit 1
fi

# 检查依赖
check_dependencies

# 获取参数
PLACEHOLDER="${1:-}"
KERNEL_VERSION="${2:-6.18}"
DESKTOP_ENV="${3:-gnome}"

# 验证参数
validate_params() {
  # 验证内核版本格式（简单的版本号验证）
  if ! echo "$KERNEL_VERSION" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
    echo -e "${RED}[ERROR]${NC} 无效的内核版本格式: $KERNEL_VERSION"
    echo -e "${GREEN}[INFO]${NC} 正确格式: 6.18 或 6.18.1"
    exit 1
  fi

  # 验证桌面环境
  case "$DESKTOP_ENV" in
    gnome|plasma|xfce|mate|lxqt|lxde|none|phosh-core|phosh-full|phosh-phone)
      ;;
    *)
      echo -e "${RED}[ERROR]${NC} 无效的桌面环境: $DESKTOP_ENV"
      echo -e "${GREEN}[INFO]${NC} 支持的桌面环境: gnome, plasma, xfce, mate, lxqt, lxde, none, phosh-core, phosh-full, phosh-phone"
      exit 1
      ;;
  esac
}

# 验证参数
validate_params

# 设置 Debian 版本
DEBIAN_VERSION="trixie"

echo "=========================================="
echo "  Debian 镜像构建"
echo "=========================================="
echo -e "${GREEN}[INFO]${NC} 构建配置:"
echo -e "${GREEN}[INFO]${NC}   桌面环境: $DESKTOP_ENV"
echo -e "${GREEN}[INFO]${NC}   内核版本: $KERNEL_VERSION"
echo -e "${GREEN}[INFO]${NC}   开始时间: $(date)"
echo ""

# 创建根文件系统镜像
echo -e "${GREEN}[INFO]${NC} 创建根文件系统镜像..."
truncate -s 6G rootfs.img
mkfs.ext4 rootfs.img
mkdir rootdir
mount -o loop rootfs.img rootdir

# debootstrap生成镜像
echo -e "${GREEN}[INFO]${NC} 使用 debootstrap 安装系统..."
debootstrap --arch=arm64 $DEBIAN_VERSION rootdir https://mirrors.tuna.tsinghua.edu.cn/debian/

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

# Chroot 安装步骤
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH
export DEBIAN_FRONTEND=noninteractive

# 配置清华镜像源
cat > rootdir/etc/apt/sources.list << 'EOF'
deb http://mirrors.tuna.tsinghua.edu.cn/debian/ trixie main contrib non-free non-free-firmware
deb http://mirrors.tuna.tsinghua.edu.cn/debian/ trixie-updates main contrib non-free non-free-firmware
deb http://mirrors.tuna.tsinghua.edu.cn/debian/ trixie-backports main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF

# 更新系统
chroot rootdir apt update
chroot rootdir apt upgrade -y

# 安装基础软件包
chroot rootdir apt install -y bash-completion sudo apt-utils ssh openssh-server nano systemd-boot initramfs-tools chrony curl wget dnsmasq iptables iproute2

# 根据桌面环境参数安装对应的桌面环境
case "$DESKTOP_ENV" in
  "gnome")
    echo -e "${GREEN}[INFO]${NC} 安装 GNOME 桌面环境..."
    chroot rootdir apt install -y gnome gnome-desktop-environment gnome-tweaks gnome-system-monitor gnome-software gnome-text-editor gnome-logs gnome-extensions gnome-control-center gnome-backgrounds gnome-screenshot gnome-calculator gnome-calendar gnome-clocks gnome-maps gnome-music gnome-photos gnome-screenshot gnome-terminal gnome-user-docs
    chroot rootdir apt install -y xorg xorg-xinit xserver-xorg xserver-xorg-video-all xserver-xorg-input-all
    chroot rootdir apt install -y nautilus file-roller eog evince firefox
    ;;
  "plasma")
    echo -e "${GREEN}[INFO]${NC} 安装 KDE Plasma 桌面环境..."
    chroot rootdir apt install -y plasma-desktop plasma-workspace plasma-meta plasma-apps kde-standard konsole dolphin kate gwenview firefox sddm
    chroot rootdir apt install -y xorg xorg-xinit xserver-xorg xserver-xorg-video-all xserver-xorg-input-all
    ;;
  "xfce")
    echo -e "${GREEN}[INFO]${NC} 安装 XFCE 桌面环境..."
    chroot rootdir apt install -y xfce4 xfce4-goodies xfce4-terminal xfce4-power-manager xfce4-screenshooter xfce4-session xfce4-settings xfce4-panel xfce4-mixer xfce4-whiskermenu-plugin xfce4-taskmanager xfce4-appfinder
    chroot rootdir apt install -y thunar thunar-archive-plugin thunar-media-tags-plugin thunar-volman
    chroot rootdir apt install -y xorg xorg-xinit xserver-xorg xserver-xorg-video-all xserver-xorg-input-all
    chroot rootdir apt install -y firefox lightdm lightdm-gtk-greeter
    ;;
  "mate")
    echo -e "${GREEN}[INFO]${NC} 安装 MATE 桌面环境..."
    chroot rootdir apt install -y mate-desktop-environment mate-desktop-environment-extra mate-panel mate-control-center mate-system-tools mate-utils mate-screensaver mate-power-manager mate-polkit mate-indicator-applet mate-media mate-sensors-applet mate-terminal caja pluma
    chroot rootdir apt install -y xorg xorg-xinit xserver-xorg xserver-xorg-video-all xserver-xorg-input-all
    chroot rootdir apt install -y mate-terminal caja pluma
    chroot rootdir apt install -y firefox lightdm lightdm-gtk-greeter
    ;;
  "lxqt")
    echo -e "${GREEN}[INFO]${NC} 安装 LXQt 桌面环境..."
    chroot rootdir apt install -y lxqt-core lxqt-meta lxqt-session lxqt-panel lxqt-runner lxqt-policykit lxqt-powermanagement lxqt-sudo lxqt-about lxqt-config lxqt-globalkeys lxqt-notificationd lxqt-openssh-ui lxqt-policykit lxqt-powermanagement lxqt-qtplugin lxqt-sudo lxqt-trayicon lxqt-wallpaper lxqt-wallet lxqt-webkit
    chroot rootdir apt install -y qterminal pcmanfm-qt leafpad
    chroot rootdir apt install -y xorg xorg-xinit xserver-xorg xserver-xorg-video-all xserver-xorg-input-all
    chroot rootdir apt install -y firefox sddm
    ;;
  "lxde")
    echo -e "${GREEN}[INFO]${NC} 安装 LXDE 桌面环境..."
    chroot rootdir apt install -y lxde lxde-common lxde-icon-theme lxde-common lxterminal pcmanfm lxappearance lxmenu-data lxpolkit
    chroot rootdir apt install -y xorg xorg-xinit xserver-xorg xserver-xorg-video-all xserver-xorg-input-all
    chroot rootdir apt install -y lxterminal pcmanfm leafpad
    chroot rootdir apt install -y firefox lightdm lightdm-gtk-greeter
    ;;
  "phosh-core"|"phosh-full"|"phosh-phone")
    echo -e "${GREEN}[INFO]${NC} 安装 Phosh 桌面环境..."
    chroot rootdir apt install -y phosh phosh-core gnome-terminal gnome-tweaks gnome-system-monitor gnome-software gnome-text-editor gnome-logs gnome-extensions gnome-control-center gnome-backgrounds gnome-screenshot gnome-calculator gnome-calendar gnome-clocks gnome-maps gnome-music gnome-photos gnome-screenshot gnome-terminal gnome-user-docs
    chroot rootdir apt install -y xorg xorg-xinit xserver-xorg xserver-xorg-video-all xserver-xorg-input-all
    chroot rootdir apt install -y nautilus file-roller eog evince firefox
    ;;
  "none")
    echo -e "${GREEN}[INFO]${NC} 无桌面环境，仅安装基础系统..."
    # 不安装任何桌面环境
    ;;
  *)
    echo -e "${RED}[ERROR]${NC} 未知的桌面环境: $DESKTOP_ENV"
    echo -e "${GREEN}[INFO]${NC} 支持的桌面环境: gnome, plasma, xfce, mate, lxqt, lxde, none, phosh-core, phosh-full, phosh-phone"
    exit 1
    ;;
esac

# 安装设备特定软件包
chroot rootdir apt install -y rmtfs protection-domain-mapper tqftpserv

# 安装语言包和设置默认语言为简体中文
chroot rootdir apt install -y locales locales-all tzdata
	
chroot rootdir sed -i 's/^# *zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
chroot rootdir locale-gen zh_CN.UTF-8
chroot rootdir update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh
echo "Asia/Shanghai" | tee rootdir/etc/timezone
chroot rootdir ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
chroot rootdir dpkg-reconfigure -f noninteractive tzdata

# 修改服务配置
sed -i '/ConditionKernelVersion/d' rootdir/lib/systemd/system/pd-mapper.service

# 复制并安装内核包（从预下载的目录）
cp xiaomi-raphael-debs_$2/*-xiaomi-raphael.deb rootdir/tmp/
chroot rootdir dpkg -i /tmp/linux-xiaomi-raphael.deb
chroot rootdir dpkg -i /tmp/firmware-xiaomi-raphael.deb
chroot rootdir dpkg -i /tmp/alsa-xiaomi-raphael.deb
rm rootdir/tmp/*-xiaomi-raphael.deb
chroot rootdir update-initramfs -c -k all

# 启用 Phosh 服务
chroot rootdir systemctl enable phosh

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
chroot rootdir useradd -m -G sudo -s /bin/bash zl
echo "zl:1234" | chroot rootdir chpasswd

# 配置 sudo 免密
echo "%sudo ALL=(ALL:ALL) NOPASSWD: ALL" | tee rootdir/etc/sudoers.d/nopasswd

# 配置 SSH（允许 root 登录）
echo "PermitRootLogin yes" | tee -a rootdir/etc/ssh/sshd_config
echo "PasswordAuthentication yes" | tee -a rootdir/etc/ssh/sshd_config

# 清理 apt 缓存
chroot rootdir apt clean

# 生成 boot 镜像
mkdir -p boot_tmp
wget https://github.com/GengWei1997/kernel-deb/releases/download/v1.0.0/xiaomi-k20pro-boot.img
mount -o loop xiaomi-k20pro-boot.img boot_tmp

# 复制 boot 文件
cp -r rootdir/boot/dtbs/qcom boot_tmp/dtbs/
cp rootdir/boot/config-* boot_tmp/
cp rootdir/boot/initrd.img-* boot_tmp/initramfs
cp rootdir/boot/vmlinuz-* boot_tmp/linux.efi

umount boot_tmp
rm -d boot_tmp

# 删除 wifi 证书
rm -f rootdir/lib/firmware/reg*

# 卸载所有挂载点
umount rootdir/sys 2>/dev/null || true
umount rootdir/proc 2>/dev/null || true
umount rootdir/dev/pts 2>/dev/null || true
umount rootdir/dev 2>/dev/null || true
umount rootdir 2>/dev/null || true

rm -rf rootdir 2>/dev/null || true

# 设置文件系统 UUID
tune2fs -U ee8d3593-59b1-480e-a3b6-4fefb17ee7d8 rootfs.img

echo 'cmdline for legacy boot: "root=PARTLABEL=userdata"'

# 压缩 rootfs 镜像
7z a rootfs.7z rootfs.img