# Changelog / 更新日志

## 0.1.1

- Localize the app display name by system language
- Show `ShiGuang` on English systems and `拾光` on Simplified Chinese systems

- 根据系统语言本地化应用显示名称
- 英文系统显示 `ShiGuang`，简体中文系统显示 `拾光`

## 0.1.0

- Adjust external display hardware brightness with the keyboard brightness up and down keys
- Change brightness in 5% steps
- Show the current brightness percentage while adjusting
- Provide a macOS menu bar entry
- Support manual brightness adjustment with a slider in the menu bar panel
- Support quick quit from the menu
- Remember the last brightness value and try to restore it on the next launch
- Reset the display connection after system or display wake
- Control real hardware brightness through DDC/CI

- 支持通过键盘亮度增加/降低按键调节外接显示器硬件亮度
- 支持按 5% 步进调整亮度
- 调整亮度时自动显示当前百分比
- 提供 macOS 菜单栏入口
- 支持通过菜单栏滑块手动调节亮度
- 支持在菜单中快速退出应用
- 支持记住上次亮度，并在下次启动时尝试恢复
- 支持在系统或显示器唤醒后重置显示器连接状态
- 基于 DDC/CI 控制显示器硬件亮度
