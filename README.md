![maplelegends_installer_logo](https://github.com/user-attachments/assets/42a7a201-8732-45cf-bfcb-0ce4c96cdbff)
![GitHub License](https://img.shields.io/github/license/Yareeeef/MapleLegends-installer) ![Game Version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2FYareeeef%2FMapleLegends-installer%2Fmain%2Fversion.yml&query=%24.version&label=game%20version) ![Made with Love](https://img.shields.io/badge/made_with-%E2%9D%A4%EF%B8%8F-red)


Install MapleLegends on Linux. Play some nostalgic MapleStory!

```sh
# Install
git clone https://github.com/Yareeeef/MapleLegends-installer
cd MapleLegends-installer
./maplelegends-install.sh /path/to/MapleLegends

# Play
/path/to/MapleLegends/run.sh

# Update
cd MapleLegends-installer
./maplelegends-install.sh --update
```

# Prerequisites

## Get Dependencies

The script makes use of a few command line tools that may not be installed by default:

- __Ubuntu/Debian:__ `sudo apt-get install curl libarchive-tools cpio gzip`
- __Fedora:__ `dnf install curl bsdtar cpio gzip`
- __(untested) Arch Linux:__ `sudo pacman -Syu curl bsdtar cpio gzip`

## Get Wine

You can install wine through your package manager or follow the instructions on the [official website](https://wiki.winehq.org/Download).

> [!NOTE]
> You may be able to use Lutris or PlayOnLinux's Wine versions, but I haven't tested it. The script expects the `wine` executable to be in your `PATH`.

# Install

__1. Clone the repository:__
```sh
git clone https://github.com/Yareeeef/MapleLegends-installer
```
(or download and extract [the ZIP](https://github.com/Yareeeef/MapleLegends-installer/archive/refs/heads/main.zip))

__2. Run the script:__
```sh
cd MapleLegends-installer
./maplelegends-install.sh
```
It'll ask you where to install MapleLegends and whether to create a desktop shortcut.

# Play

If you chose to create a desktop shortcut you can run the game just like any other application.

Otherwise, you can run it like so:
```sh
/path/to/install_dir/run.sh
```

# Update

When the game updates, you need to update your installation.

```sh
cd MapleLegends-installer
./maplelegends-install.sh --update
```

It'll attempt to detect the current installation. If it can't, it'll ask you where to install the new version.

# Contributing

I made my very first online friends on old school MapleStory, and MapleLegends community is very warm and welcoming too! I hope this project helps more people enjoy the game.

That said, I am juggling between some personal stuff and a full time job, so I may not be the fastest to update the script when a new version of MapleLegends is released.

It should be super easy to DIY tho. Assuming nothing changes with how the game itself is packaged, you can update the script like so:
1. Go to https://forum.maplelegends.com/index.php?threads/new-full-version-july-14-2024.23264/ and find the url for the MAC Wineskin version.
2. The url looks something like https://drive.google.com/file/d/1O61pmNRqaSBbFo8QGJFIPBqOagtX5E8x/view?usp=share_link. Copy the random letters part between `d/` and `/view` (in this case `1O61pmNRqaSBbFo8QGJFIPBqOagtX5E8x`)
3. Put it in `version.yml` in the `gdoc_fileid` field.
4. Also in `version.yml` clear out the `download_url` field.
5. (Optional) While your'e in `version.yml`, update the `version` field to the new version name.

If you have any suggestions or improvements, feel free to open an issue or a pull request!
