# Midnight Skin Advisor (v2.0.0)

WoW AddOn for **Midnight 12.0.1** to optimize Skinning/Leatherworking farm routes using your real loot data.

## Features

- Tracks configured skinning materials from loot chat
- Weighted score/hour ranking per zone+subzone
- Preset support for your Midnight mats
- Notes for special mats and current drop-rate caveat
- Optional High-Value-Beast zone flag (`/msa hv`)
- Compact in-game UI (`/msa ui`)
- Optional TomTom waypoint support for saved spots

## Tracked Item Preset (auto-imported)

- 238511 Void-Tempered Leather
- 238513 Void-Tempered Scales
- 238518 Void-Tempered Hide
- 238520 Void-Tempered Plating
- 238525 Fantastic Fur *(special)*
- 238522 Peerless Plumage *(special)*
- 238523 Carving Canine *(special)*
- 238528 Majestic Claw
- 238529 Majestic Hide
- 238530 Majestic Fin

## Important Notes

- `Fantastic Fur`, `Peerless Plumage`, `Carving Canine` are marked as special mats requiring **Gainful Gathering** spec.
- These three are currently treated as very rare (community reports suggest potential drop issues).
- High Value Beasts can grant extra leather/scales; use `/msa hv` when farming those packs in your current zone.

## Install

1. Copy folder to:
   - `World of Warcraft/_retail_/Interface/AddOns/MidnightSkinAdvisor/`
2. Ensure files are present:
   - `MidnightSkinAdvisor.toc`
   - `MidnightSkinAdvisor.lua`
3. Restart WoW / `/reload`

## Commands

- `/msa help`
- `/msa top` — ranked zones by weighted score/hour
- `/msa ui` — toggle compact UI panel
- `/msa items` — show tracked items + weights
- `/msa note` — show farm notes
- `/msa reset` — reset tracked session data
- `/msa hv` — flag current zone for high-value-beast bonus context
- `/msa add [itemLink] <weight>` — add custom tracked item
- `/msa weight <itemID> <weight>` — tune score weight
- `/msa addspot Name x y` — save custom spot in current zone
- `/msa spots` — list saved spots
- `/msa tomtom [index]` — set TomTom waypoint to saved spot

## CurseForge Release

This repo is CurseForge-packager ready:

- Addon files are in `MidnightSkinAdvisor/`
- `.pkgmeta` is included with `package-as: MidnightSkinAdvisor`

### Option A: Automatic packaging (recommended)

1. Create a CurseForge project (WoW Retail).
2. Connect this GitHub repository in project settings.
3. Push a tag like `v2.0.1`:
   - `git tag v2.0.1 && git push origin v2.0.1`
4. CurseForge packs and publishes the release.

### Option B: Manual upload

1. Zip the `MidnightSkinAdvisor` folder (folder itself must be at zip root).
2. Upload the zip on your CurseForge project files page.

After publication, users can install/update with one click via CurseForge App/WowUp.

## Project Image

Use `assets/midnight-skin-advisor-icon.png` (512x512) as your CurseForge project/logo image.
