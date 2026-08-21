# fuck-windows

> Windows 流氓软件 / 弹窗广告 一键清理工具 —— 纯 PowerShell，无依赖，可恢复。

专治：开机弹窗广告、后台偷偷下载安装软件、伪装成 svchost 的守护进程、删不掉的"全家桶"、让电脑变卡的内核级自我保护驱动。

## ⚠️ 免责声明

本工具会删除软件。虽然清理前会备份注册表（可恢复自启动项和卸载信息），**但被删除的文件无法恢复**。请先用 `-ScanOnly` 查看报告，确认列表中没有你需要的软件后再执行清理。特征库匹配 + 安全路径校验双重保护，但使用风险自负。

## 快速开始

```powershell
git clone https://github.com/<你的用户名>/fuck-windows.git
cd fuck-windows

# 1. 先看报告，不做任何更改（强烈建议第一次这样跑）
powershell -ExecutionPolicy Bypass -File .\fuck-windows.ps1 -ScanOnly

# 2. 交互式清理（弹出 UAC 后按提示确认）
powershell -ExecutionPolicy Bypass -File .\fuck-windows.ps1

# 3. 一条龙：全自动 + 连可疑项一起清 + 禁国产软件自启 + 开启防护
powershell -ExecutionPolicy Bypass -File .\fuck-windows.ps1 -Auto -Aggressive -TameAutostart -Harden
```

双击 `start.bat` 也可运行。

## 参数

| 参数 | 说明 |
|---|---|
| `-ScanOnly` | 只扫描输出报告，零改动 |
| `-Auto` | 无人值守，跳过确认（仍只清理 High 置信项） |
| `-Aggressive` | 连 Medium 置信项（启发式命中）一起清理 |
| `-TameAutostart` | 顺手禁用腾讯视频/百度网盘/夸克网盘等开机自启（仅删 Run 键，可恢复，不卸载） |
| `-Harden` | 开启 Windows Defender PUA 防护 + 后台快速扫描 |

## 工作原理

流氓软件的恶心之处在于持久化入口多、互相拉起、内核驱动自我保护。本工具按以下顺序斩草除根：

1. **扫描 8 类持久化位置**：进程、服务、内核驱动（注册表层全量枚举）、计划任务（含伪装在 `\Microsoft\` 目录下的）、自启动注册表键、启动文件夹快捷方式、卸载注册表项、安装目录及 Temp 残留
2. **特征库匹配**（`signatures.psd1`，社区可扩展）+ **启发式检测**：
   - 内核驱动位于 `AppData`/`ProgramData` 等用户可写目录 → 必是流氓
   - `svchost -k <组名>` 的组未在系统 Svchost 注册表注册 → svchost 伪装
   - 进程名以 `_pop` 结尾 → 弹窗进程
   - 卸载项装在 `AppData\Roaming` → 流氓软件典型位置
3. **先停服务/驱动，再杀进程**（两轮防复活），然后依次删计划任务 → 自启动项 → 注册表 → 安装目录
4. **内核驱动锁定的文件**：夺取所有权重试，仍失败则写入 `PendingFileRenameOperations`，重启时由系统强制删除
5. **双重安全防护**：删除任何目录前必须通过特征库路径匹配 + 黑名单（Windows/盘符根目录）校验，不匹配一律跳过
6. **备份与恢复**：清理前 `reg export` 所有涉及的注册表键到 `backup\<时间戳>\`，运行其中的 `restore.ps1` 可恢复；`-TameAutostart` 额外生成 `restore_autostart.ps1`

## 已收录的流氓软件家族

| 家族 | 典型成员 |
|---|---|
| 鲁大师系（成都奇鲁科技） | 鲁大师、DataLock、AI智能磁盘清理、C盘瘦身、清理大师、重复文件清理、Browser Guard |
| 天津系（中思明达/星聚时代） | SecureBox、超级回收站、GamingHub |
| 弹窗推广 | masterwallpaper(360系壁纸)、维京传奇/霸者归来/霸者天下(传奇页游)、gamebox |

遇到新的流氓软件？欢迎按下面的格式提 PR 补充特征库。

## 特征库贡献指南

编辑 [`signatures.psd1`](signatures.psd1)，对应字段添加正则（不区分大小写）：

| 字段 | 匹配对象 | 建议 |
|---|---|---|
| `RoguePublishers` | Uninstall 表 Publisher | 用公司名，杀伤面最大 |
| `RogueDisplayNames` | Uninstall 表 DisplayName | 建议 `^` 锚定 |
| `RogueProcesses` | 进程名 | 必须 `^...$` 锚定（防止误伤 msedgewebview2 之类） |
| `RoguePaths` | 服务/驱动/任务/启动项的路径 | 必须带目录上下文 `\\` 开头 |
| `RogueDirectories` | 安装目录 | 用 `{Roaming}` `{Local}` `{ProgramFilesX86}` `{ProgramData}` 占位符 |
| `SuspiciousDisplayNames` | 常见捆绑软件 | 仅 `-Aggressive` 时清理 |

## 常见问题

**Q: 为什么有些文件要重启才能删掉？**
流氓软件用内核驱动（.sys）锁定自身文件，运行中的驱动无法卸载。工具已把这类文件标记为重启删除，重启后系统会强制清除，之后它们彻底消失。

**Q: 提示需要 UAC / 闪黑窗？**
工具需要管理员权限才能停服务、删驱动。右键"以管理员身份运行"，或直接用 `start.bat`。

**Q: 误删了想要的软件怎么办？**
到 `backup\<时间戳>\` 运行 `restore.ps1` 恢复注册表；软件文件需重装（这也是为什么建议先 `-ScanOnly`）。

**Q: 支持什么系统？**
Windows 10 / 11（x64），PowerShell 5.1+，无需安装任何依赖。

## 目录结构

```
fuck-windows/
├── fuck-windows.ps1    # 主入口
├── start.bat           # 双击运行
├── signatures.psd1     # 特征库（欢迎 PR）
├── lib/
│   ├── Common.psm1     # 日志/提权/备份
│   ├── Scanner.psm1    # 8 类持久化位置扫描 + 启发式
│   ├── Terminator.psm1 # 杀进程/停服务
│   ├── Purger.psm1     # 删任务/注册表/文件/重启删除
│   └── Hardener.psm1   # Defender PUA 加固
├── logs/               # 运行日志（gitignore）
└── backup/             # 清理备份（gitignore）
```

## License

[MIT](LICENSE)
