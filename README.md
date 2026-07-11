# ProLoot

Automated loot management specific to EQ EMU server, Profusion, for running users MacroQuest. ProLoot handles
corpse detection, item evaluation, gear upgrades, bank runs, selling vendor trash and provides a filterable group loot history; designed to run alongside frameworks like RGMercs, E3, and KissAssist.

<p align="center"><img width="350" alt="image" src="https://github.com/user-attachments/assets/b002f0fe-5f92-4b8f-ac0b-a533bdfa930d" /></p>

---

## Use Cases

### Solo or Casual Play
Run ProLoot in the background while you grind. It scans for corpses every 5 seconds,
walks or warps to them, evaluates every item against your keep/sell/destroy lists and
gear upgrade logic, and handles the loot window — all without you touching a thing.

### Multi-Toon Boxing with a Bot Framework
ProLoot integrates with RGMercs and will soon with E3. When a loot sweep starts it pauses
the framework so automation doesn't interfere with looting, then resumes when done — and
if you'd paused the framework yourself, ProLoot leaves it alone instead of resuming it for you.

### Global Command & Control
A single **Shift+Click** on the pause button broadcasts pause or resume to your entire
group at once. Loot history from all toons streams into each character's history window
via DanNet or EQBC.

<p align="center"><img width="350" alt="Pause/Unpause" src="https://github.com/user-attachments/assets/ee4d9551-ff46-457b-879d-43687708d484" /></p>

### Profusion Specific Progression
Collects every progression-tier item and book page for you. When you are ready, `/proloot bankstuff`
walks you to a banker, shows you everything it found, and deposits it all in one step —
no bag-sorting required.

### Bank Runs
At the end of a session, run `/proloot bankstuff` on each toon. ProLoot auto-targets a
nearby banker (or navigates to one), shows a confirmation window with item details and deposits 
everything tagged, then consolidates your coins from copper up to platinum automatically.

**Warning** -- When banking, the script will CONTROL  your mouse, interfering could cause something to fail.

<p align="center"><img width="350" alt="BankStuff_Button" src="https://github.com/user-attachments/assets/6c732b3f-db82-4bb2-b573-669387157478" /></p>

#### Bank Stuff (Solo)
<p align="center"><img width="350" alt="Solo_Bank_Review" src="https://github.com/user-attachments/assets/e247e179-8fff-4a94-85e2-2bca294ee195" /></p>

#### Bank Stuff (Group Review)
<p align="center"><img width="350" alt="Group_Bank_Review" src="https://github.com/user-attachments/assets/c3f6ad02-3230-4945-982f-1096a800f9db" /></p>

### Gear Upgrades
Tell ProLoot your weapon style (Dual Wield, Two-Handed, Sword and Board, or Always Keep)
and it scores every piece of gear it finds against what you have equipped. Items that beat
your current stats are kept; everything else is sold or left behind.

Use **Slot Exclusions** to protect specific gear slots from being replaced — useful for
custom or server-specific items that wouldn't score correctly against standard stat logic.

Toggle **Auto Equip** off if you'd rather review upgrades before equiping. When off,
upgrade items land in your bags with a reason of `upgrade-bagged` in the loot history so
you can inspect and equip them manually.

<p align="center"><img width="350" alt="Main_Settings" src="https://github.com/user-attachments/assets/edd8c933-0ddd-4462-b64b-892a84fab505" /></p>

### Upgrade Evaluator
Run `/proloot eval` any time to scan your bags for upgrades against what's currently equipped —
no corpse required. See exactly what would change, remove augments from old gear, or equip an
upgrade on the spot and have its old augments carried over automatically.

<p align="center"><img width="997" height="969" alt="Proloot_Upgrade" src="https://github.com/user-attachments/assets/e1bcb897-cc34-4a98-9884-9a36aea8ca79" /></p>

<p align="center"><img width="997" height="958" alt="Proloot_non-upgrade" src="https://github.com/user-attachments/assets/728ba2d4-209f-4333-b7a6-b9c01cae46be" /></p>

---

## Requirements

- **MacroQuest** with Lua support (MQ2Lua plugin loaded)
- **MQ2Nav** — required for walking to corpses or bankers when warp is disabled
- **MQ2DanNet** *(optional)* — enables group-wide broadcast of loot events and pause/resume
- **MQ2EQBC** *(optional)* — alternative to DanNet for group broadcast
- **MQ2RWarp** *(optional)* — enables instant warp to corpses instead of walking

---

## Installation

1. Download the latest version at https://github.com/Tyvion-EQEMU/ProLoot/releases/latest
2. Extract & Copy the `proloot` folder into your MacroQuest `lua` directory:
   ```
   <MQ2 install path>\lua\proloot\
   ```
   The folder should contain `init.lua` directly inside it — not nested deeper.

3. Verify the structure looks like this:
   ```
   lua/
   └── proloot/
       ├── init.lua
       ├── config.lua
       ├── core/
       ├── ui/
       ├── lists/
       └── adapters/
   ```
<p align="center".<img width="450" alt="ProLoot_Directory_Structure_Example" src="https://github.com/user-attachments/assets/0f623606-4123-43a0-aecf-314815882dd9" /></p>

---

## First Launch

In the EverQuest chat window, type:

```
/lua run proloot
```

On your very first run, a **Setup dialog** will appear asking you to choose your automation
framework (RGMercs, E3, KissAssist, or None) and broadcast channel (DanNet, EQBC, or
None). These can be changed later from the main panel.

To start ProLoot with a specific framework or channel without going through setup:

```
/lua run proloot framework=rgmercs channel=dannet
```

---

## The Main Window

Once running, a panel appears with:

- **Running / Paused button** — single wide toggle. Click to pause or resume looting for
  this character. **Shift+Click** broadcasts pause/resume to your whole group (requires
  DanNet or EQBC). The button is green when running and red when paused.
- **Settings** — Weapon Mode, Ranged Slot, Loot Range, Min. Sell Value, Use Warp / Auto Equip (inline), Share Done Looting, Slot Exclusions
- **History** — opens the loot history window showing every item decision this session
- **List Editor** — opens the item list manager to add/remove items from all loot categories
- **Vendor Settings** — opens the vendor/bank settings pane (Auto Consolidate Coins, Auto Deposit, Auto Sell, Auto Restock)
- **System Settings** *(collapsed)* — Integration (framework) and Broadcast (channel); rarely changed after setup
- **Console** *(collapsed)* — scrollable in-panel log output with Log Level, Log to File, and Show Timestamps controls
- **Status** — shows nearby corpse count and current state: `Running`, `Paused`, or `Combat`

The **minimize button** (top-right of the panel) collapses ProLoot into a small overlay
showing just the enable toggle and status. A red border on the mini window means your
character is in combat and looting is temporarily suspended.

---

## How Looting Works

Every 5 seconds ProLoot scans for NPC corpses within your configured **Loot Range**.
For each corpse it finds (closest first), it:

1. Checks it is safe to loot (not dead, not casting, not moving)
2. Approaches the corpse (warp or walk depending on your setting)
3. Opens the corpse and evaluates each item against your loot lists and upgrade logic
4. Keeps, sells, destroys, or skips each item based on the decision
5. Closes the corpse and marks it done for this zone session

Looting is automatically suspended while your character is in combat and resumes once
all enemies are gone. Your **Pause/Resume** setting is separate from combat — pausing
manually stays paused until you resume manually.

---

## BankStuff

Run `/proloot bankstuff` to deposit your collected items at a banker.

1. ProLoot searches for a nearby banker and navigates to them (auto-targets known bankers
   such as Gordon Gekko in Nexus, Banker Ceridan in Plane of Knowledge, or a bank broker
   in the Guild Hall)
2. A confirmation window lists everything it found in your bags tagged — hover any item name for a full tooltip with icon, lore, stats, and value
3. Click **Bank All** to deposit, **Consolidate Coins** to convert CP/SP/GP → PP only,
   or **Rescan** to refresh the list
4. After depositing, coins are automatically consolidated (configurable in Bank & Vendor settings)

Enable **Auto Deposit** in Bank & Vendor settings to skip the confirmation window entirely.

---

## Loot Lists

Items are matched against named lists in priority order. See [Loot Lists](docs/loot-lists.md)
for a full explanation of each list type and how to manage them.

---

## Configuration

All settings are explained in [Configuration](docs/configuration.md).

---

## Slash Commands

Full command reference in [Commands](docs/commands.md).

---

## Per-Character vs Shared Settings

Some settings (Framework, Channel, Loot Range, Use Warp, etc.) are **shared** — changing
them on one character updates all characters on the next restart. Others (Weapon Mode,
Ranged Slot, Loot Enabled, Auto Equip, Slot Exclusions) are **per-character** so each
toon can have its own values.

---

## Config Files

All ProLoot files are kept in their own subfolder so they don't clutter the main config directory:

```
<MQ2 config dir>/proloot/
├── SharedSettings_<Server>.ini
├── CharSettings_<Server>_<CharName>.ini
├── CharLogs_<Server>_<CharName>.log
├── LootList_<Server>_currency.txt
├── LootList_<Server>_quest.txt
└── ... (one LootList txt per list type)
```

The folder is created automatically on first run.

---

## Support

- Report bugs or request features via [GitHub Issues](../../issues)
- Future plans in [ROADMAP.md](ROADMAP.md)
