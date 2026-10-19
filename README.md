# fuck-windows

> Windows 流氓软件 / 弹窗广告 一键清理工具 —— 纯 PowerShell，无依赖，可恢复注册表。

<table>
  <tr>
    <td align="center" width="50%">
      <h3><a href="https://space.bilibili.com/481791559">📺 B 站 · 关注我</a></h3>
      <sub>使用演示 · 逆向折腾 · 日常分享</sub><br>
      <a href="https://space.bilibili.com/481791559">https://space.bilibili.com/481791559</a>
    </td>
    <td align="center" width="50%">
      <a href="assets/images/vx.png"><img src="assets/images/vx.png" width="140" alt="微信二维码"></a><br>
      <sub>微信扫码添加，备注「fuck-windows」</sub>
    </td>
  </tr>
</table>

专治：开机弹窗广告、后台偷偷下载安装软件、伪装成 svchost 的守护进程、删不掉的“全家桶”、让电脑变卡的内核级自我保护驱动。

**适用系统**：Windows 10 / 11 (x64)　|　**权限**：管理员　|　**依赖**：无

## ✨ 功能特性

- **9 类持久化位置全扫描**：进程、服务、内核驱动、计划任务、启动项、启动文件夹、卸载项、安装目录、Temp 残留。
- **特征库 + 启发式双引擎**：`signatures.psd1` 社区可扩展，同时能识别伪装 svchost、AppData 中的内核驱动等典型流氓行为。
- **先停服务/驱动，再杀进程**，两轮强杀防止守护进程互相拉起。
- **可恢复**：清理前用 `reg export` 备份涉及的注册表键，自动生成 `restore.ps1`。
- **处理内核驱动锁定的文件**：自动 `takeown` / `icacls`，仍删不掉则写入 `PendingFileRenameOperations`，重启后由系统删除。
- **安全边界**：删除目录前必须同时通过特征库路径匹配、系统目录/盘符根目录、路径穿越、符号链接校验。
- **纯本地运行**：不联网、不上传扫描结果、无遥测。

## ⚠️ 免责声明

本工具会**删除文件**。清理前会自动备份注册表（可恢复自启动项、卸载信息、服务/驱动注册信息），**但被删除的文件和目录无法恢复**。

请务必：

1. 先用 `-ScanOnly` 查看扫描报告；
2. 确认列表里没有你需要的软件；
3. 重要数据提前备份，建议先在虚拟机或备用机上试跑。

特征库匹配 + 安全路径校验只能降低误删概率，不能保证 100% 无误。使用风险自负。

## 🚀 快速开始

```powershell
# GitHub
git clone https://github.com/chengpeng-cp/fuck-windows.git
# 国内网络也可以用 Gitee
git clone https://gitee.com/CP-chengpeng/fuck-windows.git

cd fuck-windows

# 1. 只扫描并输出报告，不修改系统（强烈建议第一次这样跑）
powershell -ExecutionPolicy Bypass -File .\fuck-windows.ps1 -ScanOnly

# 2. 交互式清理（会弹出 UAC 提权）
powershell -ExecutionPolicy Bypass -File .\fuck-windows.ps1

# 3. 无人值守只清理 High 项；请先检查 -ScanOnly 报告
powershell -ExecutionPolicy Bypass -File .\fuck-windows.ps1 -Auto
```

也可以直接双击 `start.bat` 运行。

> `-Auto -Aggressive` 会跳过确认并同时清理 Medium 项。Medium 包含需要用户判断的常见软件；只有核对过 `-ScanOnly` 报告后才使用。`-TameAutostart` 和 `-Harden` 是独立的可选动作。

## 🎛️ 参数

| 参数 | 说明 |
|---|---|
| `-ScanOnly` | 只扫描输出报告，不做任何系统更改；“零改动”不包括本地日志文件 |
| `-Auto` | 无人值守，默认只清理 High 项；同时使用 `-Aggressive` 时也会自动清理 Medium 项 |
| `-Aggressive` | 连 Medium 置信项（启发式命中 / 常见捆绑软件）一起清理 |
| `-TameAutostart` | 顺手禁用腾讯视频、百度网盘、夸克网盘等开机自启（仅删 Run 键，可恢复，不卸载） |
| `-Harden` | 开启 Windows Defender PUA 防护 + 后台快速扫描 |

## 🔧 工作原理

流氓软件的恶心之处在于持久化入口多、互相拉起、内核驱动自我保护。本工具按以下顺序斩草除根：

1. **扫描 9 类持久化位置**：进程、服务、内核驱动（注册表层全量枚举）、计划任务（含伪装在 `\Microsoft\` 目录下的）、自启动注册表键、启动文件夹快捷方式、卸载注册表项、安装目录及 Temp 残留。
2. **特征库 + 启发式判定**（`signatures.psd1`，社区可扩展）：
   - 内核驱动位于 `AppData` / `ProgramData` 等用户可写目录 → 高度可疑；
   - `svchost -k <组名>` 的组未在系统 Svchost 注册表注册 → svchost 伪装；
   - 进程名以 `_pop` 结尾 → 弹窗进程；
   - 卸载项装在 `AppData\Roaming` → 流氓软件典型位置。
3. **按依赖顺序清理**：先停服务/驱动，再杀进程（两轮防复活），然后依次删除计划任务 → 自启动项 → 启动快捷方式 → 卸载注册表 → 安装目录/Temp 残留。
4. **内核驱动锁定的文件**：夺取所有权后重试，仍失败则写入 `PendingFileRenameOperations`，重启时由系统强制删除。
5. **双重安全防护**：删除任何目录前，必须通过特征库路径匹配 + 黑名单校验（Windows/System32/盘符根目录）、路径穿越检查、符号链接/目录联接检查；不匹配一律跳过。
6. **备份与恢复**：清理前 `reg export` 备份涉及的注册表键（自启动、卸载信息、服务/驱动注册）到 `backup\<时间戳>\`，运行其中的 `restore.ps1` 可恢复；`-TameAutostart` 额外生成 `restore_autostart.ps1`。

> 计划任务和启动文件夹快捷方式会被直接删除，不在注册表备份范围内；被删除的程序文件需重新安装。

## 🦠 已收录的流氓软件家族

### 高置信度（默认清理）

| 家族 | 典型成员 |
|---|---|
| 鲁大师系（成都奇鲁科技） | 鲁大师、DataLock、AI智能磁盘清理、C盘瘦身、清理大师、重复文件清理、Browser Guard |
| 2345 系（上海二三四五网络科技） | 2345安全中心/主动防御、2345SafeCenter、2345王牌输入法 |
| 布丁系（北京布丁跑跑 / 四川智领时代） | 布丁桌面、布丁压缩、布丁跳跳、值购助手、智能云输入法、蒲公英wifi、柚子壁纸、麦家购物助手 |
| 鲁大师关联推广网（火绒 2025-11 点名） | TabXExplorer、小蓝鸽、大力文件粉碎、DXRepair、花瓣护眼 |
| 小鸟壁纸 | BirdWallpaper 安装目录 |
| 驱动精灵后门 | kbasesrv（卸载时投放，可云控执行任意文件） |
| 天津系（中思明达/星聚时代） | SecureBox、超级回收站、GamingHub、pctask |
| 弹窗推广 | masterwallpaper(360系壁纸)、维京传奇/霸者归来/霸者天下(传奇页游)、gamebox |

`RoguePublishers` 另收录下列主体，命中即按高置信处理：天津杏仁桉科技、天津简诚、重庆赫赫有盾、天津欣远、天津拂云科技、成都盈畅时代文化传播、上海二三四五网络科技、北京布丁跑跑科技、四川智领时代。

### 中置信度（仅 `-Aggressive` 时清理）

常见捆绑 / 推广软件：2345浏览器、2345看图王、快压、好压、360壁纸、小鸟壁纸、驱动精灵、驱动人生、WiFi万能钥匙、万能输入法、迅读PDF、小黑记事本、小鱼便签。

遇到新的流氓软件？欢迎按下面的格式提 PR 补充特征库。

> 部分家族来源：火绒安全《“捉迷藏”式收割：撕开鲁大师为首系列企业流量劫持黑幕》（2025-11）。

## 🤝 特征库贡献指南

编辑 [`signatures.psd1`](signatures.psd1)，对应字段添加正则（不区分大小写）：

| 字段 | 匹配对象 | 建议 |
|---|---|---|
| `RoguePublishers` | Uninstall 表 Publisher | 用公司名，覆盖面最大 |
| `RogueDisplayNames` | Uninstall 表 DisplayName | 建议 `^` 锚定 |
| `RogueProcesses` | 进程名 | 尽量用 `^...$` 锚定；若有意匹配前缀，需确认同系列进程名并附样本 |
| `RoguePaths` | 服务/驱动/任务/启动项的路径 | 必须带目录上下文 `\\` 开头；运行时还会校验目录或文件名边界 |
| `RogueDirectories` | 安装目录 | 用 `{Roaming}` `{Local}` `{ProgramFilesX86}` `{ProgramData}` 占位符 |
| `SuspiciousDisplayNames` | 常见捆绑软件 | 仅 `-Aggressive` 时清理 |

提 PR 时请尽量附上样本来源（截图 / 安装包名 / 进程路径），不要使用过短或过于通用的匹配词。

## ❓ 常见问题

**Q: 为什么有些文件要重启才能删掉？**<br>
流氓软件用内核驱动（.sys）锁定自身文件，运行中的驱动无法卸载。工具会把这类文件标记为重启删除，重启后系统会强制清除。

**Q: 提示需要 UAC / 闪黑窗？**<br>
工具需要管理员权限才能停服务、删驱动。右键“以管理员身份运行”，或直接双击 `start.bat`。UAC 请选择当前账户并同意，否则扫描的 `HKCU` / AppData 可能不是你本人的配置。

**Q: 误删了想要的软件怎么办？**<br>
到 `backup\<时间戳>\` 运行 `restore.ps1` 恢复注册表；软件文件需要重新安装。这也是为什么强烈建议先 `-ScanOnly`。

**Q: 支持什么系统？**<br>
Windows 10 / 11（x64），PowerShell 5.1+，无需安装任何依赖。

**Q: 会把我的扫描结果上传吗？**<br>
不会。脚本不包含任何网络请求，扫描、清理、日志全部在本机完成。

## 🔒 安全与隐私

- 全部逻辑在本地执行：不联网、不上传、无遥测。
- `logs/`、`backup/` 可能包含系统路径和已安装软件清单，已在 `.gitignore` 中忽略，不会被提交。
- `personal-docs/` 为作者私人资料目录，已加入忽略规则，不会进入公开仓库。
- 仓库内不包含密码、API Key、证书等敏感信息。
- 请只从 GitHub / Gitee 官方仓库下载，不要运行来路不明的“修改版 / 绿色版”。

## 📁 目录结构

```
fuck-windows/
├── fuck-windows.ps1     # 主入口
├── start.bat            # 双击运行
├── signatures.psd1      # 特征库（欢迎 PR）
├── lib/
│   ├── Common.psm1      # 日志/提权/备份
│   ├── Scanner.psm1     # 持久化位置扫描 + 启发式
│   ├── Terminator.psm1  # 杀进程/停服务
│   ├── Purger.psm1      # 删任务/注册表/文件/重启删除
│   └── Hardener.psm1    # Defender PUA 加固
├── tests/
│   └── Invoke-RegressionTests.ps1 # 无额外依赖的判定逻辑回归验证
├── assets/
│   └── images/vx.png    # 微信二维码
├── logs/                # 运行日志（gitignore）
├── backup/              # 清理备份（gitignore）
├── LICENSE
└── README.md
```

## 🧪 开发者回归验证

使用内置 PowerShell 跑路径安全和特征匹配回归用例，不需要安装 Pester，也不会改动系统：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-RegressionTests.ps1
```

## 📄 License

[MIT](LICENSE) © fuck-windows contributors

---

如果这个项目帮你清掉了弹窗，欢迎点个 ⭐ **Star**，也欢迎来 [B 站](https://space.bilibili.com/481791559) 三连支持一下。

<p align="center">
  <a href="https://space.bilibili.com/481791559">📺 Bilibili</a>　·　
  <a href="assets/images/vx.png">💬 微信</a>
</p>
