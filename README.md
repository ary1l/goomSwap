# GoomSwap

A gear-set engine for Final Fantasy XI. Define sets in one job file; GoomSwap layers the relevant sets for spells,
abilities, weapon skills, combat modes, defense and utility gear.

For **Ashita v4** (LuAshitacast). Start from an example job file and the in-game set editor (`/gcedit`).

## Features

- Weapon modes, TP and Aftermath protection, defense modes, idle Regen/Refresh, and status-specific gear.
- Precast/midcast layers, TH, spell-element gear, magic burst, Moonshade and action safety checks.
- Bellhop packer (asks only for what's missing and reachable; never twice across reloads).
- `/gcbar` status bar and `/gchud` multibox controls; colours follow goomui's preset.
- `/gcbuild` to draft a job file from carried gear; `/gcedit` to browse the character's job files, inspect gear,
  fill and compare inherited gear/stat totals, keep item details visible, and resize panels;
  arrange, hide and sort its headings, copy sets to other jobs, find an item in every job file, and edit
  settings for one character or all of them.
- TP/WS/DT/idle sets per weapon mode or weapon type (`Tp_Chango`, `Tp_2h`).

## Install

**Ashita v4**

1. Copy `common/` and `examples/` into `Ashita/config/addons/luashitacast/`.
2. Copy `examples/<JOB>.lua` into your character's LuAshitacast profile folder. Add `examples/char.lua` there if you
   want per-character settings or a Packer list.
3. Load LuAshitacast and your job file: `/addon load luashitacast`, then `/lac load`.
4. Load Ashita's `debuff` addon (`/addon load debuff`): it provides `/cancel`, which GoomSwap uses to drop Sneak or
   Stoneskin before recasting them and to cancel Stoneskin while you are asleep.
5. Einherjar: a separate addon, not part of this repository (`/ejenter`).
6. Sequencer and PacketFlow are recommended for multiboxing and action timing: [Sequencer](https://github.com/ThornyFFXI/Sequencer),
   [PacketFlow](https://github.com/ThornyFFXI/PacketFlow). [Multisend](https://github.com/ThornyFFXI/Multisend)
   (`/load multisend`) lets your boxes tell each other about incoming Cures and buffs (received sets).

## First use

1. Load the matching example job file. `/lac newlua` can create the profile folder and an empty job file.
2. Run `/gcbuild` to create `<JOB>.proposed.lua` with gear you own, or open `/gcedit` and choose **Keep only my gear**.
3. Use the editor's **To fill** and **Gear** tabs to fill empty or missing slots. **Use worn** copies your current gear
   into a set.
4. Choose **Save + reload**. The previous file is backed up; the newest ten editor backups per job are kept
   by default (`EditorBackupKeep = 0` keeps all). Other job files use **Save file** without changing your active job.
5. Run `/checksets`; use **What you actually wore** in the editor to inspect an action.

## Common commands

| Command | Purpose |
|---|---|
| `/wm [mode] [sub]` | Weapon mode, optionally with a Sub pick; right-click the bar's weapon for a menu |
| `/mw` `/sw` `/rw [item]` | Main/Sub/Range pick over the mode (any item in a `Weapon_` set) |
| `/mset [mode]` | Melee mode, such as Acc or SubtleBlow |
| `/def` | Cycle DT, MDT, Aminon and off |
| `/th` `/sir` `/kite` | Treasure Hunter, spell interruption resistance, movement gear |
| `/idleset [mode]` | Idle set mode |
| `/lock [slots]` `/unlock` | Hold equipment slots |
| `/gcbar` `/gchud` | Status bar and multibox HUD |
| `/checksets` | Validate sets |
| `/gcbuild` `/gcedit [set]` | Build or edit job sets |
| `/gchelp` | In-game command help |

See [all commands and keys](docs/commands.md).

## Documentation

- [Sets and job files](docs/sets.md)
- [Commands and keys](docs/commands.md)
- [Settings](docs/settings.md)
- [Engine behavior](docs/features.md)
- [Status bar and HUD](docs/bar.md)
- [Building a job file](docs/gcbuild.md)
- [Set editor](docs/gcedit.md)

## Troubleshooting

- **Changes do not apply:** `/lac reload`.
- **A slot will not change:** `/unlock`; check TP and Aftermath weapon holds.
- **A set is empty or gear is missing:** run `/checksets` and inspect the set in `/gcedit`.
- **An action is cancelled:** read the reason in chat; the editor's Result shows the gear path.
- **Bar or HUD is hidden:** `/gcbar on`, `/gchud on`, or `/gcbar reset`.
