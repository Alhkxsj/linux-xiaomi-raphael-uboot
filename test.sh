#!/bin/bash
echo "测试脚本语法..."
sh -n /data/data/com.termux/files/home/linux-xiaomi-raphael-uboot/debian-desktop_build.sh && echo "✅ debian-desktop_build.sh 语法正确"
sh -n /data/data/com.termux/files/home/linux-xiaomi-raphael-uboot/ubuntu-desktop_build.sh && echo "✅ ubuntu-desktop_build.sh 语法正确"
echo "测试完成！"