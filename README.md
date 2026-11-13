# NinjaWatcher

**English** | [简体中文](README.zh-CN.md)

A World of Warcraft addon that displays cumulative Need/Greed roll statistics, with local player records, optional party alerts, and manual sharing.

> **Currently Chinese-only.** The addon’s interface and in-game messages are available in **Simplified Chinese only**. An **English version is under development**, with more languages planned. This English README does not mean an English in-game version is available yet.

> **Statistics provide context—not proof of loot abuse.** A high Need share does not establish malicious behavior, and a low share does not establish fair play.

## Features

- **Compact mouseover tooltip:** See a player’s Need share and cumulative Need / Greed / total counts in two lines.
- **Local player records:** Browse previously scanned players, sort by last scan or Need share, and view collection times and scan status.
- **Optional unit-frame labels:** Display locally recorded statistics beside target, focus, and party frames.
- **Optional chat-name labels:** Recognize previously recorded players without changing the original clickable player link.
- **Manual sharing:** Print statistics locally, prepare text in the chat input, or explicitly share them with a party, raid, guild, or whisper recipient.
- **Optional numerical alerts:** Enable local or party alerts if desired. Automatic alerts are off by default.
- **Personal markers:** Keep local reference marks without changing a player’s statistics or reporting anyone to an external service.

## Compatibility

Designed for **WoW Forever 1.60.1 / Interface `16001` / game type `camelot`**.

Support for other Retail or Classic clients is not currently guaranteed. The in-game interface and messages are Chinese-only while English localization is in development.

## Installation

1. Download the repository as a ZIP and extract it.
2. Copy **only the `NinjaWatcher` folder** into your client’s `Interface/AddOns/` directory:

   ```text
   Interface/
   └── AddOns/
       └── NinjaWatcher/
           ├── NinjaWatcher.toc
           ├── Core.lua
           └── ...
   ```

   Do not install the entire extracted repository as the addon folder.
3. Remove or move aside other copies of NinjaWatcher to avoid conflicts.
4. Restart the game and enable NinjaWatcher in the addon list.
5. Type `/nw` to open the player catalog and settings.

**Upgrading?** Exit the game and back up your existing `NinjaWatcher.lua` SavedVariables file and its `.bak` under `WTF` before replacing the addon. Existing records are migrated automatically; do not delete them unless you want to reset your data.

## Using the addon

Hover over a player to request their statistics. The tooltip shows only the summary and roll counts. The current Chinese display looks like this:

```text
掷骰统计参考：需求占比 15.6%
需求 26 / 贪婪 141 / 合计 167
```

The first line is the **Need share**. The second lists **Need / Greed / total** counts. More details, including collection time, dungeon entries, and scan failures, are available in the `/nw` player catalog.

You can also scan your current party with `/nw scan`, or inspect your own statistics with `/nw status`. Scans depend on the client’s public-statistics API and can be unavailable because of distance, combat restrictions, or hidden data.

### Sharing

Sharing defaults to **local output**, visible only to you. Use `/nw share party` to explicitly send statistics to your party, or open the quick-button panel with `/nw broadcast`.

Shift-clicking a catalog row uses your selected sharing destination. Sending through a saved public destination requires confirmation; explicitly labeled Party/Raid buttons send immediately. Shared messages include a neutral caveat and snapshot freshness information.

### Defaults

- Numerical tooltip display: **on**.
- Optional color bands: **off**.
- Automatic local and public party alerts: **off**.
- Chat-name labels: **off**.
- Unit-frame labels: automatic mode, normally shown in instances and outdoors and hidden in resting areas.

## Commands

Command keywords work as shown below; their in-game output is currently in Chinese.

| Command | Purpose |
| --- | --- |
| `/nw` | Open records and settings |
| `/nw scan` | Scan the current party |
| `/nw status` | Show your own statistics |
| `/nw share` | Share the hovered or targeted player’s statistics locally by default |
| `/nw share party` | Send statistics to the party |
| `/nw share whisper Player-Realm` | Share by whisper |
| `/nw target self` | Set the default sharing destination: `self`, `edit`, `say`, `party`, `raid`, `guild`, or `whisper` |
| `/nw broadcast` | Open the statistics-sharing panel |
| `/nw icon minimap` / `float` / `hide` | Choose the quick-button mode |
| `/nw badge auto` / `on` / `off` | Choose unit-frame label mode |
| `/nw tag off` / `whisper` / `all` | Choose chat-name label mode |
| `/nw bands on` / `/nw bands off` | Enable / disable optional share colors |
| `/nw tier 15 35 55` | Customize descriptive percentage boundaries |
| `/nw rule` / `/nw rule reset` | Show / reset the boundaries |
| `/nw clear` | Show the confirmation command for deleting local records |

## Understanding the statistics

NinjaWatcher reads cumulative **Need** and **Greed** counters exposed by the client:

```text
Total recorded rolls = Need + Greed
Need share = Need / (Need + Greed)
```

- Missing or unreadable values are not treated as zero.
- No recorded rolls means there is no percentage to calculate—not a 0% Need share.
- Small recorded counts remain visible with a small-count note.
- Dungeon-entry counts are optional context. They never reduce or exempt a player’s Need share.
- Optional percentage colors describe numerical ranges, not a validated risk score.
- The addon does not estimate Pass counts or determine whether a particular Need roll was justified.

These lifetime counters do not reveal which items were rolled on, whether an item was an upgrade, or what loot rules the group agreed to. They should not be used as a verdict about another player.

Old records can be browsed and shared, but may be out of date. The player catalog shows collection times and failed attempts; the compact mouseover tooltip intentionally omits these details.

## Privacy and saved data

Records and settings are stored **locally and account-wide** in `NinjaWatcherDB`.

- No automatic website uploads or shared blacklist synchronization.
- Ordinary chat messages are sent only through manual sharing or explicitly enabled automatic party alerts.
- Personal markers are local notes, not reports to Blizzard or another service.
- Scan failures do not refresh the timestamp of a previous successful record.

When upgrading from earlier versions, ambiguous old zero values may appear as unavailable until rescanned. Previous automatic alerts, color bands, and chat labels are disabled during migration.

**`/nw clear confirm` permanently deletes local player records, personal markers, recent scan attempts, and the migration backup.** Settings are retained. Back up your SavedVariables if you want to keep the records.

## Language support

| Language | Status |
| --- | --- |
| Simplified Chinese | Available |
| English | In development — not yet available in-game |
| Additional languages | Planned |

## Acknowledgements

Thank you to the original author, subsequent community maintainers, and NGA users who contributed ideas, fixes, and feedback. This maintained version builds on their work:

- **Original NinjaWatcher release:** [NGA thread — 47784247](https://bbs.nga.cn/read.php?tid=47784247).
- **Subsequent modified version:** [NGA thread — 47910654](https://bbs.nga.cn/read.php?tid=47910654).

Keeping the NinjaWatcher name preserves addon and saved-data compatibility; it does not imply endorsement by upstream authors. See [AUTHORS.md](AUTHORS.md) for provenance and the current licensing status, and [CHANGELOG.md](CHANGELOG.md) for changes.

## Licensing status

No explicit license was found in the supplied upstream packages. Upstream permissions and a compatible project license still need to be confirmed. Attribution and public availability do not replace permission to redistribute or relicense inherited code. See [AUTHORS.md](AUTHORS.md).
