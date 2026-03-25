#!/bin/sh

set -eu

run() {
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    me=$(basename "$0")

    cur_version=$(cat "$script_dir/version.yml" | sed -n 's/^version\s*:\s*//p')
    download_from=$(cat "$script_dir/version.yml" | sed -n 's/^download_from\s*:\s*//p')
    if [ -z "$download_from" ]; then
        download_from="direct"
    fi

    download_url=""
    if [ "$download_from" = "direct" ]; then
        download_url=$(cat "$script_dir/version.yml" | sed -n 's/^direct_url\s*:\s*//p')
        if [ -z "$download_url" ]; then
            echo "Couldn't find direct_url in '$script_dir/version.yml'" >&2
            exit 1
        fi
    elif [ "$download_from" = "gdrive" ]; then
        gdoc_fileid=$(cat "$script_dir/version.yml" | sed -n 's/^gdoc_fileid\s*:\s*//p')
        if [ -z "$gdoc_fileid" ]; then
            echo "Couldn't find gdoc_fileid in '$script_dir/version.yml'" >&2
            exit 1
        fi
        download_url="https://drive.usercontent.google.com/download?id=${gdoc_fileid}&confirm=t"
    elif [ "$download_from" = "mega" ]; then
        download_url=$(cat "$script_dir/version.yml" | sed -n 's/^mega_url\s*:\s*//p')
        if [ -z "$download_url" ]; then
            echo "Couldn't find mega_url in '$script_dir/version.yml'" >&2
            exit 1
        fi
    elif [ "$download_from" = "local" ]; then
        download_url=$(cat "$script_dir/version.yml" | sed -n 's/^local_path\s*:\s*//p')
        if [ -z "$download_url" ]; then
            echo "Couldn't find local_path in '$script_dir/version.yml'" >&2
            exit 1
        fi
        if [ ! -f "$download_url" ]; then
            echo "Local file '$download_url' not found." >&2
            exit 1
        fi
    else
        echo "Unsupported download_from value '$download_from' in '$script_dir/version.yml'" >&2
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
            --update-continue)
                mode="update-continue"
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
    required_commands="curl bsdtar cpio wine sed unzip openssl"
    required_commands=$(echo "$required_commands" | tr ' ' "\n")
    missing_commands=""
    for cmd in $required_commands; do
        if ! command -v "$cmd" >/dev/null; then
            missing_commands="$missing_commands $cmd"
        fi
    done

    # if any missing commands
    if [ -n "$missing_commands" ]; then
        echo -e "Missing required commands:\n $missing_commands" >&2

        # Suggest install commands based on package manager
        if command -v apt-get >/dev/null; then
            # replace bsdtar with libarchive-tools
            missing_commands=$(echo "$missing_commands" | sed 's/bsdtar/libarchive-tools/')
            echo -e "Try installing them with:\n  sudo apt-get install$missing_commands" >&2
        elif command -v pacman >/dev/null; then
            echo -e "Try installing them with:\n  sudo pacman -S$missing_commands" >&2
        elif command -v dnf >/dev/null; then
            echo -e "Try installing them with:\n  sudo dnf install$missing_commands" >&2
        elif command -v yum >/dev/null; then
            echo -e "Try installing them with:\n  sudo yum install$missing_commands" >&2
        fi

        exit 1
    fi

    if command -v wine32 >/dev/null; then
        wine_exec="wine32"
        wine_arch="win32"
    else
        wine_exec="wine"
        wine_arch="wow64"

        if ! command -v "winetricks" >/dev/null; then
            echo "Warning: 'winetricks' command not found. In Wine's wow64 mode this script needs winetricks to install dxvk" >&2
            exit 1
        fi
    fi

    rimraf() {
        if [ ! -d "$1" ]; then
            return 0
        fi

        prompt=${2:-"Will remove '$1'. Continue?"}
        read -p "$prompt [Y/n] " REPLY
        if expr "${REPLY:-y}" : '^[Yy]$' 1>/dev/null 2>/dev/null; then
            rm -rf "$1"
            return 0
        fi

        return 1
    }

    read_filepath() {
        # on bash I can use read -e to enable filepath completions.
        # check if we're using bash
        REPLY=""
        if [ -n "${BASH_VERSION:-}" ]; then
            read -e -p "$1" REPLY
        else
            read -p "$1" REPLY
        fi
        echo $REPLY
    }

    if [ $mode = "update" ]; then
        # backup current directory aside into .update so we can avoid updating it in-place.
        update_dir="$script_dir/.update"
        update_extracted_to="$update_dir"
        rimraf "$update_dir" "Removing previous update directory at '$update_dir'. Continue?"
        mkdir -p "$update_dir"

        # if theres a .git folder its a git repo
        if [ -d "$script_dir/.git" ]; then
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
                echo "Use 'git status' to see whats up." >&2
                rm -rf "$update_dir"
                exit 1
            fi

            if ! git -C "$update_dir" fetch origin main; then
                echo "Failed to fetch updates. Try running \"git fetch origin main\" manually." >&2
                rm -rf "$update_dir"
                exit 1
            fi

            local_head=$(git -C "$update_dir" rev-parse HEAD)
            remote_head=$(git -C "$update_dir" rev-parse FETCH_HEAD)
            if [ "$local_head" != "$remote_head" ]; then
                if ! git -C "$update_dir" merge FETCH_HEAD --ff-only; then
                    echo "Failed to update. You might not be on 'main' branch or your commit history has diverged." >&2
                    echo "You can try a potentially destructive 'git reset --hard FETCH_HEAD'. Use at your own risk." >&2
                    rm -rf "$update_dir"
                    exit 1
                fi
            fi

            new_commit=$(git -C "$update_dir" rev-parse HEAD)
            if [ "$current_commit" = "$new_commit" ]; then
                echo "Already up-to-date."
                rm -rf "$update_dir"

                . "$script_dir/maplelegends-install.sh" --update-continue
                exit $?
            fi
        else
            zip_download_from="https://github.com/Yareeeef/MapleLegends-installer/archive/main.zip"
            zip_download_to="$script_dir/.update.zip"
            rm -f "$zip_download_to" || true
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
        
        . "$script_dir/maplelegends-install.sh" --update-continue
        exit $?
    elif [ $mode = "update-continue" ]; then
        install_dir=$(cat "$script_dir/current_install.txt" 2>/dev/null || echo '')
        if [ -z "$install_dir" ]; then
            echo "No previous installation found. Please re-install." >&2
        elif [ ! -d "$install_dir" ]; then
            echo "Previous installation directory not found. Please re-install." >&2
        else
            # check if we have write permission on $install_dir
            if ! touch "$install_dir/.test" 2>/dev/null; then
                echo "No write permission on previous installation directory. Please re-install in a new location." >&2
                install_dir=""
            else
                rm -f "$install_dir/.test" || true
                read -p "Will update existing installation '$install_dir'. Is this correct? [Y/n] " REPLY
                if ! expr "${REPLY:-y}" : '^[Yy]$' 1>/dev/null 2>/dev/null; then
                    install_dir=""
                fi

                echo -e "\nIMPORTANT: I need to first remove the existing installation in '$install_dir'."
                rimraf "$install_dir" "The entire directory will be removed. Continue?"
            fi
        fi
    else
        install_dir="${1:-}"
    fi

    while true; do
        if [ -z "$install_dir" ]; then
            install_dir=$(read_filepath "Enter the directory where you want to install MapleLegends: ")
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

        # if should skip prompt (not update-continue mode)
        if [ $mode != "update-continue" ]; then
            read -p "Will install to '$install_dir'. Is this correct? [Y/n] " REPLY
            if ! expr "${REPLY:-y}" : '^[Yy]$' 1>/dev/null 2>/dev/null; then
                install_dir=""
                continue
            fi
        fi

        if [ -d "$install_dir" ]; then
            echo "Directory already exists. Aborting." >&2
            exit 1
        fi
        break
    done
    # echo "$install_dir"

    echo "$install_dir" > "$script_dir/current_install.txt"
    mkdir -p "$install_dir"
    mytmp="$install_dir/.tmp-install"
    mkdir -p "$mytmp"

    echo "Downloading game client..."
    download_to="$mytmp/MapleLegends.pkg"

    if [ "$download_from" = "mega" ]; then
        set -x
        $script_dir/megafetch.sh "$download_url" > "$mytmp/mega-download"

        # mega-download will have 4 lines:
        # 1. download url
        download_url=$(sed -n '1p' "$mytmp/mega-download")
        # 2. file name
        file_name=$(sed -n '2p' "$mytmp/mega-download")
        # 3. key
        key=$(sed -n '3p' "$mytmp/mega-download")
        # 4. iv
        iv=$(sed -n '4p' "$mytmp/mega-download")

        if [ -z "$download_url" ] || [ -z "$file_name" ] || [ -z "$key" ] || [ -z "$iv" ]; then
            echo "Failed to parse download information from mega." >&2
            exit 1
        fi

        curl -L -o "$download_to" "$download_url"
        cat "$download_to" | openssl enc -d -aes-128-ctr -K $key -iv $iv > "${download_to}.new"
        mv -f "${download_to}.new" "$download_to"
        set +x
    elif [ "$download_from" = "local" ]; then
        cp -av "$download_url" "$download_to"
    else
        curl -L -o "$download_to" "$download_url"
    fi

    # Some sanity checks - if the downloaded file is too small (lets say less than 1GB), its probably an error.
    downloaded_size=$(stat -c %s "$download_to")
    if [ $downloaded_size -lt 1000000000 ]; then
        # Sometimes downloads are rate limited by Google Drive. Try detecting this.
        if head -c 50000 ../MapleLegends/.tmp-install/MapleLegends.pkg | grep -q "Too many users have viewed
 or downloaded this file recently"; then
            echo "Download failed. Google Drive rate limit reached. Try again later." >&2
        else
            echo "Downloaded file is too small. Likely something went wrong with the download." >&2
        fi

        rimraf "$install_dir" "There are left over files in '$install_dir'. Remove them?"
        exit 1
    fi

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
    WINEPREFIX="$winedir" WINEARCH=$wine_arch $wine_exec winecfg -v win98

    if [ "$wine_arch" = "wow64" ]; then
        echo "Installing dxvk via winetricks..."
        WINEPREFIX="$winedir" winetricks -q dxvk
    fi

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

    rimraf "$mytmp" "Remove temporary files in '$mytmp'?"

    echo "Happy Mapling!"
}

run "$@"