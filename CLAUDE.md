# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An X4: Foundations (game version 9.00) extension. It adds two buttons to the ship crew panel
(Map > Information > Crew, see `Before.png`): "Assign all crew as service crew" and "Assign all crew as marines". They
reassign everyone on board except the captain to that role, immediately (no Confirm step).

Button labels are plain ASCII/Latin text on purpose: the game font does not render symbols such as `→`.

Design decision: **no dependencies** on kuertee's UI Extensions or SirNukes' Mod Support APIs.
Lua is loaded natively via `ui.xml` `<file>`.

## Layout / how the pieces connect

- `content.xml` – extension manifest (id `x4_ext_assign_crew`).
- `ui.xml` – registers `ui/assign_crew.lua` in the `menus` environment, dependent on `ego_detailmonitor` (which owns the map menu).
- `ui/assign_crew.lua` – all logic.
- `t/0001.xml` (English), `t/0001-l049.xml` (German) – text page `1739420`. The Lua has hard-coded English fallbacks if the page is missing.

### Hook mechanism (the non-obvious part)

`menu.addCrewSection(...)` in the map menu (`Helper.getMenu("MapMenu")`) builds the crew section.
The Lua wraps it. While the original runs, it temporarily shadows `inputtable.addRowGroup` on the table instance (normally a metatable method)
so every row group it creates gets a shadowed `addRow`. When the row with id `"UpdateCrew"` (the
Confirm/Reset row) is added, the button row is inserted first. All shadows are removed (set to
`nil`) after the call. This works with both vanilla `menu_map` and kuertee's substituted
`menu_map.xpl`, since both call `menu.addCrewSection` and use the `"UpdateCrew"` row id. If a game
patch renames either, the buttons silently disappear (a `DebugError` is logged if the function is missing).

### Reassignment

The buttons use the same FFI calls as vanilla's `menu.infoSubmenuConfirmCrewChanges`:
`GetPeople2` → `GetRoleTiers` → `GetRoleTierNPCs` to collect people from the source roles
(`service`/`marine` + `unassigned`), skip anyone in transit (`IsPersonTransferScheduled` /
`not HasPersonArrived`), then `C.ReassignPeople(object, CrewTransferContainer[], n)`. Afterwards,
`infoTablePersistentData.{left,right}.resetcrew = true` and the info frame is refreshed, which
also discards any unconfirmed slider changes. The captain is not part of these roles (pilot slot),
so they are excluded automatically.

FFI declarations duplicate ones already made by `menu_map`, so each `ffi.cdef` is wrapped in
`pcall` to ignore redefinition errors.

## Constraints

- The game runs **LuaJIT (Lua 5.1)**: no `table.pack`, use the global `unpack`, no integer division operator, etc.
- Reference sources for the UI code: kuertee's extracted Lua in
  `~/.steam/steam/steamapps/common/X4 Foundations/extensions/kuertee_ui_extensions/ui/addons/ego_detailmonitor/menu_map.xpl`
  (plain-text Lua with CRLF line endings; pipe through `tr -d '\r'`). The vanilla files are inside the game's `.cat/.dat` archives.

## Commands

No build step. Validation:

```sh
luajit -bl ui/assign_crew.lua >/dev/null && echo OK   # Lua syntax check
xmllint --noout content.xml ui.xml t/*.xml             # XML well-formedness
```

Install for testing: link or copy the repo to
`~/.steam/steam/steamapps/common/X4 Foundations/extensions/x4_ext_assign_crew`. Lua errors from
the mod appear in the game's debug log, prefixed with `[AssignCrew]` (launch with `-debug all -logfile debug.log`).
There are no automated tests; verify in-game on a player-owned ship.
