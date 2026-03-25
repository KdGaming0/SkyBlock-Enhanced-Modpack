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
            build_and_deploy
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
