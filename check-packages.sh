#!/bin/bash

# 检查 Debian 脚本中的软件包是否存在
echo "检查 Debian 脚本中的软件包..."

# 创建临时文件
TEMP_FILE=$(mktemp)

# 提取所有软件包名称
grep -oE '[a-zA-Z0-9\-_]+[a-zA-Z0-9_\-]*' /data/data/com.termux/files/home/linux-xiaomi-raphael-uboot/debian-desktop_build.sh | \
  grep -v '^chroot$' | \
  grep -v '^apt$' | \
  grep -v '^install$' | \
  grep -v '^-$' | \
  sort -u > "$TEMP_FILE"

# 检查每个软件包
echo "检查软件包是否存在..."
while read package; do
  if apt list --installed 2>/dev/null | grep -q "$package/"; then
    echo "✅ $package (已安装)"
  elif apt search "$package" 2>/dev/null | grep -q "^$package/"; then
    echo "✅ $package (可用)"
  else
    echo "❌ $package (不存在)"
  fi
done < "$TEMP_FILE"

rm -f "$TEMP_FILE"