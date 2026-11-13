local ADDON, NW = ...
NW.strings = {
    CHAT_PREFIX="|cff66ccffNinjaWatcher|r",
    TOOLTIP_LABEL="掷骰统计参考", TOOLTIP_PENDING="扫描中…", TOOLTIP_UNKNOWN="数据不可读",
    TOOLTIP_STATUS_FAR="距离太远", TOOLTIP_STATUS_BUSY="接口忙碌", TOOLTIP_STATUS_COMBAT="战斗中",
    TOOLTIP_STATUS_NOAPI="客户端不支持成就对比", TOOLTIP_STATUS_TIMEOUT="扫描超时",
    TOOLTIP_STATUS_NODATA="没有可读的需求/贪婪统计", TOOLTIP_STATUS_RETRY="再次悬停可重试",
    EMPTY_ROLLS="无已记录掷骰", SMALL_SAMPLE="累计计数较少", VALUE_UNKNOWN="未知",
    SHARE_RATE="需求占比 %.1f%%",
    COUNTS_DETAIL="需求 %s / 贪婪 %s / 合计 %s\n地下城进入次数 %s（独立辅助信息）",
    BAND_DARKGREEN="占比较低", BAND_GREEN="占比中等", BAND_YELLOW="占比较高", BAND_RED="占比很高",
    BAND_GRAY="无占比", BAND_UNKNOWN="未知",
    FIELD_NEED="需求次数", FIELD_GREED="贪婪次数", FIELD_ENTRIES="进本次数", FIELD_ROLLS="合计掷骰",
    STATUS_READABLE="可读", STATUS_UNREPORTED="未报告", STATUS_UNKNOWN="未知", STATUS_RESTRICTED="受限",
    STATUS_FORMAT="格式不明确", STATUS_SKIPPED="客户端标记隐藏", STATUS_API="接口不可用", STATUS_ERROR="接口报错",
    DATA_RECENT="近期快照", DATA_STALE="过期/不可用快照", DATA_STALE_SHORT="旧/未知",
    DATA_COLLECTED="采集于 %s", DATA_LAST_FAILED="最近尝试失败：%s",
    SCAN_NODATA="统计不完整", SCAN_TIMEOUT="超时", SCAN_COMBAT="战斗限制", SCAN_BUSY="接口忙碌",
    SCAN_CANCELLED="已取消", SCAN_FAR="距离过远", SCAN_NOAPI="接口不可用", SCAN_UNKNOWN="未知原因",
    RATE_HINT="需求占比=N/(N+G)，不包含放弃次数；累计统计不能认定恶意需求。",
    PERSONAL_NOTE_WARNING="★个人标记仅记录你的备注，不是举报、事实认定或自动评级依据。",
    ALERT_LOCAL="统计提醒：「%s」需求占比 %.1f%%（需求%d / 贪婪%d），不代表恶意需求。",
    SETTINGS_SCAN_NONE="当前没有可扫描的小队成员。", SETTINGS_SCAN_STARTED="已请求扫描 %d 名小队成员。",
    CHAT_NO_SETTINGS="客户端没有可用的 Settings 插件面板。",
    CHAT_RULE_BAD="界值无效（%s）：需要 0<a<b<c<100 的三个整数。",
    CHAT_RULE_SET="占比分档界值：%d%% / %d%% / %d%%（人为展示线，非风险概率）。",
    SHARE_TARGET_SELF="本地聊天框", SHARE_TARGET_EDIT="聊天输入框", SHARE_TARGET_SAY="说",
    SHARE_TARGET_PARTY="小队", SHARE_TARGET_RAID="团队", SHARE_TARGET_GUILD="公会", SHARE_TARGET_WHISPER="密语",
    SHARE_TARGET_SET="手动分享目标：%s", SHARE_CONFIRM="将发到%s，30秒内再次执行同一操作确认。",
    SHARE_NO_DATA="没有本地记录，已尝试请求扫描；请稍后再分享。", SHARE_BAD_DATA="无法在聊天长度限制内生成统计信息。",
    SHARE_NO_WHISPER="请指定密语收件人，例如 /nw share whisper 玩家名。",
    SHARE_COOLDOWN="同一玩家和频道的分享间隔至少5秒。", SHARE_SENT="已发送到%s。",
    SHARE_NOT_IN_PARTY="当前不在小队。", SHARE_NOT_IN_RAID="当前不在团队。",
    BROADCAST_TITLE="NinjaWatcher 统计分享", BROADCAST_HINT="小队/团队按钮会立即公开发送中性统计；悬停可预览。",
    BROADCAST_PREVIEW="将发送：%s", BROADCAST_NO_ROW="尚无本地快照，请先悬停或扫描。",
    BROADCAST_EMPTY="当前没有可显示的玩家。", BROADCAST_STATUS="%s · 本地记录 %d 人",
    BROADCAST_STATE_RAID="团队中", BROADCAST_STATE_PARTY="小队中", BROADCAST_STATE_SOLO="未组队",
    BROADCAST_PARTY_BTN="小队", BROADCAST_RAID_BTN="团队", BROADCAST_CLOSE="关闭",
    BROADCAST_ICON_MODE="图标：%s", BROADCAST_ICON_MINIMAP="小地图", BROADCAST_ICON_FLOAT="悬浮", BROADCAST_ICON_HIDE="隐藏",
    BROADCAST_ICON_SET="快捷图标：%s", BROADCAST_ICON_TIP="左键：统计分享面板；拖动：移动；右键：悬浮模式",
    BROADCAST_TAG_MOUSE="悬停", BROADCAST_TAG_TARGET="目标", BROADCAST_TAG_RAID="团员",
    BROADCAST_TAG_PARTY="队友", BROADCAST_TAG_SELF="自己",
    BADGE_MODE_AUTO="自动（副本/野外开，休息区关）", BADGE_MODE_ON="总是显示", BADGE_MODE_OFF="关闭",
    BADGE_BAD="标签模式：auto/on/off 或 自动/开/关。", BADGE_SET="框体标签：%s", BADGE_NO_ROW="未记录",
    TAG_MODE_WHISPER="仅私聊", TAG_MODE_ALL="全部频道", TAG_MODE_OFF="关闭",
    TAG_BAD="聊天标签模式：off/whisper/all 或 关/私聊/全部。", TAG_SET="聊天标签：%s",
    TAG_UNKNOWN="(未记录)", TAG_GRAY="(无可用占比)", TAG_RATE="(%d%%)",
}
function NW.L(key, ...)
    local text=NW.strings[key] or key
    if select("#",...)>0 then
        local ok,out=pcall(string.format,text,...)
        if ok then return out end
    end
    return text
end
