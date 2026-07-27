# 🛠 Update 5.1.0-beta.1

Time for another big update. This time around I've added and changed out a few mods for improved performance and better features, plus some improvements to the default configs when playing dungeons. If you run into any issues don't hesitate to report them in the Discord server. So, on to the changes:

## Added

**Optimized Block Entities** — replaces Better Block Entities.

**OneConfig** — the OneConfig menu can be opened with `Left Shift`. From there you can see all mods installed and open the config menu for all of them.

- OneConfig has global HUD editor integration for ***Odin, Skyblocker, SkyCubed, SkyHanni*** and OneConfig mods. This lets you edit GUI positions for most HUDs from one menu across different mods. Not all mods are supported, but the main ones are.
- It also has global settings search, which lets you search for a config options across most mods. Again, not all mods are supported.

**Chatting + Compacting** — replaces Enhanced Chat. Chatting has some improved features compared to Enhanced Chat, so I find it the better option at this moment in time. Compacting was added to replace the compact chat feature in Enhanced Chat, as Chatting doesn't have this. Compacting also works much better with Hypixel chat, where a lot of separator lines are sent.

**Enhanced Sound Control** — replaces Sound Controller. Your Sound Controller config will automatically migrate on update. Enhanced Sound Control also has extra features that Sound Controller doesn't have:

- When you hear a sound you want to edit, just press `N` or do `/soundcontrol`. This will open a menu with recently played sounds, and you can edit them without needing to know the name of the sound.
- It also has the option to edit sounds per SkyBlock island, so you can for example mute block breaking sounds in the Garden and still keep them the same everywhere else.

**AsyncParticles** — replaces Particle Core, has better performance.

**Async Logger**

## Removed

| Mod                   | Reason                                                                                                                                                                                                                                                |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Better Block Entities | Replaced by Optimized Block Entities                                                                                                                                                                                                                  |
| Enhanced Chat         | Replaced by Chatting + Compacting                                                                                                                                                                                                                     |
| Sound Controller      | Replaced by Enhanced Sound Control                                                                                                                                                                                                                    |
| Particle Core         | Replaced by AsyncParticles                                                                                                                                                                                                                            |
| Fzzy Config           | Not needed now that Particle Core is removed                                                                                                                                                                                                          |
| Longview              | Had some incompatibilities with other mods, so I found it was best to remove it for the time being until these get fixed.                                                                                                                             |
| Wavey Capes           | I found the mod cool, but think most people don't care, and because of that it just added bloat. If you like this mod you can always add it back yourself. (If you want to know how to add mods to the modpack send `!add-mod` in the discord server) |

## Other Changes between 5.0.15 and 5.1.0
### 🔄 Updated  
### Mods  
- **Skyrecipes**: 0.4.3+26.1.2 -> **0.4.4+26.1.2**  
- **Ixeris**: 4.5.2+26.1.2-fabric -> **4.6.1+26.1.2-fabric**  
- **Packcore**: 5.0.12+26.1.2 -> **5.1.0+26.1.2**  
- **Scaleme**: 3.2.1+26.1.2 -> **3.3.0+26.1.2**  
- **SkyHanni**: 7.37.0-mc26.1 -> **7.38.0-mc26.1**  
- **Skyblocker**: 6.7.0+26.1.2 -> **6.8.0+26.1.2**
  
## Default Config v5.1

Most of Odin config changes were brought to you by fuschen. Thanks for the help.

<details> <summary><b>Click to expand the full config list</b></summary>

### Odin

|Setting|Value|
|---|---|
|Invincibility Timer|`On`|
|Invincibility Timer → Invincibility Timer|`On`|
|Invincibility Timer → Show in Boss|`On`|
|Breaker Display|`Off`|
|Secret Clicked|`On`|
|Secret Clicked → Style|`Filled Outline`|
|Secret Clicked → Depth check|`On`|
|Secret Clicked → Chime Sound|`block.wool.break`|
|Secret Clicked → Chime Sound Volume|`0.69`|
|Mage Beam|`On`|
|Mage Beam → Color|`00DFF9FF`|
|Mimic|`On`|
|Melody Message → Progress GUI|`On`|
|Melody Message → Melody Progress|`On`|
|Wither Dragons|`On`|
|Wither Dragons → Solo Debuff on All Splits|`On`|
|Arrows Device|`On`|
|Arrows Device → Show Aim Positions|`On`|
|Simon Says|`On`|
|Simon Says → Block Wrong Clicks|`On`|
|Simon Says → Block Wrong on Start|`On`|
|Extra Stats|`On`|
|Spirit Bear|`On`|
|Chat Commands|`On`|
|Chat Commands → Chat Emotes|`On`|
|Chat Commands → Odin|`Off`|
|Chat Commands → Coords (`coords`)|`Off`|
|Chat Commands → Party transfer (`pt`)|`On`|
|Chat Commands → Reinvite|`On`|
|Chat Commands → Kick Offline|`On`|

### Stella

|Setting|Value|
|---|---|
|Dungeon Map|`On`|
|Check for Updates|`Off`|

### SkyHanni

|Setting|Value|
|---|---|
|Death Counter Display|`Off`|
|Personal Compactor Overlay|`Off`|
|Milestone Display|`Off`|

### Skyblocker

|Setting|Value|
|---|---|
|Device Solvers → Solve Simon Says|`Off`|
|Gyro Overlay → Gyrokinetic Wand Mode|`Circle Outline`|
|Quick Navigation → Button 4|`/loadout`|

</details>

---
  
### 🛠 Troubleshooting & Tips  
- The first launch after updating may take slightly longer than usual.  
- If Modrinth does not show the update, refresh the instance page or just wait abit.  
  
### 💡 Need Help?  
Join us on **[Discord](https://discord.gg/pdwxyjTta7)** or **[Fluxer](https://fluxer.gg/3jJy9cp6)** for support.  
  
Thanks for using SkyBlock Enhanced!
