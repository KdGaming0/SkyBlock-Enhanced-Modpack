{gold}**Frequently Asked Questions (FAQ)**{}  


{gold}**📦 General Questions**{}  

{yellow}**What is SkyBlock Enhanced?**{}  
SkyBlock Enhanced is a complete modpack made for Hypixel SkyBlock. It brings the game to modern Minecraft (1.21+) with high FPS, smart overlays, and a smooth experience. The pack includes top mods like SkyHanni, Skyblocker, Firmament, Sodium, and Iris—all preconfigured for performance and stability.  

{yellow}**Is the pack preconfigured?**{}  
Yes! The pack includes preconfigured settings for 1080p, 1440p, and 4K. On first launch, it detects your screen resolution and applies the right config. Everything is set up to work together without overlapping or cluttered interfaces.  

{yellow}**What makes a preconfigured pack special?**{}  
When you mix several big mods with custom overlays and smaller add-ons, they often overlap or show duplicate info.  
A preconfigured pack fixes that by disabling duplicates, placing elements correctly, and tailoring layouts for each resolution.  
Without setup, you’d see text and icons overlapping, blocking each other, or scattered across the screen.  

{yellow}**How do I access the in-game guides?**{}  
Type `/packcore guides` in chat or click the *Guides* button from the main menu.  



{gold}**⚙️ Configuration & Setup**{}  

{yellow}**How do I change my performance profile?**{}  
You can switch between *Performance*, *Balanced*, *Quality*, or *Shaders* anytime:  

1. Type `/packcore performance [performance, balanced, quality, shaders]`
2. Run the command

{#275EF5}**Profile Overview:**{}  
- {gold}**Performance**{} – Best for older PCs, disables fancy effects  
- {gold}**Balanced**{} – Recommended default for most users  
- {gold}**Quality**{} – Best visuals without shaders  
- {gold}**Shaders**{} – For mid/high-end systems only  

{yellow}**How do I reset my configs to default?**{}  
See the *How to Reset Configs* guide for full steps.  

Quick version:  
1. From the main menu, open the *Config Manager* or use `/packcore configmanager`  
2. Click the config you want  
3. Apply it  
4. The game will close  
5. Reopen the game  
6. Config is now applied  
7. Check using `/packcore status`  

{yellow}**Can I switch resource packs after setup?**{}  
Yes. Go to *Options → Resource Packs* to enable, disable, or reorder packs.  
> {#275EF5}**Tip:**{} Packs at the top override packs below.  

{yellow}**How do I import community configs?**{}  
1. Open the *Config Manager* (`/packcore configmanager`)  
2. Click *Import*  
3. Download a community config from Discord  
4. Import and apply it  



{gold}**🎮 Performance & Technical**{}  

{yellow}**How much RAM should I allocate?**{}  
It depends on your system:  
- 8GB system – 3–4GB  
- 16GB system – 4–6GB  
- 32GB+ system – 6–10GB  

> {#275EF5}**Important:**{} Don’t allocate more than ***half of your system RAM***.  
See the *RAM Allocation Guide* for details.  

{yellow}**The game is lagging. What should I do?**{}  
1. Switch to *Balanced* or *Performance* profile  
2. Allocate at least 4GB RAM  
3. Make sure Minecraft uses your **dedicated GPU**  
4. Disable shaders (*K*)  
5. Lower render distance to 10–12  
6. Update GPU drivers  

See the *Troubleshooting Common Issues* guide for more help.  

{yellow}**Why is my FPS low with shaders?**{}  
Shaders are demanding.  
Try disabling them (**K**) or lowering render distance.  
> {#275EF5}**Note:**{} Some shaders may break overlays or waypoints.  

{yellow}**How do I check FPS and memory usage?**{}  
Press ***F3***:  
- *Top-left* → FPS  
- *Top-right* → Memory usage  

If memory hits **90–95%**, increase allocated RAM.  



{gold}**🎨 Resource Packs**{}  

{yellow}**I'm getting “Resource Reload Failed” error. How do I fix it?**{}  
Large packs need a special JVM argument.  
See the *Fix Resource Reload Failed Error* guide.  

Quick fix: Add `-Xss4M` to your JVM arguments in launcher settings.  

{yellow}**Which resource pack combination is best?**{}  
Popular picks:  
- Hypixel Plus + SkyBlock Dark UI  
- FurfSky Overlay + SkyBlock Dark UI  
- SkyBlock Dark UI + Defrosted + Looshy  
- Hypixel Plus (standalone)  
- FurfSky Full (standalone)  

> {#275EF5}**Warning:**{} FurfSky Full + SkyBlock Dark UI can conflict in some menus.  

{yellow}**How do I change resource pack priority?**{}  
Go to *Options → Resource Packs*.  
Drag packs to reorder — the **top** pack has priority.  



{gold}**🔧 Mod Configuration**{}  

{yellow}**How do I move GUI elements?**{}  
Press **G** to open the GUI editor (SkyHanni).  
For SkyBlocker widgets, use `/widgets`.  

{yellow}**How do I disable an overlay?**{}  
1. Press **G**  
2. Right-click the overlay  
3. Toggle it off  

For SkyBlocker, use `/skyblocker config` and search the widget.  

{yellow}**How do I open a mod’s config menu?**{}  
1. Type the mod’s command (e.g. `/sh`, `/skyblocker`)  
2. Or press *ESC → Mods → Configure*  

{yellow}**Where can I find specific features?**{}  
Most are in SkyHanni or SkyBlocker:  
- `/sh` or `/skyblocker config`  
- Use search in config menus  
- See the *Feature Showcase* in `/packcore guides`  



{gold}**🎯 Keybinds**{}  

{yellow}**Main Keybinds:**{}  
- **G** – GUI Editor  
- **M** – Warp Menu  
- **F1** – Fandom Wiki Lookup  
- **F4** – Hypixel Wiki Lookup  
- **F6** – Item Price Lookup  
- **K** – Toggle Shaders  
- **P** – Protect Item  

See the *Getting Started* guide for the full list.  

{yellow}**Can I change keybinds?**{}  
Yes. Go to *Options → Controls* and search for them.  



{gold}**🐛 Troubleshooting**{}  

{yellow}**The game crashes on launch.**{}  
1. Make sure you have at least 4GB RAM  
2. Remove manually added mods  
3. Check crash logs in `crash-reports`  

See the *Troubleshooting Common Issues* guide.  

{yellow}**Mods aren’t showing up.**{}  
- File corrupted (must end in `.jar`)  
- Missing dependencies  
- Wrong mod loader (*Fabric ≠ Forge*)  
- Incompatible version  

{yellow}**How do I share log files?**{}  

{#275EF5}**Modrinth App:**{}  
- Open instance → ⋯ → *Open Folder* → `logs`  
- Upload `latest.log` to [mclo.gs](https://mclo.gs)  

{#275EF5}**Prism Launcher:**{}  
- Instance → *Folder* → `logs`  
- Upload `latest.log` to [mclo.gs](https://mclo.gs)  



{gold}**💾 Backups & Updates**{}  

{yellow}**How do I backup configs?**{}  
1. Main menu → *Config Manager* or `/packcore configmanager`  
2. Export your current config  
3. Save it safely  

> {#275EF5}**Note:**{} Configs are stored in your `config` folder.  

{yellow}**How do I update the modpack?**{}  

{#275EF5}**Modrinth App:**{}  
Click *Update* on the instance page when available.  

{#275EF5}**Prism Launcher:**{}  
1. Select instance → *Edit*  
2. *Modrinth* tab → *Update pack*  

> ⚠️ Custom mods and configs are kept.  
See the *How to Update SkyBlock Enhanced* guide.  

{yellow}**Will updating remove my settings?**{}  
No. Updates keep:  
- Custom configs  
- Added mods  
- Resource packs  
- Worlds  

> {#275EF5}**Tip:**{} Always back up your `config` folder before major updates.  



{gold}**🆘 Getting More Help**{}  

{yellow}**Where can I get support?**{}  
1. Check in-game guides `/packcore guides`  
2. Join the Discord (main menu button)  
3. Read *Start Here*  
4. In support channel, include:  
   - What you were doing  
   - The error  
   - Modpack version  
   - Log file  

{yellow}**Is there a feature showcase?**{}  
Yes. In `/packcore guides` → *Feature Showcase*  

{yellow}**Can I suggest features or report bugs?**{}  
Yes. In Discord:  
- *#suggestions* for ideas  
- *#bug-reports* for issues  

> {#275EF5}**Tip:**{} Include as much detail as possible.  



{gold}**📚 Additional Resources**{}  
- In-Game Guides: `/packcore guides`  
- Config Manager: `/packcore configmanager`  
- Discord: Main menu button  
- Log Upload: [mclo.gs](https://mclo.gs)  
- Modpack Page: [SkyBlock Enhanced – Modern Edition](https://modrinth.com/modpack/skyblock-enhanced-modern-edition)  
