# add-to-steam — CachyOS / KDE 上的 Dolphin 右键「添加到 Steam」

在 CachyOS（KDE Plasma 6 + 原生 Steam）上复刻 SteamOS 桌面模式的 **Add to Steam**：
在 Dolphin 里右键 `.exe` / `.desktop` / `.AppImage` / 原生可执行文件，一键作为
「非 Steam 游戏」加进 Steam 库。

- **不用重启 Steam**（运行中的客户端会立即收到请求，实测 1～2 秒出现在库里）
- **`.exe` 不需要 `chmod +x`**（Proton 场景，与 SteamOS 行为一致）
- 路径含**空格、中文、单引号、`$`、反引号**都能正确添加（已用测试固化）
- **纯用户级安装**，不动系统包、不用 root、一条命令卸载

本目录在你的机器上实测通过（Steam `1.0.0.87-3`、Dolphin `26.08.1`、Plasma `6.7.5`、KIO `6.30.0`）。

---

## 1. 原理

Steam 客户端支持一个**未公开**的 URL scheme：

```
steam://addnonsteamgame/<percent-encoded 绝对路径>
```

发送前需要先创建哨兵文件 `/tmp/addnonsteamgamefile`（Steam 用它确认这是本地用户
主动发起的请求，而不是网页里的 `steam://` 链接在偷偷往库里塞游戏）。脚本做的就是：

1. 归一化路径（处理 `file://` URL）→ `readlink -f` 取绝对路径
2. 按 MIME 判断类型、检查可执行位
3. `percent-encode`（`python3 -c` 经 argv 传参；没有 python3 时用 `od` 逐字节兜底，输出逐字节一致）
4. `umask 077; : >> /tmp/addnonsteamgamefile`
5. `setsid steam "steam://addnonsteamgame/..."`（无原生 Steam 时用 `flatpak run com.valvesoftware.Steam`）

同样的做法被两个仍在维护的实现使用，可作为机制有效性的旁证：
[vicrodh/steamos-add-to-steam](https://github.com/vicrodh/steamos-add-to-steam)、
[GloriousEggroll/steam-add-nonsteam-game](https://github.com/GloriousEggroll/steam-add-nonsteam-game)。

**脚本不直接改 `shortcuts.vdf`**：那个文件由 Steam 客户端自己维护，运行中外部改动会被覆盖；
由客户端走 URL scheme 写库才是安全的。

## 2. 安装

```sh
./install.sh            # 用户级（推荐，无需 root）
./install.sh --link     # 软链到本仓库，改完即生效（开发用）
sudo ./install.sh --system   # 装到 /usr/local（多用户共用，需要 sudo）
```

用户级安装落两个文件：

```
~/.local/bin/add-to-steam
~/.local/share/kio/servicemenus/add-to-steam.desktop
```

> `kio/servicemenus` 是 Plasma 6 的服务菜单目录（本机 `kompare`/`filelight`/`kleopatra`
> 等系统包都装到 `/usr/share/kio/servicemenus/`；Dolphin 自带的 `/usr/bin/servicemenuinstaller`
> 内嵌的也是这个路径）。AUR 包用的 `kservices6/ServiceMenus` 在本机并不存在。
>
> ⚠️ **服务菜单 .desktop 必须是 755**：KIO 启动前会调用
> `KDesktopFile::isAuthorizedDesktopFile()` 做授权检查，非可信目录（`~/.local/share/kio/servicemenus`
> 就是）下的 .desktop 缺少可执行位时会被拒绝，表现是点菜单弹
> **「错误 — Dolphin：您没有此文件的执行权限。」**，脚本根本不会被启动。
> `install.sh` 已经用 `install -Dm755` 处理；如果你手工复制文件，记得 `chmod 755`。
> （系统里 `/usr/share/kio/servicemenus/` 下真正会被执行的菜单也都是 755。）

安装后**重开一个 Dolphin 窗口**（无需重启 plasma）即可看到菜单项。

## 3. 使用

### Dolphin 右键
右键 `.exe` / `.desktop` / `.AppImage` / 原生程序 / `.sh` → **添加到 Steam**。
可以多选，一次加多个。

### 命令行

```sh
add-to-steam 游戏.exe                      # 加入 Steam
add-to-steam --ui 游戏.exe                 # 出错时用 kdialog 弹窗（服务菜单用的就是这个）
add-to-steam --dry-run 游戏.exe            # 只打印将要发送的 steam:// URL，不做任何改动
add-to-steam --ui --no-notify a.exe b.exe  # 不弹成功提示
```

退出码：`0` 全部成功，`1` 有失败（文件不存在/类型不支持/没有执行位/找不到 Steam），`2` 用法错误。

**诊断日志**：每次调用都会往 `~/.cache/add-to-steam/add-to-steam.log` 追加一行，记录
时间、识别到的 MIME、路径和结果（`ADD` / `DRYRUN` / `REJECT reason=...` / `CHMOD u+x`）。
从 Dolphin 点击时看不到终端输出，出问题就看这个文件。
`ADD_TO_STEAM_LOG=/别的路径` 可改位置，`ADD_TO_STEAM_LOG=off` 关闭。

### 类型规则

| 类型 | MIME（本机实测） | 是否要求 `+x` |
|---|---|---|
| Windows 程序 | `application/vnd.microsoft.portable-executable`（`application/x-msdownload` 也接受） | 否 |
| `.desktop` | `application/x-desktop` | 否 |
| AppImage | `application/vnd.appimage` | 是 |
| 原生二进制 | `application/x-executable` | 是 |
| shell 脚本 | `text/x-shellscript` | 是 |
| 其它（如 `.txt`） | — | 直接拒绝并提示 |

> `.exe` 的 MIME 名每个发行版可能不同（上游 AUR 包只写了 `application/x-ms-dos-executable`，
> 在本机是漏的），这里的列表是按本机 `kmimetypefinder` 实测结果写的。

## 4. 本机实测结果（验收记录）

| 场景 | 结果 |
|---|---|
| **真实 Dolphin 右键点击** `/mnt/Games/Hgames/SymbiontZeroType/SymbiontZeroType.exe` → 「添加到 Steam」 | ✅ 日志 `19:08:58 INVOKE argv=--ui /mnt/…/SymbiontZeroType.exe` → `19:08:59 ADD mime=application/x-msdownload`，`shortcuts.vdf` 出现第 16 条 `SymbiontZeroType.exe` → 该绝对路径 |
| `/tmp/steam-add-test/AddToSteamTest.exe`（命令行添加，Steam 正在运行） | ✅ 1.5 秒后 `shortcuts.vdf` 出现条目：`AppName='AddToSteamTest.exe'`、`Exe='"/tmp/steam-add-test/AddToSteamTest.exe"'`、`StartDir='/tmp/steam-add-test/'` |
| `狼 狼's Game.exe`（空格 + 中文 + 单引号） | ✅ 正确写入同名字段，未被截断 |
| `Test Launcher.desktop` | ✅ Steam 解析 desktop 文件：`AppName='测试启动器'`（取 `Name=`）、`Exe='"/bin/true"'`（取 `Exec=`） |
| KIO 是否真能发现菜单（`tests/probe-servicemenu.sh`，走 Dolphin 同一条 `KFileItemActions` 代码路径） | ✅ 对 `.exe` 的第一个服务菜单就是「添加到 Steam」（共 11 项：kleopatra/kompare/konsole 等系统菜单 + 本项） |
| 纯本地冒烟测试 41 项 | ✅ 全绿 |

说明：
- Steam 会自己给 `Exe` 加一对引号（`"/path/xx.exe"`）——这是客户端行为，本机库里原有条目也是这样。
- 加 `.desktop` 的好处：Steam 用 desktop 的 `Name=` 作为显示名、`Exec=` 作为启动命令，
  所以想要好看的标题/自定义启动参数，可以做一个 `.desktop` 再右键它。
- 重复添加同路径时脚本只会在 stderr 提示「可能已有同路径条目」，**不会阻止**（与 SteamOS 行为一致）；
  重复条目请在 Steam 里手动删除。

## 5. 排错

| 现象 | 原因 / 处理 |
|---|---|
| Dolphin 里看不到「添加到 Steam」 | ① 重开 Dolphin 窗口；② `command -v add-to-steam` 是否解析到 `~/.local/bin/add-to-steam`（不在 PATH 就 `./install.sh --system`）；③ 用 `./tests/probe-servicemenu.sh <某个.exe>` 看 KIO 是否发现菜单；④ 文件类型是否在支持列表里 |
| **弹「错误 — Dolphin：您没有此文件的执行权限。」** | 服务菜单 .desktop 缺可执行位（KIO 的 `KDesktopFile::isAuthorizedDesktopFile` 授权检查）→ `chmod 755 ~/.local/share/kio/servicemenus/add-to-steam.desktop`。注意这个弹窗标题是 Dolphin 而不是 kdialog，日志里也不会有 `INVOKE`，可据此和脚本自身的报错区分 |
| 点击后弹窗「没有可执行权限（识别为 xxx）」 | 你选中的**文件**是原生二进制/脚本/AppImage 且没有执行位；弹窗里选「是」就会自动 `chmod u+x` 并继续。`.exe`/`.desktop` 不需要执行位 |
| 点击后弹窗「不支持的文件类型（识别为 xxx）」 | 该 MIME 不在列表里；把报的那行日志发出来即可加进去 |
| 点了没反应，库里也没有 | **先看 `~/.cache/add-to-steam/add-to-steam.log`**：有 `INVOKE` 说明脚本跑了（后面会跟 `REJECT reason=...`），完全没有 `INVOKE` 说明是 Dolphin/KIO 没启动脚本；再手动跑 `add-to-steam --ui <文件>`；确认 `/tmp/addnonsteamgamefile` 能写；确认 Steam 已登录（未登录时 URL 不会被处理）；`~/.local/share/Steam/logs/` 里可看客户端日志 |
| 加了但启动不了 | 条目的 `Exe` 是否指向正确路径（本机是绝对路径）；Windows 程序需要在 Steam 里设置 Proton；路径所在的挂载点是否变化 |
| `/mnt` 上的游戏失效 | 挂载点变化后绝对路径失效，需要重新添加（SteamOS 同样如此） |
| 想让菜单在没装 Steam 时消失 | `.desktop` 里的 `TryExec=steam` 已做到这一点 |

## 6. 常见疑问

**为什么不直接装 AUR 的 `steamos-add-to-steam`？**
它的 PKGBUILD 把服务菜单装到 `/usr/share/kservices6/ServiceMenus` + `/usr/share/kservices5/ServiceMenus`
（本机这两个目录都不存在，Plasma 6 读的是 `kio/servicemenus`），而且它的脚本用
`python3 -c "...\"$1\"..."` 做字符串插值，路径里带引号/`$`/反引号会出问题。本仓库的实现修正了这两点，
而且**不需要 root**。

**为什么没有启动器（Kickoff）右键？**
Plasma 5 时代 Kicker 支持从 `plasma/kickeractions` 目录加载额外动作
（[上游实现](https://invent.kde.org/plasma/plasma-workspace/-/commit/f1148d9cb4a7028a91ba67799a76efa515b78c7d)，
用 `X-KDE-OnlyForAppIds` 过滤），但本机 Plasma 6.7.5 的
`/usr/lib/qt6/qml/org/kde/plasma/private/kicker/libkickerplugin.so` 里
`plasma/kickeractions`、`X-KDE-OnlyForAppIds` 均为 0 命中，`/usr/share/plasma/kickeractions`
目录也不存在——该机制在本版本已不可用，所以没做。
替代做法：想要给某个应用加，就在 Dolphin 里右键它的 `.desktop`
（`/usr/share/applications/xxx.desktop` 或 `~/.local/share/applications/xxx.desktop`）。

**会不会哪天失效？**
`steam://addnonsteamgame` 是未公开接口，Valve 有可能改。验证方法：

```sh
add-to-steam --dry-run /路径/游戏.exe     # 看 URL 对不对
add-to-steam --ui /路径/游戏.exe          # 实际加一个，然后看 Steam 库里有没有
```

如果确认失效，回退方案是**直接写 `shortcuts.vdf`**（本机已装 `python-vdf`）：

1. 完全退出 Steam（运行中写入会被覆盖）
2. 备份 `~/.local/share/Steam/userdata/<账号id>/config/shortcuts.vdf`
3. 用 `vdf.binary_loads` 读入，往 `shortcuts` 里加一条
   `{AppName, Exe(带引号的绝对路径), StartDir(以 / 结尾), appid(唯一 int32), icon:'', LaunchOptions:'', IsHidden:0, AllowDesktopConfig:1, tags:{}}`
4. `vdf.binary_dumps` 原子写回，再启动 Steam

（当前版本不需要走这条路，仅作为接口失效时的备案。）

## 7. 目录结构与测试

```
bin/add-to-steam                            # 核心脚本（POSIX sh，755）
share/kio/servicemenus/add-to-steam.desktop # Dolphin 服务菜单（含中文菜单名）
install.sh / uninstall.sh                   # 用户级安装 / 卸载（--system 走 /usr/local）
tests/smoke.sh                              # 41 项纯本地冒烟测试（用 steam 桩，不碰真实 Steam）
tests/probe-servicemenu.cpp                 # KFileItemActions 探针源码
tests/probe-servicemenu.sh                  # 编译+运行探针，验证 KIO 能发现菜单
README.md
```

```sh
./tests/smoke.sh                          # 语法、编码一致性、类型门控、哨兵、全链路（桩）
./tests/probe-servicemenu.sh /路径/a.exe  # 用 Dolphin 同一条代码路径验证菜单可见
./uninstall.sh                            # 卸载（不会动 Steam 库里已有的条目）
```

> `tests/smoke.sh` 会把 `steam` 换成 PATH 里的桩程序，所以不会真的往库里加东西；
> 它会在 `/tmp` 建测试文件，并在结束时删掉临时目录。
