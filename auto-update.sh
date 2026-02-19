#!/bin/bash
set -euo pipefail

# === BTRFS SNAPSHOT ===
echo ">>> Creating pre-upgrade Btrfs snapshot..."
SNAPSHOT_DIR="/.snapshots"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
SNAP_NAME="autoupdate-$TIMESTAMP"
SNAP_PATH="$SNAPSHOT_DIR/$SNAP_NAME"

if [[ -d "$SNAPSHOT_DIR" ]]; then
  echo ">>> Creating snapshot at: $SNAP_PATH"
  sudo btrfs subvolume snapshot -r / "$SNAP_PATH"
else
  echo ">>> WARNING: Snapshot directory $SNAPSHOT_DIR does not exist. Skipping Btrfs snapshot."
fi

# Optional: prune old autoupdate snapshots
echo ">>> Pruning old autoupdate snapshots..."
find "$SNAPSHOT_DIR" -maxdepth 1 -type d -name "autoupdate-*" | sort | head -n -5 | while read -r old_snap; do
  echo ">>> Deleting old snapshot: $old_snap"
  sudo btrfs subvolume delete "$old_snap"
done

# === MIRROR REFRESH ===
echo ">>> Refreshing mirrorlist and removing [community] repo if needed..."
if ! command -v reflector &>/dev/null; then
  sudo pacman -Sy --noconfirm reflector
fi

sudo reflector \
  --country 'United States' \
  --age 12 \
  --protocol https \
  --sort rate \
  --threads 10 \
  --fastest 10 \
  --save /etc/pacman.d/mirrorlist

sudo sed -i '/^\[community\]/,/^$/d' /etc/pacman.conf

echo ">>> Syncing updated mirrorlist..."
sudo pacman -Syy

# === KEYRING + PACMAN UPDATE ===
echo ">>> Updating archlinux-keyring and pacman..."
sudo pacman -Sy --noconfirm archlinux-keyring pacman

# === ORPHAN CLEANUP (pre-upgrade) ===
echo ">>> Checking for broken dependencies (pre-clean)"
if pacman -Qdtq &>/dev/null; then
  sudo pacman -Rns --noconfirm $(pacman -Qdtq)
fi

# === SYSTEM UPGRADE ATTEMPT ===
echo ">>> Starting full system upgrade..."
if ! sudo pacman -Syu --noconfirm; then
  echo ">>> Initial upgrade failed. Checking for known issues..."

  # gpgme/ostree conflict fix
  if pacman -Qi ostree &>/dev/null; then
    echo ">>> Removing ostree to resolve gpgme conflict"
    sudo pacman -Rdd --noconfirm ostree
  fi

  # Check for package conflicts
  echo ">>> Attempting to detect and remove conflicting packages..."
  upgrade_output=$(mktemp)
  sudo pacman -Syu --noconfirm &> "$upgrade_output" || true
  conflict_lines=$(grep -oP '^:: [^ ]+ and [^ ]+ are in conflict' "$upgrade_output")

  if [[ -n "$conflict_lines" ]]; then
    echo ">>> Conflicting package pairs detected:"
    echo "$conflict_lines"

    echo "$conflict_lines" | while read -r line; do
      pkg_to_remove=$(echo "$line" | awk '{print $4}' | sed 's/-[0-9][^ ]*$//')
      if pacman -Q "$pkg_to_remove" &>/dev/null; then
        echo ">>> Removing conflicting package: $pkg_to_remove"
        sudo pacman -Rdd --noconfirm "$pkg_to_remove"
      else
        echo ">>> Skipping: $pkg_to_remove is not installed"
      fi
    done
  fi
  rm -f "$upgrade_output"

  echo ">>> Retrying upgrade..."
  if ! sudo pacman -Syu --noconfirm; then
    echo ">>> Checking for NVIDIA firmware file conflicts..."

    if find /usr/lib/firmware/nvidia -type f | while read -r f; do ! pacman -Qo "$f" &>/dev/null && echo "$f"; done | grep -q .; then

# Auto-clean known problematic NVIDIA firmware dirs if unowned
echo ">>> Cleaning up known unowned NVIDIA firmware paths..."
for dir in /usr/lib/firmware/nvidia/ad10{3..7}; do
  if [[ -d "$dir" ]] && ! pacman -Qo "$dir" &>/dev/null; then
    echo ">>> Removing unowned firmware directory: $dir"
    sudo rm -rf "$dir"
  fi
done

echo ">>> Unowned firmware files found — retrying with targeted overwrite..."
      if sudo pacman -Syu --overwrite '/usr/lib/firmware/nvidia/*' --noconfirm; then
        echo ">>> Upgrade completed with targeted firmware overwrite."
      else
        echo ">>> Targeted overwrite failed. Trying full overwrite fallback..."
        sudo pacman -Syu --overwrite '*' --noconfirm || {
          echo ">>> Upgrade failed even after full overwrite. Manual intervention required."
          exit 1
        }
      fi
    else
      echo ">>> No NVIDIA firmware conflict detected. Trying full overwrite fallback..."
      sudo pacman -Syu --overwrite '*' --noconfirm || {
        echo ">>> Upgrade failed even after full overwrite. Manual intervention required."
        exit 1
      }
    fi
  fi
else
  echo ">>> Upgrade completed successfully on first attempt."
fi

# === FINAL ORPHAN CLEANUP ===
echo ">>> Final orphan cleanup..."
orphans=$(pacman -Qdtq || true)
if [[ -n "$orphans" ]]; then
  sudo pacman -Rns --noconfirm $orphans
else
  echo ">>> No orphans found."
fi

echo ">>> All done. System is up to date."

