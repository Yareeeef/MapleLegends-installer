#!/bin/sh

set -eu

run() {
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    me=$(basename "$0")

    cur_version=$(cat "$script_dir/version.yml" | sed -n 's/^version\s*:\s*//p')
    gdoc_fileid=$(cat "$script_dir/version.yml" | sed -n 's/^gdoc_fileid\s*:\s*//p')
    if [ -z "$gdoc_fileid" ]; then
        echo "Couldn't find gdoc_fileid in '$script_dir/version.yml'" >&2
        exit 1
    fi

    # validate arguments
    if [ $# -gt 1 ] ; then
        echo "$me: too many arguments.
    Try '$me --help' for more information."
        exit 1
    fi

    mode="install"
    if [ $# -eq 1 ]; then
        case "$1" in
            -h | --help)
                echo "Usage: $me [INSTALL_DIR]
    Install MapleLegends to INSTALL_DIR. Prompts for directory if not provided."
                exit 0
                ;;
            --update)
                mode="update"
                ;;
            # starts with '-' (looks like an option)
            -*)
                echo "$me: unrecognized option '$1'
    Try '$me --help' for more information."
                exit 1
                ;;
        esac
    fi

    # check for required commands
    required_commands="curl bsdtar cpio wine sed unzip"
    required_commands=$(echo "$required_commands" | tr ' ' "\n")
    missing_commands=""
    for cmd in $required_commands; do
        if ! command -v "$cmd" >/dev/null; then
            missing_commands="$missing_commands $cmd"
        fi
    done

    # if any missing commands
    if [ -n "$missing_commands" ]; then
        echo "Missing required commands:\n $missing_commands" >&2

        # Suggest install commands based on package manager
        if command -v apt-get >/dev/null; then
            # replace bsdtar with libarchive-tools
            missing_commands=$(echo "$missing_commands" | sed 's/bsdtar/libarchive-tools/')
            echo "Try installing them with:\n  sudo apt-get install$missing_commands" >&2
        elif command -v pacman >/dev/null; then
            echo "Try installing them with:\n  sudo pacman -S$missing_commands" >&2
        elif command -v dnf >/dev/null; then
            echo "Try installing them with:\n  sudo dnf install$missing_commands" >&2
        elif command -v yum >/dev/null; then
            echo "Try installing them with:\n  sudo yum install$missing_commands" >&2
        fi

        exit 1
    fi

    if [ $mode = "update" ]; then
        # backup current directory aside into .update so we can avoid updating it in-place.
        update_dir="$script_dir/.update"
        update_extracted_to="$update_dir"
        rm -rf "$update_dir"
        mkdir -p "$update_dir"
            
        # if theres a .git folder its a git repo
        if [ -d "$script_dir/.gitt" ]; then
            if ! command -v git >/dev/null; then
                echo "This looks like a git repository but 'git' is not installed." >&2
                echo "Install git and try again." >&2
                exit 1
            fi

            current_commit=$(git -C "$script_dir" rev-parse HEAD)

            # note, copying aside excluding .update so we dont recursively copy
            # into ourselves.
            find "$script_dir" -mindepth 1 -maxdepth 1 -not -name ".update" -exec cp -a {} .update \; 1>/dev/null
            # check if the directory is clean (no untracked and no modified files)
            if ! git -C "$script_dir" diff --exit-code --quiet \
                || ! git -C "$script_dir" diff --exit-code --cached --quiet; then
                echo "Cheeky cheeky! Can't update because you have some local changes." >&2
                rm -rf "$update_dir"
                exit 1
            fi
            # note, use --ff-only to avoid implicitly creating merge commits,
            # rebasing or overwriting local changes.
            if ! git -C "$update_dir" pull origin main --ff-only; then
                echo "Failed to update. Try running \"git pull origin main --ff-only\" manually." >&2
                rm -rf "$update_dir"
                exit 1
            fi

            new_commit=$(git -C "$script_dir" rev-parse HEAD)
            if [ "$current_commit" = "$new_commit" ]; then
                echo "Already up-to-date."
                rm -rf "$update_dir"
                exit 0
            fi
        else
            zip_download_from="https://github.com/Yareeeef/MapleLegends-installer/archive/main.zip"
            zip_download_to="$script_dir/.update.zip"
            curl -L -o "$zip_download_to" "$zip_download_from"

            unzip "$zip_download_to" -d "$update_dir"
            update_extracted_to="$update_dir/MapleLegends-installer-main"
            rm -f "$zip_download_to"
        fi

        # copy back from .update to script directory
        # Note: cp -f required because some files may not be writable.
        find "$update_extracted_to" -mindepth 1 -maxdepth 1 -exec cp -af {} "$script_dir/" \; 1>/dev/null
        rm -rf "$update_dir"
        
        new_version=$(cat "$script_dir/version.yml" | sed -n 's/^version\s*:\s*//p')
        echo "Updated to version '${new_version}'."
        
        install_dir=$(cat "$script_dir/current_install.txt" 2>/dev/null || echo '')
        if [ -z "$install_dir" ]; then
            echo "No previous installation found. Please re-install." >&2
        elif [ ! -d "$install_dir" ]; then
            echo "Previous installation directory not found. Please re-install." >&2
        else
            # check if we have write permission on $install_dir
            if ! touch "$install_dir/.test" 2>/dev/null; then
                echo "No write permission on previous installation directory. Please re-install." >&2
                install_dir=""
            fi
            rm -f "$install_dir/.test" || true
        fi
    else
        install_dir="${1:-}"
    fi

    while true; do
        if [ -z "$install_dir" ]; then
            read -p "Enter the directory where you want to install MapleLegends: " install_dir
        fi

        # if not absolute path (doesn't start with /)
        # posix compatible
        if ! expr "$install_dir" : "^/" 1>/dev/null 2>/dev/null; then
            install_dir="$(pwd)/$install_dir"
        fi

        # normalize path
        install_dir=$(readlink -m "$install_dir" 2>/dev/null || echo '')
        if [ -z "$install_dir" ]; then
            echo "Couldn't resolve path. Try with an absolute path." >&2
            install_dir=""
            continue
        fi

        read -p "Will install to '$install_dir'. Is this correct? [Y/n] " REPLY
        if ! expr "${REPLY:-y}" : '^[Yy]$' 1>/dev/null 2>/dev/null; then
            install_dir=""
            continue
        fi

        if [ -d "$install_dir" ]; then
            echo "Directory already exists. Aborting." >&2
            # exit 1
        fi
        break
    done
    # echo "$install_dir"

    echo "$install_dir" > "$script_dir/current_install.txt"
    mkdir -p "$install_dir"
    mytmp="$install_dir/.tmp-install"
    mkdir -p "$mytmp"

    echo "Downloading game client..."
    download_url="https://drive.usercontent.google.com/download?id=${gdoc_fileid}&confirm=t"
    download_to="$mytmp/MapleLegends.pkg"
    curl -L -o "$download_to" "$download_url"

    echo "Extracting game client..."
    extract_to="$mytmp/extracted"
    mkdir -p "$extract_to"
    bsdtar -xvf "$download_to" -C "$extract_to"
    payload_dir="$mytmp/payload"
    mkdir -p "$payload_dir"
    cat "$extract_to/MapleLegends.pkg/Payload" | gunzip -dc | cpio -i -D "$payload_dir"
    game_dir="$install_dir/Game"
    mkdir -p "$game_dir"
    mv "$payload_dir/MapleLegends.app/drive_c/MapleLegends/"* "$game_dir"

    echo "Preparing Wine prefix..."
    winedir="$install_dir/.wine"
    WINEPREFIX="$winedir" WINEARCH=win32 wine winecfg -v win98

    echo "Patching..."
    cp -vf "$script_dir/ws2_32.dll" "$winedir/drive_c/windows/system32/ws2_32.dll"
    cp -vf "$script_dir/ws2help.dll" "$winedir/drive_c/windows/system32/ws2help.dll"
    cp -vf "$script_dir/maplestory-icon.png" "$install_dir/maplestory-icon.png"
    cp -vf "$script_dir/run.sh-template" "$install_dir/run.sh"
    chmod +x "$install_dir/run.sh"

    read -p "Would you like to make a desktop entry? [Y/n] " REPLY
    if expr "${REPLY:-y}" : '^[Yy]$' 1>/dev/null 2>/dev/null; then
        desktop_entry=""
        if [[ -n "${XDG_DATA_HOME:-}" ]]; then
            desktop_entry="${XDG_DATA_HOME%/}/applications/maplelegends.desktop"
        else
            desktop_entry="$HOME/.local/share/applications/maplelegends.desktop"
        fi

        sed -e "s~{{ INSTALL_DIR }}~${install_dir}~g" \
            < "$script_dir/maplelegends.desktop-template" \
            > "$desktop_entry"
    fi

    echo "Cleaning up..."
    rm -rf "$mytmp"
}

run "$@"