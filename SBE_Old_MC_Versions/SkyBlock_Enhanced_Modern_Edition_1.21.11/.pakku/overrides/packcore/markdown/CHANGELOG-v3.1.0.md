# 🛠 Update 3.1.0  

## ✨ New Features

### Chat Enhancements

- **Compact Duplicate Messages**: Merges repeated chat messages into a single line with an occurrence counter (×N).  
  - Optional setting to only compact consecutive duplicates.
- **Centered Hypixel Text**: Properly centers space-padded Hypixel messages in the chat window.
- **Smooth Separators**: Replaces dash/line separators with clean horizontal lines.
- **Chat Tabs**: Adds Hypixel channel tabs (All, Party, Guild, PM, Co-op) above the chat input.  
  - Button textures by [Bentcheesee](https://modrinth.com/user/Bentcheesee) — huge thanks!
- **Extended Chat History**: Increases the chat history limit from 100 to a configurable value (up to 2048).
- **Chat Animation**: Smooth slide-up animation when new messages appear and when opening chat.

---

## ❌ Removed

### Mods
- Chat Patches (Replaced by Skyblock Enhancements)

---

## ➕ Added

### Mods
- Catharsis

### Resource Packs
- PacksHQ

---

## 🔄 Updated  

### Mods  
- **packcore**: 4.2.1+1.21.11 → **4.2.2+1.21.11**  
- **skyblock_enhancements**: 0.9.0+1.21.11 → **0.10.0+1.21.11**  

### Resource Packs  
- **Looshy [1.21.x] (v0.9.9)** → Updated to latest version  
- **Furfsky** → Updated to latest version  

---

## 🚧 Work in Progress

### Recipe Viewer Integration

> Requires the [Reliable Recipe Viewer (RRV)](https://modrinth.com/mod/rrv)

Currently, to use the recipe viewer:
- Disable REI manually  
- Install RRV yourself  

This will be added as the main option soon, but needs more testing first.

### Features

Recipe data is sourced from the **NEU repository**, downloaded and cached on first launch.  
Use `/skyblockenhancements refresh repoData` to force a manual refresh.

- **SkyBlock Crafting**: 3×3 crafting recipes for SkyBlock items  
- **SkyBlock Forge**: Forge recipes with ingredients, result, and readable duration (e.g. "2h 30m")  
- **SkyBlock NPC Shop**: Shows up to 5 cost items + result, with an "NPC Info" button  
- **SkyBlock NPC Info**: Displays NPC head, island, coordinates, lore, and navigation support for [SkyHanni](https://modrinth.com/mod/skyhanni)  
- **SkyBlock Mob Drops**: 4×3 grid with drop chances  
- **SkyBlock Trade**: Simple 1:1 trades  
- **Kat Pet Upgrade**: Shows pet upgrades, materials, coin cost, and time  
- **SkyBlock Wiki**: Fallback info card for items with wiki links  
- **Search Calculator**:
  - Supports +, -, *, /, %, ^, and parentheses  
  - SkyBlock suffixes (k, m, b, t, st)  
  - Scientific notation (e.g. 1.5e6)  
  - Functions: sqrt(), abs(), floor(), ceil(), round()  

- **Category Filtering**: Filter items by category (e.g. armor, weapons)  

---

## ⚙️ Config Changes (33.0.2 → 3.0.3)

- Set **Background Fade-In Duration** to 0 in Modern UI  
- Removed Chat Patches config  

---

## 🛠 Troubleshooting & Tips  

 - The first launch after updating may take slightly longer than usual.  
 - If Minecraft appears frozen while loading, wait a moment before closing it.  
 - If Modrinth does not show the update, refresh the instance page.

---

## 💬 Need Help?  

Join us on **[Fluxer](https://fluxer.gg/3jJy9cp6)** (recommended) or **[Discord](https://discord.gg/pdwxyjTta7)**  

---

Thanks for using SkyBlock Enhanced!
