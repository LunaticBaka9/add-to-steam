#!/bin/sh
# 卸载 add-to-steam 的用户级安装（不动 Steam 库里的任何条目）
#
#   ./uninstall.sh            删除 ~/.local 下的两个文件
#   ./uninstall.sh --system   删除 /usr/local 下的两个文件（需要 sudo）
set -eu

MODE=user
for arg in "$@"; do
    case $arg in
    --system) MODE=system ;;
    -h | --help)
        sed -n '2,6p' "$0"
        exit 0
        ;;
    *)
        echo "未知参数: $arg" >&2
        exit 2
        ;;
    esac
done

if [ "$MODE" = system ]; then
    BIN_DIR=/usr/local/bin
    MENU_DIR=/usr/local/share/kio/servicemenus
else
    BIN_DIR="${HOME}/.local/bin"
    MENU_DIR="${HOME}/.local/share/kio/servicemenus"
fi

for f in "$BIN_DIR/add-to-steam" "$MENU_DIR/add-to-steam.desktop"; do
    if [ -e "$f" ] || [ -L "$f" ]; then
        rm -f "$f" && echo "已删除 $f"
    else
        echo "跳过（不存在）$f"
    fi
done

echo
echo "重开 Dolphin 后右键菜单项即消失。已加入 Steam 库的条目需要自己在 Steam 里移除"
echo "（库中右键游戏 → 管理 → 移除非 Steam 游戏）。"
