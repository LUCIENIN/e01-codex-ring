# E01 Codex Ring

一个面向 macOS 的实验性 Swift 项目：读取本机 Codex 与 Kimi Code 额度，生成圆形仪表盘，并通过 BLE 把自定义内容写入 E01/ZRun 圆形电子胸牌。

> 当前结论：预览、BLE 扫描、绑定、设备信息解析、RCSP 媒体传输和自定义画面显示曾在一台 368×368 E01 上完成实机验证。当前 `display` 把静态仪表盘编码为 368×368 JPEG；程序只有在设备明确结束传输后才输出 `display_transfer_complete`，但仍需肉眼确认圆屏确实切换。持续同步已经加入后台启动、短超时重试、旧连接恢复和状态落盘，每个固件仍需做一次断电重连验收。仓库暂不刷写固件。

![Status](https://img.shields.io/badge/status-hardware--investigation-orange)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0%2B-F05138)
![License](https://img.shields.io/badge/license-MIT-green)

## 已验证的部分

- 只读取近期 Codex JSONL 中的 `token_count.rate_limits`，忽略提示词、消息、账号标识和 Cookie。
- 从 Kimi Code 官方 `https://api.kimi.com/coding/v1/usages` 只读获取每周额度和 5 小时滚动额度；API Key 只在内存中的请求头使用，不写入图片、日志、缓存或仓库。
- 生成 64–2048 像素的圆形 PNG；默认 320×320，设备路径使用 368×368。
- 只读扫描 E01 的 `FD00` 数据服务。
- 在 `FD01/FD02/FD03` 白名单内执行绑定，并校验 `0x61` 响应。
- 解析屏幕尺寸、存储容量、协议版本、固件版本、平台和型号字段。
- 实现普通数据帧、视频表盘 `C0/C1/C2/C3/C5`、RCSP 帧和大文件传输的解析/编码测试。
- 在一台自有 E01 上通过 RCSP 完成媒体传输，并由用户肉眼确认过自定义画面显示；当前静态 JPEG 路径仍以每次实屏回读为最终验收。
- 后台连接卡住时会在 15 秒结束本轮；前两次保留已知设备，连续三次失败后自动切换为重新扫描。

## 验证边界

- 实机结论只覆盖当前这一台 E01 及其已观察到的协议组合，不代表所有同外壳设备兼容。
- 普通数据服务的 `C0` 表盘更新在该固件上会在请求媒体分片前被拒绝，因此 `display` 使用已经实机成功的 RCSP 文件传输路径。
- 没有取得与该设备精确版本匹配、可回滚的官方固件，所以没有执行 OTA。
- 其他 E01 固件和相似外壳设备的兼容性未知。

## 快速开始

要求：macOS 14+、Swift 6+。`display` 还需要 Homebrew 路径下的 FFmpeg：`/opt/homebrew/bin/ffmpeg`。

```bash
git clone https://github.com/LUCIENIN/e01-codex-ring.git
cd e01-codex-ring
swift test

# 只生成预览，不连接设备
swift run codex-ring preview \
  --sessions "$HOME/.codex/sessions" \
  --output .runtime/codex-ring-preview.png
open .runtime/codex-ring-preview.png

# 只扫描，不连接、不写入
swift run codex-ring scan --timeout 10

# 执行普通数据服务绑定
swift run codex-ring bind --timeout 20

# 写屏；失败会以非零状态退出
swift run codex-ring display --timeout 30

# 持续同步；至少每 30 秒检查一次，只在剩余百分比变化后写屏
swift run codex-ring display-watch --interval 30 --timeout 30
```

`display_transfer_complete` 只有在设备明确返回成功结果后才会输出。看到扫描或绑定成功，不代表屏幕内容已经更新。

`display-watch` 在正常空闲时按不短于 30 秒的周期读取 Codex，并向 Kimi Code 官方接口请求最新额度；BLE 重试不会把 Kimi 请求加速到 30 秒以内。Kimi 返回 `remaining` 时程序优先按 `remaining / limit` 计算百分比，只有缺少 `remaining` 时才使用 `used` 推算，避免因 5 小时窗口不含 `used` 而回退到旧缓存。只有设备写入成功后，它才把三项百分比的组合签名、时间和设备中的活动文件名保存到 `~/.codex/e01-display-sync-state.json`；任一百分比变化都会触发下一次写屏。Kimi 最近一次成功结果会脱敏缓存到 `~/.codex/e01-kimi-usage-cache.json`，临时断网或服务重启时可以继续显示旧值，超过 10 分钟会标为 `STALE DATA`。扫描或传输失败会按 5、15、30、60 秒的上限退避重试；长时间不变时每 5 分钟重新确认一次，避免设备重启后保留旧画面。E01 必须开机并处于 Mac 可连接的 BLE 状态，手机端 ZRun 占用连接时无法刷新。

## 新徽章首次同步

新用户需要一台 macOS 14+ 的 Mac、Swift 6+、Homebrew 版 FFmpeg，以及已经产生本地额度记录的 Codex Desktop/CLI。Kimi 显示是可选的：安装 Kimi Code CLI 并执行一次 `kimi login` 后，程序会读取 `~/.kimi-code/config.toml` 中的 Kimi 类型凭据，但只允许把它发送给官方 `api.kimi.com/coding/v1` 地址。没有登录 Kimi 时，Codex 同步仍可独立工作。

```bash
brew install ffmpeg
git clone https://github.com/LUCIENIN/e01-codex-ring.git
cd e01-codex-ring

# 可选：需要显示 Kimi 时，先安装 Kimi Code CLI，再登录一次
kimi login

chmod +x scripts/install-display-watch.zsh
./scripts/install-display-watch.zsh
```

安装完成后按这个顺序操作：

1. 关闭手机蓝牙，避免 ZRun 或手机系统先占用徽章连接。
2. 给 E01 断电再上电一次，让 Mac 捕获它的短时 BLE 广播。
3. 等待 `display_sync_complete`；只有这条日志和屏幕肉眼变化同时出现，才算同步成功。
4. 查看日志：`tail -f ~/.local/state/e01-codex-ring/display-watch.error.log ~/.local/state/e01-codex-ring/display-watch.log`。

首次完成 GATT 服务发现后，程序会在 `~/.codex/e01-known-device-id` 保存本机 CoreBluetooth UUID。此后 Mac 登录、后台服务重启或徽章再次广播时都会自动尝试连接，不需要重复运行安装命令。连续三次短连接失败后，程序会暂时放弃旧 UUID 并自动扫描；更换另一块徽章时执行 `./scripts/install-display-watch.zsh --reset-device`，旧 UUID 会先备份，再重新扫描新设备。

这不是 HDMI 或 USB 外接屏。当前静态显示链路是“Codex/Kimi 额度 → 368×368 图片 → JPEG → BLE/RCSP 推送”，因此更新粒度是下一次 30 秒检查发现百分比变化后的同步，不是秒级推送，也不是逐帧镜像。当前只在一台 368×368 E01 上验证过协议和实际显示；自动重连仍需按设备固件逐台做一次断电验收。设备完全不广播时，任何 Mac 程序都无法主动连接，此时只需让徽章重新开机，不需要重装或重新执行同步命令。

## 写入自己的程序/内容

这个胸牌不是 HDMI 显示器，不能直接把 macOS 窗口投进去。可行模型是：

`数据源 → 368×368 渲染 → 设备接受的媒体封装 → BLE 绑定/认证 → 分片传输 → 设备确认 → 肉眼回读`

如果你要显示天气、订单数、服务器状态或自己的 API，只需替换数据读取器和 `RingCardRenderer` 的展示内容；BLE 层保持不变。完整入口见 [写入自己的内容](docs/BUILD-YOUR-OWN.md)，协议边界见 [协议观察](docs/PROTOCOL.md)。

## 项目状态

路线图、验收门和已知阻塞见 [PROJECT.md](PROJECT.md)。公开 Issue 只记录脱敏后的协议与复现信息，不记录真实 MAC、二维码绑定 URL、Codex 会话或固件文件。

## 安全与版权

- 只在你拥有或得到明确授权的设备上测试。
- 仓库不包含 ZRun APK、反编译源码或 E01 固件。
- `jl_auth_2.0.0.js` 来自 Jieli-Tech 的 Apache-2.0 项目；详情见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
- 主项目以 MIT 许可证发布；第三方文件继续遵循其原许可证。

## 参考来源

- [Jieli-Tech/WeChat-Mini-Program-OTA](https://github.com/Jieli-Tech/WeChat-Mini-Program-OTA)（RCSP 认证资源和公开 SDK 语义）
- [jumpingmushroom/e87_badge](https://github.com/jumpingmushroom/e87_badge)（ZRun 圆形 E-Badge 的 JPEG/AVI 上传实现与协议记录）
- [Kimi Code Membership](https://www.kimi.com/code/docs/en/kimi-code/membership.html)（共享周额度与 5 小时滚动额度说明）
- [MoonshotAI/kimi-code managed usage](https://github.com/MoonshotAI/kimi-code/blob/fa9865f2ee653133295992489554bb2db05a9db5/packages/oauth/src/managed-usage.ts)（官方额度接口、响应字段和超时行为）
- 本仓库的 E01 普通数据/表盘协议代码来自对自有设备和自有 App 流量的 clean-room 观察；未复制厂商 App 源码。

## 参与贡献

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。最有价值的贡献不是“我这里也不行”，而是脱敏后的固件身份、完整阶段、返回命令与 reason code。
