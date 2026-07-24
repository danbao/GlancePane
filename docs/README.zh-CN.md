# GlancePane 中文快速开始

GlancePane 是一个运行在 macOS 副屏上的原生状态面板，适合 `1280×720` 便携屏。它提供翻页时钟、系统状态、性能趋势、Codex 用量、股票和天气页面。

## 安装

1. 从 [GitHub Releases](https://github.com/danbao/GlancePane/releases/latest) 下载 `GlancePane-arm64.dmg`。
2. 打开 DMG，把 `GlancePane.app` 拖入 Applications。
3. 首次启动时按住 Control 点击 App，选择“打开”，再确认一次。

当前免费版本使用 ad-hoc 签名，没有 Apple 公证。如果系统仍拦截，请到“系统设置 > 隐私与安全性”允许 GlancePane。

只支持 Apple Silicon 和 macOS 14 及以上版本。安装后不需要 Xcode、Homebrew 或源码仓库。

## 三步配置

1. 点击菜单栏中的 GlancePane 图标，打开 **Settings…**。
2. 在 **Display & Behavior** 中保留 **Automatic**，程序会优先选择第一块非主屏；也可以指定某块显示器。
3. 在 **Dashboard** 中启用、隐藏或排序页面，并设置自动轮播间隔。

副屏上左键切上一页，右键切下一页，也可以横向拖拽。该功能可在设置中关闭。

## 页面

- **Clock**：Oswald 字体的极简翻页时钟。
- **System**：内存、温度、电源、网络、磁盘和健康状态。
- **Performance**：CPU 趋势、P/E 核、GPU 和高占用进程。
- **Agents**：Codex context、token 使用和额度；默认隐藏项目名。
- **Market**：Yahoo Finance 股票行情，失败时使用本地缓存。
- **Weather**：QWeather 当前天气、小时预报和分钟级降雨。

## 数据与隐私

- 配置目录为 `~/.glancepane/`，目录权限为 `0700`。
- 配置、缓存、备份和导出的配置文件权限为 `0600`。
- 不缓存 Codex prompt、response、账号邮箱和完整项目路径。
- QWeather JWT 在本机生成，只保存在内存中。
- Weather 页面隐藏后暂停刷新，减少 API 调用。

旧 GlanceDeck 用户请先关闭旧版的 Launch at Login 并退出旧程序。GlancePane 首次启动时会迁移 `~/.glancedeck/` 中支持的配置、缓存和默认 QWeather 私钥。

## 配置天气

天气默认未配置。先在 QWeather 创建 Ed25519 JWT 凭证，然后执行：

```bash
mkdir -p "$HOME/.glancepane/qweather"
chmod 700 "$HOME/.glancepane" "$HOME/.glancepane/qweather"

openssl genpkey -algorithm ED25519 \
  -out "$HOME/.glancepane/qweather/ed25519-private.pem"

openssl pkey -pubout \
  -in "$HOME/.glancepane/qweather/ed25519-private.pem" \
  -out "$HOME/.glancepane/qweather/ed25519-public.pem"

chmod 600 "$HOME/.glancepane/qweather/ed25519-private.pem"
```

把公钥上传到 QWeather，再在 Settings 中填写 API Host、Credential ID、Project ID、私钥路径和天气位置。

## 本地开发

```bash
sh scripts/test.sh
sh scripts/build.sh
sh scripts/package-dmg.sh
```

返回[英文 README](../README.md)。
