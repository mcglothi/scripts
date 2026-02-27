#!/bin/bash
set -euo pipefail

# === BTRFS SNAPSHOT ===
echo '>>> Creating pre-upgrade Btrfs snapshot...'
SNAPSHOT_DIR='/.snapshots'
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')
SNAP_NAME="autoupdate-$TIMESTAMP"
SNAP_PATH="$SNAPSHOT_DIR/$SNAP_NAME"

if [[ -d "$SNAPSHOT_DIR" ]]; then
  echo ">>> Creating snapshot at: $SNAP_PATH"
  if sudo btrfs subvolume snapshot -r / "$SNAP_PATH"; then
    echo '>>> Snapshot created successfully.'
  else
    echo '>>> FAILED to create snapshot! Aborting for safety.'
    exit 1
  fi
else
  echo ">>> WARNING: Snapshot directory $SNAPSHOT_DIR does not exist. Skipping Btrfs snapshot."
fi

# Prune old autoupdate snapshots (keep last 10)
echo '>>> Pruning old autoupdate snapshots...'
find "$SNAPSHOT_DIR" -maxdepth 1 -type d -name "autoupdate-*" | sort | head -n -10 | while read -r old_snap; do
  echo ">>> Deleting old snapshot: $old_snap"
  sudo btrfs subvolume delete "$old_snap"
done

# === MIRROR REFRESH ===
echo '>>> Refreshing mirrorlist...'
if ! command -v reflector &>/dev/null; then
  sudo pacman -Sy --noconfirm reflector
fi

sudo reflector   --country 'United States'   --age 12   --protocol https   --sort rate   --threads 10   --fastest 10   --save /etc/pacman.d/mirrorlist

# Ensure [community] repo is removed (deprecated and merged into [extra])
if grep -q "^\[community\]" /etc/pacman.conf; then
    echo '>>> Removing deprecated [community] repo from pacman.conf...'
    sudo sed -i '/^\[community\]/,/^$/d' /etc/pacman.conf
fi

echo '>>> Syncing updated mirrorlist...'
sudo pacman -Syy

# === KEYRING + PACMAN UPDATE ===
echo '>>> Updating archlinux-keyring and pacman...'
sudo pacman -Sy --noconfirm archlinux-keyring pacman

# === ORPHAN CLEANUP (pre-upgrade) ===
echo '>>> Checking for broken dependencies (pre-clean)...'
orphans_pre=$(pacman -Qdtq || true)
if [[ -n "$orphans_pre" ]]; then
  sudo pacman -Rns --noconfirm $orphans_pre
fi

# === SYSTEM UPGRADE ATTEMPT ===
echo '>>> Starting full system upgrade...'
if ! sudo pacman -Syu --noconfirm; then
  echo '>>> Initial upgrade failed. Checking for known issues...'

  # gpgme/ostree conflict fix
  if pacman -Qi ostree &>/dev/null; then
    echo '>>> Removing ostree to resolve gpgme conflict'
    sudo pacman -Rdd --noconfirm ostree
  fi

  # Check for package conflicts
  echo '>>> Attempting to detect and resolve conflicts...'
  upgrade_output=$(mktemp)
  sudo pacman -Syu --noconfirm &> "$upgrade_output" || true
  conflict_lines=$(grep -oP '^:: [^ ]+ and [^ ]+ are in conflict' "$upgrade_output")

  if [[ -n "$conflict_lines" ]]; then
    echo '>>> Conflicting package pairs detected:'
    echo "$conflict_lines"

    echo "$conflict_lines" | while read -r line; do
      pkg_to_remove=$(echo "$line" | awk '{print $4}' | sed 's/-[0-9][^ ]*$//')
      
      # PROTECTION: Do NOT remove nvidia drivers automatically
      if [[ "$pkg_to_remove" == *nvidia* ]]; then
        echo ">>> PROTECTION: Refusing to automatically remove NVIDIA package: $pkg_to_remove"
        echo '>>> This package is likely required for your legacy 1080ti support.'
        echo '>>> Manual intervention required to resolve this conflict.'
        rm -f "$upgrade_output"
        exit 1
      fi

      if pacman -Q "$pkg_to_remove" &>/dev/null; then
        echo ">>> Removing conflicting package: $pkg_to_remove"
        sudo pacman -Rdd --noconfirm "$pkg_to_remove"
      else
        echo ">>> Skipping: $pkg_to_remove is not installed"
      fi
    done
  fi
  rm -f "$upgrade_output"

  echo '>>> Retrying upgrade...'
  if ! sudo pacman -Syu --noconfirm; then
    echo '>>> Checking for NVIDIA firmware file conflicts...'

    # Check for unowned files in /usr/lib/firmware/nvidia
    if find /usr/lib/firmware/nvidia -type f | while read -r f; do ! pacman -Qo "$f" &>/dev/null && echo "$f"; done | grep -q .; then
        # Auto-clean known problematic NVIDIA firmware dirs if unowned
        echo '>>> Cleaning up unowned NVIDIA firmware paths...'
        for dir in /usr/lib/firmware/nvidia/ad10{3..7}; do
          if [[ -d "$dir" ]] && ! pacman -Qo "$dir" &>/dev/null; then
            echo ">>> Removing unowned firmware directory: $dir"
            sudo rm -rf "$dir"
          fi
        done

        echo '>>> Unowned firmware files found — retrying with targeted overwrite...'
        if sudo pacman -Syu --overwrite '/usr/lib/firmware/nvidia/*' --noconfirm; then
            echo '>>> Upgrade completed with targeted firmware overwrite.'
        else
            echo '>>> Targeted overwrite failed. Trying full overwrite fallback...'
            sudo pacman -Syu --overwrite '*' --noconfirm || {
                echo '>>> Upgrade failed even after full overwrite. Manual intervention required.'
                exit 1
            }
        fi
    else
        echo '>>> No unowned NVIDIA firmware files detected. Trying full overwrite fallback...'
        sudo pacman -Syu --overwrite '*' --noconfirm || {
            echo '>>> Upgrade failed even after full overwrite. Manual intervention required.'
            exit 1
        }
    fi
  fi
else
  echo '>>> Upgrade completed successfully on first attempt.'
fi

# === FINAL CLEANUP ===
echo '>>> Final orphan cleanup...'
orphans_post=$(pacman -Qdtq || true)
if [[ -n "$orphans_post" ]]; then
  sudo pacman -Rns --noconfirm $orphans_post
else
  echo '>>> No orphans found.'
fi

echo '>>> Cleaning package cache (keeping last 3)...'
if command -v paccache &>/dev/null; then
    sudo paccache -r
else
    echo '>>> Skip: paccache not found.'
fi

# === REBOOT CHECK ===
echo '>>> Checking if reboot is required...'
if [[ ! -d "/usr/lib/modules/$(uname -r)" ]]; then
    echo '>>> WARNING: Running kernel modules not found! A kernel update likely occurred.'
    echo '>>> A REBOOT IS REQUIRED to use the new kernel and modules.'
elif [[ -f /var/run/reboot-required ]]; then
    echo '>>> A reboot is required (detected /var/run/reboot-required).'
else
    echo '>>> No reboot seems to be required.'
fi

echo '>>> All done. System is up to date.'
