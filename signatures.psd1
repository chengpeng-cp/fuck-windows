# ============================================================
#  流氓软件特征库（fuck-windows signatures）
#  所有条目均为正则表达式，匹配时不区分大小写。
#  欢迎通过 PR 补充你遇到过的流氓软件家族，请注明来源。
# ============================================================
@{
    # ---- 高置信度：确认流氓（默认直接清理） ----

    # Uninstall 表 Publisher 字段匹配的发布者
    RoguePublishers = @(
        '成都奇鲁科技'      # 鲁大师全家桶
        '鲁大师'
        '天津中思明达科技'  # SecureBox / 超级回收站
        '天津星聚时代科技'  # GamingHub
    )

    # Uninstall 表 DisplayName 匹配的软件名
    RogueDisplayNames = @(
        '^鲁大师'
        '鲁大师Browser Guard'
        '^DataLock$'
        '^SecureBox$'
        '超级回收站'
        '^GamingHub$'
        'AI智能磁盘清理'
        '^C盘瘦身$'
        '^清理大师$'
        '^重复文件清理$'
        '维京传奇'
        '霸者归来'
        '霸者天下'
        '^卸载霸者'
        '^卸载维京'
        '^gamebox'
    )

    # 进程名匹配（建议 ^ $ 锚定，避免误伤，如 msedgewebview2）
    RogueProcesses = @(
        '^datalock'
        '^securebox_'
        '^filerecycle'
        '^viewedg$'
        '^adblock_master'
        '^winopt_assistant'
        '^sys_boost'
        '^EdgeWeb$'
        '^masterwallpaper$'
        '^ComputerZ'
        '^ai_smart_clean'
        '^gamebox$'
        '^GamingHub$'
    )

    # 文件路径 / 服务路径 / 任务动作 匹配
    # 必须带目录上下文（\\ 开头），防止误伤普通文件名
    RoguePaths = @(
        '\\DataLock'
        '\\SecureBox'
        '\\FileRecycle'
        '\\MicroGame\\'
        '\\pctask\\'
        '\\masterwallpaper'
        '\\AISmartClean'
        '\\Lds(CClean|CleanMaster|DuplicateFileClean|BrowserGuard)'
        '\\ludashi'
        '\\GamingHub'
        '\\gamebox'
    )

    # 已知流氓安装目录（占位符: {Roaming} {Local} {ProgramFilesX86} {ProgramData}）
    RogueDirectories = @(
        '{ProgramFilesX86}\AISmartClean'
        '{ProgramFilesX86}\LdsCClean'
        '{ProgramFilesX86}\LdsCleanMaster'
        '{ProgramFilesX86}\LdsDuplicateFileClean'
        '{ProgramFilesX86}\LdsBrowserGuard'
        '{ProgramFilesX86}\GamingHub'
        '{Roaming}\DataLock'
        '{Roaming}\DataLockCfg'
        '{Roaming}\SecureBox'
        '{Roaming}\SecureBoxCfg'
        '{Roaming}\FileRecycle'
        '{Roaming}\FileRecycleCfg'
        '{Roaming}\MicroGame'
        '{Roaming}\pctask'
        '{Roaming}\gamebox'
        '{Local}\masterwallpaper'
    )

    # Temp 目录下的残留文件夹名
    TempResiduePatterns = @(
        'Ludashi'
        'masterwallpaper'
        'TaskPopGameBox'
        'datalock'
        'securebox'
        'filerecycle'
        'gamebox'
    )

    # ---- 中置信度：常见捆绑/推广软件（仅 -Aggressive 时清理） ----
    SuspiciousDisplayNames = @(
        '^2345'
        '^快压'
        '^好压'
        '^360壁纸'
        '^小鸟壁纸'
        '^驱动精灵'
        '^驱动人生'
        '^WiFi万能钥匙'
        '^万能输入法'
    )

    # ---- 可选：-TameAutostart 时禁用自启的正常软件（仅删 Run 键，可恢复，不卸载） ----
    UserAutostartPatterns = @(
        'QQLive\.exe'
        'SodaMusicLauncher'
        'YunDetectService'
        'BaiduYunDetect'
        'QuarkCloudDrive\.exe'
        'QuarkUpdater'
        'fdm\.exe'
        'douyin'
    )
}
