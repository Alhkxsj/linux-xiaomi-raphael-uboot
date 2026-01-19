# 小米 Raphael 设备 Linux 系统镜像构建项目

本项目提供用于小米 Raphael 设备（Redmi K20 Pro）的 Debian/Ubuntu/Arch Linux 系统镜像构建脚本和自动化工作流。

## 📋 功能支持

- ✅ Wi-Fi (2.4Ghz，5Ghz)
- ✅ 蓝牙 (文件传输，音频)
- ✅ USB (ssh，OTG)
- ✅ 电池
- ✅ 实时时钟
- ✅ 显示
- ✅ 触摸
- ✅ 手电筒 (LED及强度调节)
- ✅ GPU
- ✅ FDE

## 🚀 使用 GitHub Actions 自动化构建

### 构建内核
1. Fork 本仓库到你的 GitHub 账户
2. 进入 Actions 页面，选择 "内核编译" 工作流
3. 点击 "Run workflow"，输入内核版本号（如 `6.18`）
4. 等待构建完成，产物将自动发布到 Releases

### 构建系统镜像
1. 选择 "构建系统镜像" 工作流
2. 点击 "Run workflow"，配置参数：
   - 系统类型：`debian-desktop`/`debian-server`/`ubuntu-desktop`/`ubuntu-server`/`arch-desktop`/`arch-server`
   - 内核版本号：上一步构建的内核版本号
   - 桌面环境（仅桌面版）：`phosh-core`/`phosh-full`/`phosh-phone`/`gnome`
3. 等待构建完成，镜像将自动发布到 Releases

## 💻 本地构建

### 构建 Debian/Ubuntu 内核
```bash
# 安装依赖
sudo apt install -y build-essential gcc-aarch64-linux-gnu bc flex bison \
  7zip kmod bash cpio binutils tar git wget dpkg libssl-dev clang llvm lld \
  libelf-dev python3 rsync

# 构建内核（版本 6.18）
sudo sh raphael-kernel_build.sh 6.18
```

### 构建 Arch Linux 内核
```bash
# 安装依赖
sudo apt install -y build-essential clang llvm lld bc bison flex openssl \
  python3 git wget zstd ccache

# 构建内核（版本 6.18）
sudo sh raphael-kernel-arch_build.sh 6.18
```

### 构建系统镜像
```bash
# 安装依赖
sudo apt install -y debootstrap arch-install-scripts zstd 7zip

# 构建镜像（需要先下载对应格式的内核包）
sudo sh debian-desktop_build.sh "" 6.18 gnome
sudo sh ubuntu-desktop_build.sh "" 6.18 gnome
sudo sh arch-desktop_build.sh "" 6.18 gnome
```

## 📦 镜像特性

### 通用特性
- ✅ 清华大学软件源
- ✅ 简体中文语言环境
- ✅ 中国标准时区
- ✅ 支持NCM（USB连接电脑，SSH示例：`ssh user@172.16.42.1`）
- ✅ 预装 SSH 服务器，允许 root 登录
- ✅ 包含必要的设备驱动和固件
- ✅ 默认用户：`zl`（密码：`1234`），`root`（密码：`1234`）
- ✅ [一键更新内核脚本](https://github.com/GengWei1997/kernel-deb)

### 桌面版额外特性
- ✅ Phosh 移动桌面环境

### 服务器版额外特性
- ✅ 网络管理器
- ✅ 开机15秒后自动熄屏
- ✅ 命令行输入 `leijun` 关闭屏幕，`jinfan` 打开屏幕

## 🔧 安装到设备

### 准备工作
1. **解锁 Bootloader**：确保设备已解锁 Bootloader
2. **安装工具**：安装 `fastboot` 和 `adb`

### 刷机步骤

```bash
# 1. 进入 Fastboot 模式
adb reboot bootloader

# 2. 刷入 boot 镜像
fastboot flash cache xiaomi-k20pro-boot.img
fastboot flash boot u-boot.img

# 3. 刷入系统镜像（需要先解压 rootfs.7z）
fastboot flash userdata rootfs.img

# 4. 擦除dtbo分区
fastboot erase dtbo

# 5. 重启设备
fastboot reboot
```

## ❓ 常见问题

### Server 版网络连接方式
1. OTG 连接网线，系统会自动识别
2. OTG 连接键盘，输入 `nmtui` 连接 WiFi
3. USB 连接电脑，安装好 NCM 驱动后输入 `nmtui` 连接 WiFi

### 其他问题
- [解决 Windows 下无法连接使用 CDC NCM 驱动](https://www.bilibili.com/video/BV1tW4y1A79V/)

## 🔧 故障排除

### GitHub Actions 构建失败

#### 内核编译失败
- 检查 Actions 日志中的错误信息
- 确认内核版本号正确
- 尝试使用较小的内核版本

#### 系统镜像构建失败
- 确保先成功构建对应版本的内核
- 检查 Release 是否包含正确的文件
- Arch Linux 需要使用 `.pkg.tar.zst` 格式的内核包
- Debian/Ubuntu 需要使用 `.deb` 格式的内核包

### 本地构建失败

#### 内核编译失败
```bash
# 检查依赖是否安装
which clang ld.lld llvm-ar
clang --version
ld.lld --version

# 检查系统资源
free -h
df -h
```

#### 系统镜像构建失败
```bash
# 检查内核包是否存在
ls -la xiaomi-raphael-debs_6.18/

# 检查依赖是否安装
which debootstrap pacstrap
```

### Arch Linux 特定问题

#### pacman 密钥问题
```bash
# 在 chroot 中执行
chroot rootdir pacman-key --init
chroot rootdir pacman-key --populate archlinuxarm
```

## 🙏 致谢

- [@cuicanmx](https://github.com/cuicanmx) - 提供帮助以及创新思路
- [@map220v](https://github.com/map220v/ubuntu-xiaomi-nabu) - 原项目
- [@Pc1598](https://github.com/Pc1598) - sm8150-mainline-raphael 内核维护
- [Aospa-raphael-unofficial/linux](https://github.com/Aospa-raphael-unofficial/linux) - 内核项目
- [sm8150-mainline/linux](https://gitlab.com/sm8150-mainline/linux) - 内核项目