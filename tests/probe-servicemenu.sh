#!/bin/sh
# 编译并运行 KFileItemActions 探针，验证 Dolphin 能发现「添加到 Steam」服务菜单。
#
#   ./probe-servicemenu.sh [被测文件]
#
# KF6 在 Arch 上没有 pkg-config 文件，include/lib 只能手写；编译/运行失败就跳过
# （以 Dolphin 里肉眼确认为准，不作为硬性验收门槛）。
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/probe-servicemenu.XXXXXX")
OUT="$WORK/probe-servicemenu"
TARGET=${1:-$HERE/../bin/add-to-steam}

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

if ! command -v g++ >/dev/null 2>&1; then
    echo "skip: 没有 g++"
    exit 0
fi

INCS=''
for d in /usr/include/KF6/*; do
    [ -d "$d" ] && INCS="$INCS -I$d"
done

# shellcheck disable=SC2046
QF=$(pkg-config --cflags --libs Qt6Core Qt6Gui Qt6Widgets 2>/dev/null)

# shellcheck disable=SC2086
if ! g++ -fPIC -O0 "$HERE/probe-servicemenu.cpp" -o "$OUT" $QF $INCS \
    -lKF6KIOWidgets -lKF6KIOGui -lKF6KIOCore -lKF6Service -lKF6ConfigCore -lKF6CoreAddons \
    -lKF6JobWidgets -lKF6WindowSystem -lKF6ItemViews -lKF6WidgetsAddons -lKF6Completion \
    -lKF6Bookmarks -lKF6Solid 2>"$WORK/build.log"; then
    echo "skip: 探针编译失败（$(grep -m1 -E 'error|fatal' "$WORK/build.log" || head -n1 "$WORK/build.log")）"
    exit 0
fi

echo "probe: $TARGET"
ACTIONS=$("$OUT" "$TARGET" 2>&1 || true)
printf '%s\n' "$ACTIONS" | sed 's/^/  /'

if printf '%s\n' "$ACTIONS" | grep -qi 'Add to Steam\|添加到 Steam'; then
    echo "结果：KIO 能发现该服务菜单 ✓"
else
    echo "结果：没有在 action 列表里看到「Add to Steam」✗"
    exit 1
fi
