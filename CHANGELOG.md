# Changelog

## v2.3.2

### Improved
- Made the main UI more transparent for better world visibility while farming.
- Refined minimap button visuals (proper background + border + highlight) to avoid the odd look.

### Fixed
- Cleaned minimap icon placement/drag behavior styling.

## v2.3.1

### Fixed
- Fixed UI not opening on some clients by adding `BackdropTemplate` compatibility to the main frame.
- Improved minimap drag angle calculation fallback for client Lua variants.

## v2.3.0

### Added
- Minimap button to open the addon quickly (left-click), with drag-to-reposition (right-drag).
- Item icons in the Items tab for better visual scanning.
- Hover tooltips (“hovercards”) on rows:
  - Items: item tooltip + weight + looted count
  - Overview rows: zone summary (score/h, total loot, HV flags)
  - Spots: coordinates and TomTom hint

### Improved
- UI polish pass for better readability and less generic feel.
- Settings tab now includes minimap usage notes.
- Version bump and release-ready metadata for CurseForge upload notes.

## v2.2.0

### Added
- Polished tabbed in-game UI: Overview / Spots / Items / Settings.
- Colored score bars for top farming zones.
- Session status line with time, tracked zones, and total loot.
- Quick action button to flag High Value Beast activity.

### Improved
- Reworked presentation from plain text dump to structured UI.

## v2.0.0

### Added
- Core weighted ranking system for Skinning farm spots.
- Tracked item preset for Midnight materials.
- Notes for Gainful Gathering requirement and rare special-mat caveat.
- TomTom integration for custom saved spots.
- `/msa` command suite and compact UI toggle.
