# Configuration

ProLoot stores settings in two INI files in your MacroQuest config directory:

- `SharedSettings_<Server>.ini` — group-wide settings; one file shared across all characters
- `CharSettings_<Server>_<CharName>.ini` — per-character overrides

You rarely need to edit these directly. All settings are accessible from the main panel
or via the `/proloot set` command.

---

## Integration (Framework)

**Setting:** `Framework`  
**Shared:** Yes  
**Options:** `None` | `RG Mercs` | `E3`  
**Location:** System Settings (collapsed section in the main panel)

Which bot framework ProLoot works alongside. When a loot sweep starts, ProLoot pauses
the framework so it doesn't interfere with movement to corpses, then resumes it when
the sweep is done. With `RG Mercs`, if you'd paused RGMercs yourself before the sweep
started, ProLoot recognizes that and leaves it paused instead of resuming it for you.

Set to `None` if you are running ProLoot standalone without a bot framework.

---

## Broadcast (Channel)

**Setting:** `Channel`  
**Shared:** Yes  
**Options:** `None` | `DanNet` | `EQBC`  
**Location:** System Settings (collapsed section in the main panel)

The network channel used to share loot events and group pause/resume commands across
characters. With DanNet or EQBC enabled, loot history from all group members appears
in each character's history window, and **Shift+Click** on the Running/Paused button
broadcasts pause/resume to the whole group.

Requires the corresponding MQ2 plugin to be loaded (MQ2DanNet or MQ2EQBC).

---

## Weapon Mode

**Setting:** `WeaponMode`  
**Shared:** No (per-character)  
**Options:** `Dual Wield` | `Two-Handed` | `Sword and Board` | `Any / No Restriction` | `Always Keep`

Controls which weapon types are considered when evaluating gear upgrades for the
Primary and Secondary slots. Items that don't match the mode are not kept as upgrades
even if the stats are better. Hover over each option in the dropdown for a tooltip
describing it.

| Mode | Primary slot | Secondary slot | Notes |
|------|-------------|----------------|-------|
| Dual Wield | 1H weapons only | 1H weapons only | |
| Two-Handed | 2H weapons only | N/A (2H occupies both) | |
| Sword and Board | 1H weapons only | Shields only | |
| Any / No Restriction | Any weapon | Any weapon | |
| Always Keep | Keep all wearable items | Keep all wearable items | Ignores stat comparison entirely |

Armor slots (head, chest, legs, etc.) are always evaluated regardless of weapon mode,
except in **Always Keep** mode which keeps everything regardless of stats.

---

## Ranged Slot

**Setting:** `RangedMode`  
**Shared:** No (per-character)  
**Options:** `Any Ranged` | `Only Bows`

Controls how items that fit the Ranged equipment slot are evaluated.

- **Any Ranged** — standard upgrade logic using AC/HP/Mana comparison. Any ranged item
  that beats your current equipped item by stats will be kept.
- **Only Bows** — only bow-type items (archery, crossbow) are considered for the ranged
  slot. Non-bow ranged items are skipped entirely. When a bow does compete, it is scored
  on damage/delay ratio rather than AC/HP. Recommended for Rangers and melee characters
  that pull with bows.

---

## Loot Range

**Setting:** `LootRange`  
**Shared:** Yes  
**Range:** 50 – 600 units  
**Default:** 200

The radius around your character that ProLoot scans for NPC corpses. Corpses beyond this
distance are ignored until you move closer.

Use **Ctrl+Click** on the slider in the panel to type an exact value.

---

## Use Warp

**Setting:** `UseWarp`  
**Shared:** Yes  
**Default:** `true`

When enabled, ProLoot uses `/warp target` (MQ2RWarp) to teleport directly to a corpse
or banker. When disabled, it uses `/nav` to walk there. Requires **MQ2RWarp.dll** to
be loaded.

---

## Warp Distance

**Setting:** `WarpDist`  
**Shared:** Yes  
**Default:** 100

*UI control coming soon — currently set via `/proloot set warpdist <value>`.*

Maximum distance at which ProLoot will warp to a corpse. Corpses closer than this value
are walked to even when Use Warp is enabled. Set to `0` to always warp regardless of
distance.

---

## Auto Equip

**Setting:** `AutoEquipUpgrades`  
**Shared:** No (per-character)  
**Default:** `true`  
**Location:** Inline with Use Warp in the main panel

When enabled, items evaluated as gear upgrades are equipped immediately during looting —
the new item swaps into the worn slot and the displaced item goes to your bags. This is
the default behavior.

When disabled, upgrade items are picked up and placed in bags via `/autoinventory` without
equipping. The loot history entry shows reason `upgrade-bagged` so you can find and review
them later. Useful when you want to inspect an item before committing to equipping it.

---

## Slot Exclusions

**Setting:** `ExcludedSlots`  
**Shared:** No (per-character)  
**Default:** *(empty — no slots excluded)*  
**Location:** Main panel settings table

A multi-select dropdown listing all gear slots. Any slot you check here is skipped
entirely during upgrade evaluation — ProLoot will never consider replacing whatever is
currently equipped in that slot.

Useful for:
- Custom or server-specific items with unusual stats that score incorrectly against
  standard AC/HP/Mana/damage-ratio logic
- Slots where you have a hand-picked item you never want displaced

Stored as a comma-separated list of internal slot IDs in the per-character INI
(e.g. `ExcludedSlots=13,20` for Primary and Waist). Can also be set via:
```
/proloot set ExcludedSlots 13,20
```

---

## Done Looting

**Setting:** `AnnounceDone`  
**Shared:** Yes  
**Default:** `true`

When enabled, each character broadcasts `/g Done Looting` in group chat after a sweep
that clears all nearby corpses. Useful for coordinating when the group can move on.

---

## Trash Price

**Setting:** `TrashPrice`  
**Shared:** Yes  
**Default:** 0  

*UI control coming soon — currently set via `/proloot set trashprice <value>`.*

Minimum platinum value for an item to be automatically sold rather than skipped. Items
worth less than this value that aren't on any keep list are left on the corpse. Set to
`0` to never auto-sell by price.

---

## Loot Enabled

**Setting:** `LootEnabled`  
**Shared:** No (per-character)  
**Default:** `true`

Whether this character is currently looting. Controlled by the **Running/Paused** toggle
button in the panel (click to toggle; Shift+Click broadcasts to the whole group). Saved
per-character so each toon can be individually paused.

---

## Auto Consolidate Coins

**Setting:** `AutoConsolidateCoins`  
**Shared:** Yes  
**Default:** `true`  
**Location:** Bank & Vendor settings pane

When enabled, ProLoot automatically converts all carried coins to the highest denomination
(copper → silver → gold → platinum) after each BankStuff deposit. Requires the bank
window to be open — this is why it runs as part of the bank visit rather than on demand.

The **Consolidate Coins** button in the BankStuff confirmation window always runs
regardless of this setting.

---

## Auto Deposit (Bank)

**Setting:** `BankAutoDeposit`  
**Shared:** No (per-character)  
**Default:** `false`  
**Location:** Bank & Vendor settings pane

When enabled, `/proloot bankstuff` skips the confirmation window and immediately deposits
all `bank`, `astrial`, and `deva` items without prompting. Useful for characters on
scheduled bank runs where you always want to deposit everything.

---

## Console

The **Console** section in the main panel (collapsed by default) provides in-panel log
output and controls for the logging system.

### Log Level

**Setting:** `LogLevel`  
**Shared:** No (per-character)  
**Options:** `1` Error | `2` Warn | `3` Info | `4` Debug  
**Default:** `3` (Info)

Controls how verbose the console output is. Debug shows every item evaluation decision.

### Log to File

**Setting:** `LogToFile`  
**Shared:** No (per-character)  
**Default:** `false`

When enabled, all console output is also written to:
```
<MQ2 config dir>/proloot/ConsoleLogs_<Server>_<CharName>.log
```

### Show Timestamps

**Setting:** `LogTimestamps`  
**Shared:** No (per-character)  
**Default:** `false`

Prepends a `HH:MM:SS` timestamp to each line in the console output.

---

## Other Toggles (UI coming soon)

These settings exist in the config engine and can be set via `/proloot set <key> <value>`:

| Setting | Default | Description |
|---------|---------|-------------|
| `LootCorpses` | `true` | Master toggle for NPC corpse looting |
| `LootPets` | `false` | Whether to loot pet corpses |
| `LootGroup` | `false` | Whether to loot nearby group members' corpses |
| `AnnounceGroup` | `false` | Broadcast every loot event to group chat |
