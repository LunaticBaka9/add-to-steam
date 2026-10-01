#!/bin/sh
# 纯本地冒烟测试：不启动、不修改真实 Steam（用 PATH 里的 steam 桩拦截调用）
set -u

SRC=$(cd "$(dirname "$0")/.." && pwd)
BIN="$SRC/bin/add-to-steam"
MENU="$SRC/share/kio/servicemenus/add-to-steam.desktop"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/add-to-steam-test.XXXXXX") || exit 1
STUB="$WORK/stub"
mkdir -p "$STUB"

# 测试期间写自己的日志，别污染 ~/.cache/add-to-steam/add-to-steam.log
ADD_TO_STEAM_LOG="$WORK/run.log"
export ADD_TO_STEAM_LOG

pass_n=0
fail_n=0
pass() {
    pass_n=$((pass_n + 1))
    printf '  ok   %s\n' "$1"
}
fail() {
    fail_n=$((fail_n + 1))
    printf '  FAIL %s\n' "$1"
}
t() {
    _d=$1
    shift
    if "$@" >/dev/null 2>&1; then pass "$_d"; else fail "$_d"; fi
}
tf() {
    _d=$1
    shift
    if "$@" >/dev/null 2>&1; then fail "$_d（期望失败却成功了）"; else pass "$_d"; fi
}
eq() {
    _d=$1
    _got=$2
    _want=$3
    if [ "$_got" = "$_want" ]; then
        pass "$_d"
    else
        fail "$_d
       got  = [$_got]
       want = [$_want]"
    fi
}
rp() { readlink -f "$1"; }

expected_url() {
    python3 -c 'import sys,urllib.parse;print("steam://addnonsteamgame/"+urllib.parse.quote(sys.argv[1],safe=""))' "$1"
}

echo "== 1. 语法与静态校验 =="
for f in "$BIN" "$SRC/install.sh" "$SRC/uninstall.sh" "$SRC/tests/smoke.sh"; do
    t "sh -n $(basename "$f")" sh -n "$f"
done
# desktop-file-validate 不认识 KDE 服务菜单扩展（Actions/MimeType/TryExec 在
# Type=Service 下是合法的，系统自带的 /usr/share/kio/servicemenus/*.desktop 同样报这些错），
# 所以只要求“除了这些已知误报之外没有别的错误”。
if command -v desktop-file-validate >/dev/null 2>&1; then
    _dv=$(desktop-file-validate "$MENU" 2>&1 | grep -v 'only valid for type "Application"' || true)
    eq "desktop-file-validate（忽略 KDE 服务菜单误报）" "$_dv" ""
fi
# 关键回归项：服务菜单 .desktop 必须带可执行位。
# 否则 KIO 的 KDesktopFile::isAuthorizedDesktopFile() 会拒绝执行，
# 点击只得到「错误 — Dolphin：您没有此文件的执行权限。」，脚本根本不会被启动。
if [ -x "$MENU" ]; then
    pass "服务菜单 .desktop 有可执行位（KIO 授权检查必需）"
else
    fail "服务菜单 .desktop 缺少可执行位：KIO 会拒绝执行（chmod 755 $MENU）"
fi
t "--help 正常退出" "$BIN" --help
tf "无参数 → 非 0" "$BIN"
tf "未知参数 → 非 0" "$BIN" --bogus-flag /tmp
t "install.sh --help" "$SRC/install.sh" --help
t "uninstall.sh --help" "$SRC/uninstall.sh" --help

echo "== 2. 造测试文件 =="
EXE="$WORK/狼 狼's.exe"
printf 'MZ fake pe' >"$EXE"
DESK="$WORK/My Game.desktop"
printf '[Desktop Entry]\nName=My Game\nExec=true\n' >"$DESK"
APP="$WORK/App 测试.AppImage"
printf '#!/bin/sh\n' >"$APP"
chmod +x "$APP"
APP_NOX="$WORK/没有执行位.AppImage"
printf 'x' >"$APP_NOX"
NATIVE="$WORK/native tool"
printf '#!/bin/sh\n' >"$NATIVE"
chmod +x "$NATIVE"
NATIVE_NOX="$WORK/no exec bit"
printf 'x' >"$NATIVE_NOX"
TXT="$WORK/readme.txt"
printf 'x' >"$TXT"
DOLLAR="$WORK/a\$b\`c.exe"
printf 'MZ' >"$DOLLAR"
echo "  (临时目录 $WORK)"

echo "== 3. URL 编码（python 与纯 sh 兜底必须一致） =="
if command -v python3 >/dev/null 2>&1; then
    for f in "$EXE" "$DESK" "$APP" "$NATIVE" "$DOLLAR"; do
        want=$(expected_url "$(rp "$f")")
        eq "dry-run $(basename "$f")" "$("$BIN" --dry-run "$f" 2>/dev/null)" "$want"
        eq "sh 兜底编码 $(basename "$f")" "$(ADD_TO_STEAM_FORCE_SH_ENCODER=1 "$BIN" --dry-run "$f" 2>/dev/null)" "$want"
    done
    FF="file://$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe="/"))' "$(rp "$EXE")")"
    eq "file:// 形式归一化" "$("$BIN" --dry-run "$FF" 2>/dev/null)" "$(expected_url "$(rp "$EXE")")"
else
    echo "  skip （没有 python3，无法计算期望值）"
fi

echo "== 4. 类型门控 =="
t "exe 不要求 +x" "$BIN" --dry-run "$EXE"
t ".desktop 不要求 +x" "$BIN" --dry-run "$DESK"
t "AppImage 有 +x" "$BIN" --dry-run "$APP"
t "原生可执行文件有 +x" "$BIN" --dry-run "$NATIVE"
tf "AppImage 无 +x 被拒" "$BIN" --dry-run "$APP_NOX"
tf "原生文件无 +x 被拒" "$BIN" --dry-run "$NATIVE_NOX"
tf "文本文件被拒" "$BIN" --dry-run "$TXT"
tf "不存在的文件被拒" "$BIN" --dry-run "$WORK/不存在.exe"

echo "== 5. 全链路（steam 桩 + 哨兵文件） =="
cat >"$STUB/steam" <<'EOS'
#!/bin/sh
printf '%s\n' "$@" >>"$STUB_OUT"
EOS
chmod +x "$STUB/steam"
export STUB_OUT="$WORK/stub.out"

rm -f /tmp/addnonsteamgamefile
: >"$STUB_OUT"
PATH="$STUB:$PATH" "$BIN" "$EXE" >/dev/null 2>&1
i=0
while [ ! -s "$STUB_OUT" ] && [ "$i" -lt 40 ]; do
    sleep 0.05
    i=$((i + 1))
done
eq "桩收到正确的 steam:// URL" "$(cat "$STUB_OUT")" "$(expected_url "$(rp "$EXE")")"
eq "哨兵 /tmp/addnonsteamgamefile mode" "$(stat -c %a /tmp/addnonsteamgamefile 2>/dev/null || echo missing)" "600"
eq "哨兵文件存在" "$([ -f /tmp/addnonsteamgamefile ] && echo yes || echo no)" "yes"

: >"$STUB_OUT"
PATH="$STUB:$PATH" "$BIN" "$EXE" "$DESK" >/dev/null 2>&1
i=0
while [ "$(wc -l <"$STUB_OUT")" -lt 2 ] && [ "$i" -lt 40 ]; do
    sleep 0.05
    i=$((i + 1))
done
eq "多选发送 2 条" "$(wc -l <"$STUB_OUT")" "2"
eq "多选第 2 条是 .desktop" "$(sed -n 2p "$STUB_OUT")" "$(expected_url "$(rp "$DESK")")"

: >"$STUB_OUT"
t "干跑正常退出" env PATH="$STUB:$PATH" "$BIN" --dry-run "$EXE"
eq "干跑不发请求（桩没有输出）" "$(wc -c <"$STUB_OUT")" "0"

echo "== 6. 诊断日志（下次从 Dolphin 点击出错时靠它定位） =="
if grep -q 'REJECT reason=not-executable' "$ADD_TO_STEAM_LOG" 2>/dev/null; then
    pass "日志含 not-executable 记录"
else
    fail "日志缺 not-executable 记录"
fi
if grep -q 'REJECT reason=unsupported' "$ADD_TO_STEAM_LOG" 2>/dev/null; then
    pass "日志含 unsupported 记录"
else
    fail "日志缺 unsupported 记录"
fi
if grep -q 'ADD mime=' "$ADD_TO_STEAM_LOG" 2>/dev/null; then
    pass "日志含 ADD 记录"
else
    fail "日志缺 ADD 记录"
fi
if grep -q 'DRYRUN' "$ADD_TO_STEAM_LOG" 2>/dev/null; then
    pass "日志含 DRYRUN 记录"
else
    fail "日志缺 DRYRUN 记录"
fi

echo
echo "== 结果：通过 $pass_n，失败 $fail_n =="
rm -rf "$WORK"
[ "$fail_n" -eq 0 ] || exit 1
exit 0
