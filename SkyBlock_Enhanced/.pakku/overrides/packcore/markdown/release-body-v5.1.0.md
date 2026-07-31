# 🛠 Update 5.1.0

Version 5.1 is now out of beta and ready for use. Below is a complete overview of the changes between versions **5.0.15** and **5.1**.

Note during the beta, 5.1 included **OneConfig**. After receiving feedback, I decided to remove it from the modpack. While it worked well for many users, others experienced compatibility issues and performance regressions, making it a poor fit overall.

OneConfig's unified config search and HUD editor were nice additions, but in practice they didn't outweigh the downsides. Since OneConfig only supports a limited number of mods, I often found it just as fast to search each mod's settings individually, starting with the larger ones. The HUD editor also wasn't perfect and could be difficult to work with, so using each mod's built-in editor was usually the better experience.

Taking all of this into account, I didn't feel the added complexity and potential performance regressions were worth the benefits, so I decided to remove it from the default modpack.

With both 5.0 and 5.1, my main focus has been improving performance and stability. That will continue with the upcoming 5.2 update, and I hope you understand and agree with the decision.

If you didn't experience any issues and would like to continue using OneConfig, you can easily add it back yourself. To learn how, type `!add-mod` in any Discord channel and the bot will reply with a tutorial.

## Added

### Optimized Block Entities

Replaces **Better Block Entities** with improved performance.

### Enhanced Sound Control

Replaces **Sound Controller**. Your existing Sound Controller configuration will automatically be migrated when you update.

Enhanced Sound Control also includes several new features:

* Press `N` (or run `/soundcontrol`) after hearing a sound to open a list of recently played sounds. You can edit them without needing to know their internal names.
* Configure sound volumes separately for each SkyBlock island. For example, you can mute block breaking sounds only in the Garden while keeping them unchanged everywhere else.

### AsyncParticles

Replaces **Particle Core** and provides better performance.

### Async Logger

## Removed

| Mod                   | Reason                                                                                                                                                                                     |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Better Block Entities | Replaced by Optimized Block Entities.                                                                                                                                                      |
| Sound Controller      | Replaced by Enhanced Sound Control.                                                                                                                                                        |
| Particle Core         | Replaced by AsyncParticles.                                                                                                                                                                |
| Fzzy Config           | No longer required now that Particle Core has been removed.                                                                                                                                |
| Longview              | Removed due to compatibility issues with other mods. It may return once those issues are resolved.                                                                                         |
| Wavey Capes           | While a fun cosmetic mod, it wasn't used by most players and only added extra bloat. If you'd like to keep using it, you can add it back yourself with the `!add-mod` tutorial in Discord. |

## Other Changes

### Updated Mods

* **Ixeris:** 4.5.2+26.1.2-fabric → **4.6.1+26.1.2-fabric**
* **Lithium Fabric:** 0.24.6 → **0.24.7**
* **Packcore:** 5.0.12+26.1.2 → **5.1.1+26.1.2**
* **Scaleme:** 3.2.1+26.1.2 → **3.3.0+26.1.2**
* **SkyHanni:** 7.38.0-mc26.1 → **7.41.0-mc26.1**
* **Enhanced Storage:** 1.0.1+26.1.2 → **1.1.0+26.1.2**
* **Skyblocker:** 6.7.0+26.1.2 → **6.8.2+26.1.2**

# Default Config v5.1

Most of the Odin configuration changes were contributed by **fuschen**. Thanks for the help!

<details>
<summary><b>Click to expand the full config list</b></summary>

### Odin

| Setting                                    | Value              |
| ------------------------------------------ | ------------------ |
| Invincibility Timer                        | `On`               |
| Invincibility Timer → Invincibility Timer  | `On`               |
| Invincibility Timer → Show in Boss         | `On`               |
| Breaker Display                            | `Off`              |
| Secret Clicked                             | `On`               |
| Secret Clicked → Style                     | `Filled Outline`   |
| Secret Clicked → Depth Check               | `On`               |
| Secret Clicked → Chime Sound               | `block.wool.break` |
| Secret Clicked → Chime Sound Volume        | `0.69`             |
| Mage Beam                                  | `On`               |
| Mage Beam → Color                          | `00DFF9FF`         |
| Mimic                                      | `On`               |
| Melody Message → Progress GUI              | `On`               |
| Melody Message → Melody Progress           | `On`               |
| Wither Dragons                             | `On`               |
| Wither Dragons → Solo Debuff on All Splits | `On`               |
| Arrows Device                              | `On`               |
| Arrows Device → Show Aim Positions         | `On`               |
| Simon Says                                 | `On`               |
| Simon Says → Block Wrong Clicks            | `On`               |
| Simon Says → Block Wrong on Start          | `On`               |
| Extra Stats                                | `On`               |
| Spirit Bear                                | `On`               |
| Chat Commands                              | `On`               |
| Chat Commands → Chat Emotes                | `On`               |
| Chat Commands → Odin                       | `Off`              |
| Chat Commands → Coords (`coords`)          | `Off`              |
| Chat Commands → Party Transfer (`pt`)      | `On`               |
| Chat Commands → Reinvite                   | `On`               |
| Chat Commands → Kick Offline               | `On`               |

### Stella

| Setting           | Value |
| ----------------- | ----- |
| Dungeon Map       | `On`  |
| Check for Updates | `Off` |

### SkyHanni

| Setting                    | Value |
| -------------------------- | ----- |
| Death Counter Display      | `Off` |
| Personal Compactor Overlay | `Off` |
| Milestone Display          | `Off` |

### Skyblocker

| Setting                              | Value            |
| ------------------------------------ | ---------------- |
| Device Solvers → Solve Simon Says    | `Off`            |
| Gyro Overlay → Gyrokinetic Wand Mode | `Circle Outline` |
| Quick Navigation → Button 4          | `/loadout`       |

### Enhanced Chat

| Setting      | Value |
| ------------ | ----- |
| Compact Chat | `Off` |

</details>

---

## 🛠 Troubleshooting & Tips

* The first launch after updating may take slightly longer than usual.
* If Modrinth doesn't show the update immediately, refresh the instance page or wait a few minutes.

## 💡 Need Help?

Join us on **Discord** or **Fluxer** if you need support.

* https://discord.gg/pdwxyjTta7
* https://fluxer.gg/3jJy9cp6

Thanks for using SkyBlock Enhanced!
