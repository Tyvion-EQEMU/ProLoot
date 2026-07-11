# Slash Command Reference

All ProLoot commands start with `/proloot` followed by a subcommand.

---

## Starting and Stopping

| Command | Description |
|---------|-------------|
| `/lua run proloot` | Start ProLoot |
| `/lua run proloot framework=rgmercs channel=dannet` | Start with specific framework and channel |
| `/lua stop proloot` | Stop ProLoot completely |

---

## Looting

| Command | Description |
|---------|-------------|
| `/proloot loot` | Trigger an immediate loot sweep right now, regardless of the 5-second timer |
| `/proloot enable` | Resume looting (same as clicking the Running/Paused button in the panel) |
| `/proloot disable` | Pause looting (same as clicking the Running/Paused button in the panel) |
| `/proloot reload` | Reload all loot list files from disk without restarting the script |

---

## Banking

| Command | Description |
|---------|-------------|
| `/proloot bankstuff` | Open the bank confirmation window (or deposit immediately if Auto Deposit is on). Navigates to a nearby banker, then deposits all `bank`, `astrial`, and `deva` items from your bags. After depositing, automatically consolidates coins CP→PP if Auto Consolidate Coins is enabled. |

---

## Interface

| Command | Description |
|---------|-------------|
| `/proloot show` | Restore the main panel if it has been closed or minimized |
| `/proloot mini` | Toggle mini mode on/off |
| `/proloot mini on` | Force mini mode on for this character |
| `/proloot mini off` | Force mini mode off for this character |
| `/proloot editor` | Open the List Editor window |
| `/proloot eval` | Open the Upgrade Evaluator window |
| `/proloot setup` | Re-open the first-run setup dialog |

---

## Group Features

| Command | Description |
|---------|-------------|
| `/proloot toggledone` | Toggle the "Done Looting" group announce on or off for all characters in the group simultaneously (broadcasts via DanNet/EQBC) |

The **Running/Paused** button in the panel also supports group control: **Shift+Click** broadcasts
pause or resume to all group members at once (requires DanNet or EQBC).

---

## Settings

```
/proloot set <setting> <value>
```

Changes a config setting by name. Setting names are case-insensitive.

### Examples

```
/proloot set lootrange 300
/proloot set usewarp false
/proloot set weaponmode 2H
/proloot set rangedmode bows
/proloot set trashprice 50
/proloot set warpdist 150
/proloot set lootpets true
/proloot set announcedone false
/proloot set autodeposit true
/proloot set autoconsolidatecoins false
```

### All Settable Keys

| Key | Type | Example Values |
|-----|------|----------------|
| `Framework` | string | `none`, `rgmercs`, `e3` |
| `Channel` | string | `none`, `dannet`, `eqbc` |
| `WeaponMode` | string | `DW`, `2H`, `SNB`, `ANY`, `always` |
| `RangedMode` | string | `any`, `bows` |
| `LootRange` | number | `200` |
| `WarpDist` | number | `100` |
| `UseWarp` | boolean | `true`, `false` |
| `TrashPrice` | number | `50` |
| `LootEnabled` | boolean | `true`, `false` |
| `LootCorpses` | boolean | `true`, `false` |
| `LootPets` | boolean | `true`, `false` |
| `LootGroup` | boolean | `true`, `false` |
| `AnnounceGroup` | boolean | `true`, `false` |
| `AnnounceDone` | boolean | `true`, `false` |
| `AutoConsolidateCoins` | boolean | `true`, `false` |
| `BankAutoDeposit` | boolean | `true`, `false` |
| `AutoEquipUpgrades` | boolean | `true`, `false` |
| `ExcludedSlots` | string | `13,20` (comma-sep slot IDs) |
| `LogLevel` | number | `1` (Error), `2` (Warn), `3` (Info), `4` (Debug) |
| `LogToFile` | boolean | `true`, `false` |
| `LogTimestamps` | boolean | `true`, `false` |

---

## Help

```
/proloot
```

Running `/proloot` with no subcommand prints a summary of available commands to chat.
