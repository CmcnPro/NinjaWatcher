# Changelog / 更新记录

## 0.4.2 — Opt-in unit labels & official announcement / 框体标签独立开关与官方公告

- Add an independent unit-frame label switch, off by default for both new and existing saves. Toggle target, focus, and party labels immediately without changing mouseover tooltips; retain the auto/on/off mode commands.
- Replace the customer-support screenshot in both READMEs with the Chinese-server operator's official prohibition announcement. State the enforcement year as 2026 based on user confirmation; the screenshot lists only month and day.
- Describe the original distribution thread as deleted from the NGA community, without attributing the deletion or inferring the author's intentions. Upstream licensing remains unconfirmed.
- 新增目标／焦点／小队框体统计标签独立开关，新安装及已有存档升级后默认关闭；勾选或取消立即生效，不影响鼠标悬停提示，保留 auto/on/off 模式命令。
- 中英文 README 改用中国服务器运营商官方禁止公告及截图；依据用户确认注明处罚年份为 2026 年，截图本身仅列月日。
- 原始来源改为“原作者在 NGA 社区分发的帖子被删除”，不推断删帖方或作者意向；上游授权状态仍待确认。

## 0.4.1 — RollLedger rename & operator warning / 更名与运营商警告

- Use `/rledger` and `/rollledger`, not `/rl`, to avoid conflicting with the commonly used reload shortcut.
- 使用 `/rledger` 和 `/rollledger`，不注册 `/rl`，避免与常用重载快捷命令冲突。

- Add a prominent Chinese-server suspension warning in both READMEs, with the user-provided customer-support screenshot. Reports about Blizzard-operated servers are identified as user reports, not official approval.
- Rename the maintained addon from NinjaWatcher to RollLedger: folder, TOC, saved variable (`RollLedgerDB`), frame names, internal namespace, localized labels, and commands (`/rledger`, `/rollledger`). No old command alias or automatic legacy-addon loading is retained.
- Document optional manual migration from `NinjaWatcher.lua` / `NinjaWatcherDB`; keep upstream attribution and historical release notes. A rename does not guarantee protection from detection or suspension.
- 中英文 README 增加中国服务器封号风险警告及用户提供的客服邮件截图；暴雪自营服务器情况明确标注为用户反馈，不代表官方许可。
- 维护版由 NinjaWatcher 更名为 RollLedger，统一目录、TOC、存档字段（`RollLedgerDB`）、框体、内部命名空间、中英文文案及命令（`/rledger`、`/rollledger`），不保留旧命令别名，也不自动加载旧插件。
- 说明旧存档的可选手动迁移方式，保留上游来源与历史更新记录；更名不保证避免检测或封号。

## 0.4.0 — English & Simplified Chinese / 中英双语

- Add a default-on setting to show or hide only the tooltip's share-band description (e.g. Moderate share), keeping the percentage, colors, counts, and other views unchanged.
- 新增“鼠标提示中显示占比分档描述”开关，默认开启；仅控制“占比中等”等文字，百分比、颜色、计数和其他界面不变，无需重载。

- Add English and Simplified Chinese for the tooltip, settings, menus, help, alerts, sharing, and local labels.
- Follow the client language by default; unsupported languages fall back to English.
- Add `/nw language auto|zhCN|enUS` and a language button; `/reload` applies the saved account-wide choice.
- Preserve existing player data, the two-line tooltip, and chat-link destinations when changing language.
- 游戏内提示、设置、菜单、命令帮助、提醒、分享和本地标签统一接入简体中文／英文。
- 默认跟随客户端，未支持的语言回退英文。
- 新增语言命令和设置按钮，语言按账号保存，`/reload` 后统一生效。
- 切换语言不影响玩家记录，保留两行悬停提示和原有聊天链接目标。

### Compact tooltip / 精简悬停

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
