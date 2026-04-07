#!/bin/bash

set -e

# ---------------- CONFIG ----------------
SOURCE="/home/karld/Nextcloud/SkyBlock Enhanced/SkyBlock_Enhanced_Modpack/Default Configs"
ARCHIVE="$SOURCE/archive"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

DEST=(
    "/home/karld/.local/share/ModrinthApp/profiles/SkyBlock Enhanced ME 1440p (6)/packcore/configs"
    "/home/karld/.local/share/ModrinthApp/profiles/SkyBlock Enhanced ME 1440p (4)/packcore/configs"
    "/home/karld/.local/share/ModrinthApp/profiles/SkyBlock Enhanced ME 1440p (3)/packcore/configs"
    "/home/karld/.local/share/ModrinthApp/profiles/SkyBlock Enhanced ME 1440p (8)/packcore/configs"
    "/home/karld/.local/share/ModrinthApp/profiles/SkyBlock Enhanced ME 1440p (5)/packcore/configs"
    "/home/karld/.local/share/ModrinthApp/profiles/SkyBlock Enhanced ME 4k/packcore/configs"
)

OVERWRITE_DEST="/home/karld/Nextcloud/SkyBlock Enhanced/SkyBlock_Enhanced_Modpack/SkyBlock_Enhanced_Modern_Edition_1.21.11/.pakku/overrides/packcore/configs"

# ---------------- FUNCTIONS ----------------

pause() {
    read -p "Press Enter to continue..."
}

# -------- VERSION BUMP --------

bump_version() {
    local pack_files=()

    # Find all pack.json files in the config folders
    while IFS= read -r -d '' f; do
        pack_files+=("$f")
    done < <(find "$SOURCE" -maxdepth 3 -name "pack.json" -not -path "*/archive/*" -print0)

    if [ ${#pack_files[@]} -eq 0 ]; then
        echo "⚠ No pack.json files found. Skipping version bump."
        return
    fi

    # Read version from the first found pack.json
    local sample_file="${pack_files[0]}"
    local current_version
    current_version=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$sample_file")

    if [ -z "$current_version" ]; then
        echo "⚠ Could not read version from pack.json. Skipping version bump."
        return
    fi

    # Parse major.minor.patch
    IFS='.' read -r MAJOR MINOR PATCH <<< "$current_version"

    echo ""
    echo "=================================="
    echo "   Version Bump"
    echo "=================================="
    echo "  Current version: $current_version"
    echo ""
    echo "  1) Patch  →  $MAJOR.$MINOR.$((PATCH + 1))"
    echo "  2) Minor  →  $MAJOR.$((MINOR + 1)).0"
    echo "  3) Major  →  $((MAJOR + 1)).0.0"
    echo "  4) Skip   →  Keep $current_version"
    echo "----------------------------------"
    read -p "Choose an option: " vchoice

    local new_version=""
    case "$vchoice" in
        1) new_version="$MAJOR.$MINOR.$((PATCH + 1))" ;;
        2) new_version="$MAJOR.$((MINOR + 1)).0" ;;
        3) new_version="$((MAJOR + 1)).0.0" ;;
        4)
            echo "  Skipping version bump."
            return
            ;;
        *)
            echo "  Invalid option. Skipping version bump."
            return
            ;;
    esac

    echo ""
    echo "  Bumping version: $current_version → $new_version"
    echo ""

    # Apply new version to all found pack.json files
    for pf in "${pack_files[@]}"; do
        sed -i "s/\"version\"\s*:\s*\"$current_version\"/\"version\": \"$new_version\"/" "$pf"
        echo "  Updated: $pf"
    done

    echo "  ✔ Version bumped to $new_version"
}

create_zips() {
    echo "=== Creating ZIPs ==="

    found=false

    for dir in "$SOURCE"/*/; do
        [ -d "$dir" ] || continue

        folder_name=$(basename "$dir")

        # Skip archive folder
        if [ "$folder_name" = "archive" ]; then
            continue
        fi

        ZIP_NAME="${folder_name}.zip"

        echo "Zipping: $folder_name -> $ZIP_NAME"
        if [ -n "$(ls -A "$SOURCE/$folder_name")" ]; then
            (cd "$SOURCE/$folder_name" && zip -r "$SOURCE/$ZIP_NAME" . >/dev/null)
        else
            echo "Skipping empty folder: $folder_name"
        fi

        found=true
    done

    if [ "$found" = false ]; then
        echo "⚠ No folders found to zip!"
        return 1
    fi
}

archive_old_zips() {
    echo "=== Archiving old ZIPs ==="
    mkdir -p "$ARCHIVE/$TIMESTAMP"

    find "$SOURCE" -maxdepth 1 -name "*.zip" -exec mv {} "$ARCHIVE/$TIMESTAMP/" \;

    echo "Archived to: $ARCHIVE/$TIMESTAMP"
}

deploy_zips() {
    echo "=== Deploying ZIPs ==="
    for target in "${DEST[@]}"; do
        mkdir -p "$target"
        find "$target" -maxdepth 1 -name "*.zip" -delete
        cp "$SOURCE"/*.zip "$target/"
        echo "Deployed to: $target"
    done
}

overwrite_dest() {
    echo "=== Overwriting pakku configs ==="
    mkdir -p "$OVERWRITE_DEST"
    find "$OVERWRITE_DEST" -maxdepth 1 -name "*.zip" -delete
    cp "$SOURCE"/*.zip "$OVERWRITE_DEST/"
}

build_and_deploy() {
    bump_version
    archive_old_zips
    create_zips
    deploy_zips
    overwrite_dest
    echo -e "\n✔ Done!"
}

# -------- INTERACTIVE RESTORE --------

select_archive() {
    mapfile -t archives < <(ls -1 "$ARCHIVE")

    if [ ${#archives[@]} -eq 0 ]; then
        echo "No archives found."
        return 1
    fi

    echo "Select archive:"
    for i in "${!archives[@]}"; do
        echo "$((i+1))) ${archives[$i]}"
    done

    read -p "Enter number: " choice
    ARCH_SELECTED="${archives[$((choice-1))]}"

    if [ -z "$ARCH_SELECTED" ]; then
        echo "Invalid selection."
        return 1
    fi
}

select_zip() {
    mapfile -t zips < <(ls -1 "$ARCHIVE/$ARCH_SELECTED"/*.zip 2>/dev/null | xargs -n1 basename)

    if [ ${#zips[@]} -eq 0 ]; then
        echo "No ZIPs in archive."
        return 1
    fi

    echo "Select ZIP:"
    for i in "${!zips[@]}"; do
        echo "$((i+1))) ${zips[$i]}"
    done

    read -p "Enter number: " choice
    ZIP_SELECTED="${zips[$((choice-1))]}"

    if [ -z "$ZIP_SELECTED" ]; then
        echo "Invalid selection."
        return 1
    fi
}

restore_zip() {
    echo "=== Restore ZIP ==="

    select_archive || return
    select_zip || return

    cp "$ARCHIVE/$ARCH_SELECTED/$ZIP_SELECTED" "$SOURCE/"
    echo "✔ Restored: $ZIP_SELECTED"
}

# -------- CONFIG CHANGELOG --------

ensure_config_changelog_file() {
    local changelog_file="$SOURCE/CONFIG_CHANGELOG.md"

    if [[ ! -f "$changelog_file" ]]; then
        cat > "$changelog_file" << 'EOF'
# ⚙ Config Changes

<!--
This file is included in the modpack release notes when the config version increases.
Edit this before running the script, then it will be automatically included.
Replace this text with your config changes for this release.
-->

- Example config change 1
- Example config change 2
EOF
        echo "  ✓ Created: $changelog_file"
    fi
}

create_config_changelog_prompt() {
    local current_config_ver="$1"
    local previous_config_ver="$2"

    echo ""
    echo "=================================="
    echo "   Config Changelog"
    echo "=================================="

    if [[ "$current_config_ver" != "$previous_config_ver" ]] && [[ "$previous_config_ver" != "none" ]]; then
        echo "  ℹ Config version changed: $previous_config_ver → $current_config_ver"
        echo ""
        echo "  A CONFIG_CHANGELOG.md file will be included in the modpack release."
        echo "  Edit it now in your text editor, then come back here."
        echo ""
        read -p "Press Enter when you're done editing CONFIG_CHANGELOG.md..."
    elif [[ "$previous_config_ver" == "none" ]]; then
        echo "  ⚠ First release or no previous config version found"
        echo "  CONFIG_CHANGELOG.md will NOT be included in this release."
    else
        echo "  ℹ Config version unchanged ($current_config_ver)"
        echo "  CONFIG_CHANGELOG.md will NOT be included in the modpack release."
    fi
}

update_build_and_deploy() {
    bump_version

    # Get current config version from first found pack.json
    local sample_file
    sample_file=$(find "$SOURCE" -maxdepth 3 -name "pack.json" -not -path "*/archive/*" 2>/dev/null | head -1)

    local current_cfg_ver="none"
    if [[ -n "$sample_file" ]]; then
        current_cfg_ver=$(jq -r '.version // empty' "$sample_file" 2>/dev/null || echo "none")
    fi

    create_config_changelog_prompt "$current_cfg_ver" "none"

    archive_old_zips
    create_zips
    deploy_zips
    overwrite_dest
    echo -e "\n✔ Done!"
}

# ---------------- MENU ----------------

menu() {
    clear
    echo "=================================="
    echo "   SkyBlock Config Manager"
    echo "=================================="
    echo "1) Build + Deploy (normal)"
    echo "2) Restore ZIP from archive"
    echo "3) Exit"
    echo "----------------------------------"

    read -p "Choose an option: " choice

    case "$choice" in
        1)
            ensure_config_changelog_file
            update_build_and_deploy
            pause
            ;;
        2)
            restore_zip
            pause
            ;;
        3)
            exit 0
            ;;
        *)
            echo "Invalid option"
            pause
            ;;
    esac
}

menu
