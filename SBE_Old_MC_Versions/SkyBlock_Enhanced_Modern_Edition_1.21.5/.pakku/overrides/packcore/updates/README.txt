═══════════════════════════════════════════════════════════
PackCore Automatic Config Updates Folder
═══════════════════════════════════════════════════════════

📦 What is this folder?

This folder is used for automatic config updates when you
release a modpack update. It allows you to ship config files
for new mods without overwriting users' existing configs.

═══════════════════════════════════════════════════════════
🔧 How to use (for modpack developers):
═══════════════════════════════════════════════════════════

1. Create your config update zip file
   - Include ONLY the new/changed config files
   - Example: config/newmod/settings.json

2. Create update_manifest.json with this structure:
   {
     "updateId": "1.2.0_newmod",
     "version": "1.2.0",
     "description": "Added NewMod configuration",
     "configFileName": "newmod_config.zip",
     "createBackup": true,
     "affectedMods": ["newmod"]
   }

3. Place both files in this folder for distribution

4. When users update the modpack, configs apply automatically

═══════════════════════════════════════════════════════════
📋 Update Manifest Fields:
═══════════════════════════════════════════════════════════

updateId:       Unique identifier (prevents re-applying)
version:        Modpack version (e.g., "1.2.0")
description:    What this update contains
configFileName: Name of the zip file to extract
createBackup:   Whether to backup before applying
affectedMods:   List of affected mod names

═══════════════════════════════════════════════════════════
⚠️ Important Notes:
═══════════════════════════════════════════════════════════

- Each updateId can only be applied once
- Applied updates are moved to the 'applied' subfolder
- Users on fresh installs get full configs (updates skipped)
- Only existing users will receive these updates

═══════════════════════════════════════════════════════════
📂 Folder Structure After Updates:
═══════════════════════════════════════════════════════════

packcore/updates/
├── update_manifest.json       ← Pending update
├── newmod_config.zip          ← Pending update
├── README.txt                 ← This file
└── applied/                   ← Archive of applied updates
    └── 1.2.0_newmod_20250101_120000/
        ├── update_manifest.json
        └── newmod_config.zip

═══════════════════════════════════════════════════════════
