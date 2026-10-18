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
        # ---- 火绒《撕开鲁大师为首系列企业流量劫持黑幕》点名关联企业（2025-11）----
        '天津杏仁桉科技'        # 推广结算网络 apkevery.com（与鲁大师同源）
        '天津简诚'              # 小蓝鸽 / 大力文件粉碎
        '重庆赫赫有盾'          # DXRepair
        '天津欣远'              # 花瓣护眼
        '天津拂云科技'          # 关联企业
        '成都盈畅时代文化传播'  # 小鸟壁纸
        # ---- 其他常见流氓家族 ----
        '上海二三四五网络科技'  # 2345 全家桶
        '北京布丁跑跑科技'      # 布丁系（布丁桌面 / 布丁压缩 / 麦家购物助手等）
        '四川智领时代'          # 布丁系 / 值购助手
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
        # ---- 2345 静默安装组件（无卸载入口 / 带内核驱动防删，默认清理）----
        '^2345安全中心'
        '^2345安全卫士'
        '^2345王牌输入法'
        # ---- 布丁系全家（删了会复活，成套静默安装）----
        '^布丁桌面$'
        '^布丁压缩$'
        '^布丁跳跳$'
        '^值购助手$'
        '^智能云输入法$'
        '^蒲公英'
        '^柚子壁纸$'
        '^麦家购物助手$'
        # ---- 火绒点名推广产品 ----
        '^TabXExplorer$'
        '^小蓝鸽'
        '^大力文件粉碎'
        '^DXRepair$'
        '^花瓣护眼$'
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
        # ---- 2345 安全中心 / 主动防御（静默安装）----
        '^2345SafeCenter'
        '^2345MiniPage'
        '^2345ssp'
        '^2345Base'
        # ---- 驱动精灵卸载时投放的后门（火绒实锤，可云控执行任意文件）----
        '^kbasesrv'
        # ---- 布丁系 ----
        '^pdzip'
        '^SCMenu'
        '^worthyshop'
        '^dandelionwifi'
        '^pgywifi'
        '^yzwallpaper'
        '^barleyshop'
        # ---- 小鸟壁纸 / 火绒点名产品 ----
        '^BirdWallpaper'
        '^360wallpaper_bird'
        '^TabXExplorer'
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
        # ---- 2345 全家桶 ----
        '\\2345Soft\\'
        '\\2345safe\\'
        '\\2345Base'
        # ---- 驱动精灵后门 ----
        '\\kbasesrv'
        # ---- 布丁系 ----
        '\\PuddingDesktop'
        '\\pdzip'
        '\\SCMenu'
        '\\worthyshop'
        '\\yzwallpaper'
        '\\dandelionwifi'
        # ---- 小鸟壁纸 / 火绒点名产品 ----
        '\\BirdWallpaper'
        '\\TabXExplorer'
        '\\XunDuPdf'      # 迅读PDF大师（目录名待核实）
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
        # ---- 2345 全家桶 ----
        '{ProgramFilesX86}\2345Soft\2345Explorer'
        '{ProgramFilesX86}\2345safe'
        # ---- 布丁系（目录名部分待核实）----
        '{ProgramFilesX86}\PuddingDesktop'
        '{Roaming}\pdzip'
        '{Roaming}\SCMenu'
        '{Roaming}\worthyshop'
        '{Roaming}\yzwallpaper'
        '{Roaming}\dandelionwifi'
        # ---- 小鸟壁纸 ----
        '{ProgramFilesX86}\BirdWallpaper'
        '{Roaming}\BirdWallpaper'
        '{Local}\BirdWallpaper'
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
        '2345SafeCenter'
        'PuddingDesktop'
        'pdzip'
        'SCMenu'
        'worthyshop'
        'yzwallpaper'
        'dandelionwifi'
        'BirdWallpaper'
        'XunDuPdf'
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
        # 功能性软件但带推广/劫持行为，交用户判断（仅 -Aggressive 清理）
        '^迅读PDF'
        '^小黑记事本$'
        '^小鱼便签$'
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
