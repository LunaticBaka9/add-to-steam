#!/bin/sh
# 用户级安装 add-to-steam（无需 root）
#
#   ./install.sh            复制到 ~/.local（推荐）
#   ./install.sh --link     改为软链到本仓库（方便开发时改完即生效）
#   ./install.sh --system   安装到 /usr/local（需要 sudo，自己加 sudo 运行）
set -eu

SRC=$(cd "$(dirname "$0")" && pwd)
MODE=user
LINK=0

for arg in "$@"; do
    case $arg in
    --link) LINK=1 ;;
    --system) MODE=system ;;
    -h | --help)
        sed -n '2,8p' "$0"
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

backup_if_exists() {
    [ -e "$1" ] || return 0
    [ -L "$1" ] && return 0
    if cmp -s "$2" "$1" 2>/dev/null; then
        return 0
    fi
    _bak="$1.bak-$(date +%Y%m%d-%H%M%S)"
    cp -p "$1" "$_bak" 2>/dev/null && echo "已备份旧文件 -> $_bak"
}

mkdir -p "$BIN_DIR" "$MENU_DIR"
backup_if_exists "$BIN_DIR/add-to-steam" "$SRC/bin/add-to-steam"
backup_if_exists "$MENU_DIR/add-to-steam.desktop" "$SRC/share/kio/servicemenus/add-to-steam.desktop"

if [ "$LINK" = 1 ]; then
    ln -sf "$SRC/bin/add-to-steam" "$BIN_DIR/add-to-steam"
    ln -sf "$SRC/share/kio/servicemenus/add-to-steam.desktop" "$MENU_DIR/add-to-steam.desktop"
    # KIO 的 KDesktopFile::isAuthorizedDesktopFile() 授权检查：非可信目录下的
    # .desktop 必须带可执行位，否则点击只会得到 “错误 — Dolphin：您没有此文件的执行权限。”
    chmod 755 "$SRC/share/kio/servicemenus/add-to-steam.desktop"
    echo "已软链到 $SRC"
else
    install -Dm755 "$SRC/bin/add-to-steam" "$BIN_DIR/add-to-steam"
    # 服务菜单 .desktop 必须 755：见上面 KDesktopFile::isAuthorizedDesktopFile 的说明
    install -Dm755 "$SRC/share/kio/servicemenus/add-to-steam.desktop" "$MENU_DIR/add-to-steam.desktop"
    echo "已安装（复制）"
fi
chmod 755 "$MENU_DIR/add-to-steam.desktop" 2>/dev/null || true

echo "  $BIN_DIR/add-to-steam"
echo "  $MENU_DIR/add-to-steam.desktop"

case ":${PATH}:" in
*":$BIN_DIR:"*) ;;
*) echo "警告：$BIN_DIR 不在 PATH 里，Dolphin 可能找不到 add-to-steam（可改用 --system）" ;;
esac

command -v steam >/dev/null 2>&1 || echo "警告：PATH 里没有 steam（Flatpak 版 Steam 会被脚本自动识别）"
command -v python3 >/dev/null 2>&1 || echo "提示：没有 python3，脚本会用 od 兜底做 URL 编码（结果一致）"

if command -v desktop-file-validate >/dev/null 2>&1; then
    # desktop-file-validate 不认识 KDE 服务菜单扩展（Type=Service 下的 Actions/MimeType/TryExec
    # 是合法的，系统自带的 /usr/share/kio/servicemenus/*.desktop 同样报这些错），过滤掉这些误报。
    _dv=$(desktop-file-validate "$MENU_DIR/add-to-steam.desktop" 2>&1 | grep -v 'only valid for type "Application"' || true)
    if [ -z "$_dv" ]; then
        echo "desktop 文件校验通过（已忽略 KDE 服务菜单的已知误报）"
    else
        echo "$_dv"
    fi
fi

echo
echo "下一步：重开一个 Dolphin 窗口（或重启 plasmashell），右键 .exe/.desktop/.AppImage 即可看到「添加到 Steam」。"
echo "命令行自检：add-to-steam --dry-run /path/to/game.exe"
