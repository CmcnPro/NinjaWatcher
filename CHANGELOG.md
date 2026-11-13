# Changelog / 更新记录

## Unreleased / 未发布

- Keep mouseover information to two lines: the statistical summary and Need / Greed / total counts.
- 鼠标提示精简为统计摘要及需求／贪婪／合计两行，不再显示进本次数、采集时间和长说明。完整记录仍可在玩家目录查看。

## 0.3.1

- Fix asynchronous tooltip updates overlapping native content.
- Use single-column rows and recalculate tooltip dimensions after updates.
- Prevent delayed scan results from changing a different player's tooltip.
- 修复扫描结果返回后提示框重叠、错位的问题。
- 改为单栏显示，更新后重新计算宽高，避免覆盖原生提示内容。
- 切换目标后，旧扫描结果不再写入新目标的提示框。

## 0.3.0 — Independent maintenance baseline / 独立维护基线

- Display Need share directly from cumulative Need and Greed counts; dungeon entries no longer exempt players from the calculation.
- Remove estimated Pass counts, accusatory labels, and kick/blacklist recommendations.
- Disable optional color bands and automatic alerts by default.
- Preserve unknown values instead of treating missing data as zero.
- Keep local records, optional frame/chat labels, manual sharing, and personal markers.
- Improve cross-realm name matching, record browsing, and snapshot freshness information.
- Migrate older saved data with a local backup; remove the inherited third-party website and pairing-code features.

- 需求占比直接按需求与贪婪累计次数计算，不再基于进本次数免责。
- 移除放弃估算、定罪式标签及踢人／拉黑建议。
- 颜色分档和自动提醒默认关闭，未知数据不再冒充0。
- 保留本地记录、可选框体／聊天标签、手动分享及个人标记。
- 改善跨服同名匹配、记录浏览和快照时效展示。
- 兼容迁移旧版数据并保留本地备份，移除原有第三方网站及配对码功能。
