#!/usr/bin/env bash
set -Eeuo pipefail

POOL="/data/pool"
DISK_ROOT="/data/disks"
FSTAB="/etc/fstab"
STATE_DIR="/var/lib/mergerfs-manager"
DEFAULT_BALANCE_PERCENT=10

mkdir -p "$STATE_DIR"

die() {
    whiptail --title "mergerfs manager" --msgbox "$*" 12 72
    exit 1
}

msg() {
    whiptail --title "mergerfs manager" --msgbox "$*" 16 78
}

require_root() {
    [[ $EUID -eq 0 ]] || die "Run this program with sudo."
}

require_commands() {
    local missing=()
    local cmd

    for cmd in \
        whiptail lsblk findmnt blkid readlink \
        getfattr setfattr rsync awk sed grep \
        parted partprobe udevadm mkfs.ext4 \
        e2label tune2fs mount umount df
    do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if ((${#missing[@]})); then
        die "Missing commands:

${missing[*]}"
    fi
}

backup_fstab() {
    cp -a "$FSTAB" \
        "${FSTAB}.bak.mergerfs-manager.$(date +%Y%m%d-%H%M%S)"
}

live_branches_raw() {
    getfattr --only-values \
        -n user.mergerfs.branches \
        "$POOL/.mergerfs" 2>/dev/null || true
}

live_branch_paths() {
    live_branches_raw |
        tr ':' '\n' |
        sed 's/=.*$//' |
        sed '/^$/d'
}

is_live_branch() {
    local path="$1"

    live_branch_paths | grep -Fxq "$path"
}

set_live_branches() {
    local value="$1"

    setfattr \
        -n user.mergerfs.branches \
        -v "$value" \
        "$POOL/.mergerfs"
}

add_live_branch() {
    local path="$1"
    local current

    current="$(live_branches_raw)"

    if is_live_branch "$path"; then
        return 0
    fi

    if [[ -n "$current" ]]; then
        current="${current}:${path}=RW"
    else
        current="${path}=RW"
    fi

    set_live_branches "$current"
}

remove_live_branch() {
    local remove="$1"
    local current new=""

    current="$(live_branches_raw)"

    while IFS= read -r branch; do
        [[ -z "$branch" ]] && continue

        local path="${branch%%=*}"

        [[ "$path" == "$remove" ]] && continue

        if [[ -n "$new" ]]; then
            new="${new}:${branch}"
        else
            new="$branch"
        fi
    done < <(printf '%s\n' "$current" | tr ':' '\n')

    [[ -n "$new" ]] ||
        die "Refusing to remove the final mergerfs branch."

    set_live_branches "$new"
}

fstab_pool_line() {
    awk '$2 == "'"$POOL"'" {print; exit}' "$FSTAB"
}

fstab_pool_options() {
    local line

    line="$(fstab_pool_line)"
    [[ -n "$line" ]] || die "No $POOL mergerfs entry found in $FSTAB."

    awk '{print $4}' <<<"$line"
}

write_pool_fstab_branches() {
    local branches="$1"
    local tmp

    tmp="$(mktemp)"

    awk -v pool="$POOL" -v branches="$branches" '
        $2 == pool {
            $1 = branches
        }
        {
            print
        }
    ' "$FSTAB" > "$tmp"

    cat "$tmp" > "$FSTAB"
    rm -f "$tmp"
}

persist_live_branches() {
    local sources=""

    while IFS= read -r path; do
        [[ -z "$path" ]] && continue

        if [[ -n "$sources" ]]; then
            sources="${sources}:${path}"
        else
            sources="$path"
        fi
    done < <(live_branch_paths)

    [[ -n "$sources" ]] ||
        die "Could not construct persistent mergerfs source list."

    write_pool_fstab_branches "$sources"
}

remove_member_fstab_line() {
    local path="$1"
    local tmp

    tmp="$(mktemp)"

    awk -v path="$path" '
        $2 != path {print}
    ' "$FSTAB" > "$tmp"

    cat "$tmp" > "$FSTAB"
    rm -f "$tmp"
}

add_member_fstab_line() {
    local label="$1"
    local path="$2"

    if awk -v path="$path" '$2 == path {found=1} END {exit !found}' "$FSTAB"; then
        die "$path already has an fstab entry."
    fi

    printf 'LABEL=%s %s ext4 defaults,nofail,x-systemd.device-timeout=10 0 2\n' \
        "$label" "$path" >> "$FSTAB"
}

next_disk_label() {
    local n=1

    while blkid -L "disk$n" >/dev/null 2>&1 ||
          [[ -e "$DISK_ROOT/disk$n" ]] &&
          is_live_branch "$DISK_ROOT/disk$n"
    do
        ((n++))
    done

    printf 'disk%s\n' "$n"
}

parent_disk_for_device() {
    local dev="$1"

    lsblk -ndo PKNAME "$dev" 2>/dev/null |
        head -1 |
        sed 's#^#/dev/#'
}

root_parent_disk() {
    local src

    src="$(findmnt -rn -o SOURCE /)"

    while [[ "$(lsblk -ndo TYPE "$src" 2>/dev/null || true)" != "disk" ]]; do
        local parent
        parent="$(parent_disk_for_device "$src")"

        [[ -n "$parent" ]] || break
        src="$parent"
    done

    readlink -f "$src"
}

disk_is_pool_member() {
    local disk="$1"
    local branch src parent

    while IFS= read -r branch; do
        src="$(findmnt -rn -o SOURCE "$branch" 2>/dev/null || true)"
        [[ -z "$src" ]] && continue

        parent="$(parent_disk_for_device "$src")"
        [[ -z "$parent" ]] && parent="$src"

        if [[ "$(readlink -f "$parent")" == "$(readlink -f "$disk")" ]]; then
            return 0
        fi
    done < <(live_branch_paths)

    return 1
}

status_screen() {
    local tmp
    tmp="$(mktemp)"

    {
        printf '%-7s %-7s %-7s %-7s %-24s %s\n' \
            "DISK" "SIZE" "USED" "USE%" "MODEL" "SERIAL"
        printf '%s\n' \
            "-------------------------------------------------------------------------------"

        while IFS= read -r path; do
            local src parent label size used pct model serial

            src="$(findmnt -rn -o SOURCE "$path" 2>/dev/null || true)"
            label="$(basename "$path")"

            if [[ -n "$src" ]]; then
                parent="$(parent_disk_for_device "$src")"
                [[ -z "$parent" ]] && parent="$src"

                read -r size used pct < <(
                    df -h --output=size,used,pcent "$path" |
                        tail -1
                )

                model="$(lsblk -dn -o MODEL "$parent" |
                    sed 's/[[:space:]]*$//' |
                    cut -c1-24)"

                serial="$(lsblk -dn -o SERIAL "$parent" |
                    xargs)"
            else
                size="-"
                used="-"
                pct="-"
                model="NOT MOUNTED"
                serial="-"
            fi

            printf '%-7s %-7s %-7s %-7s %-24s %s\n' \
                "$label" "$size" "$used" "$pct" "$model" "$serial"
        done < <(live_branch_paths)
    } > "$tmp"

    whiptail \
        --title "mergerfs pool status" \
        --scrolltext \
        --textbox "$tmp" 24 100

    rm -f "$tmp"
}

choose_unused_disk() {
    local root_disk
    root_disk="$(root_parent_disk)"

    local options=()

    while read -r dev size model serial; do
        [[ -z "$dev" ]] && continue

        if [[ "$(readlink -f "$dev")" == "$root_disk" ]]; then
            continue
        fi

        if disk_is_pool_member "$dev"; then
            continue
        fi

        options+=(
            "$dev"
            "$size | $model | serial=$serial"
            "OFF"
        )
    done < <(
        lsblk -dnpo NAME,SIZE,MODEL,SERIAL,TYPE |
            awk '$NF == "disk" {
                type=$NF
                serial=$(NF-1)
                $NF=""
                $(NF-1)=""
                print
            }'
    )

    if ((${#options[@]} == 0)); then
        msg "No unused physical disks were detected."
        return 1
    fi

    whiptail \
        --title "Add disk" \
        --radiolist \
        "Select the physical disk to ERASE and add to mergerfs." \
        22 100 12 \
        "${options[@]}" \
        3>&1 1>&2 2>&3
}

add_disk() {
    local dev

    dev="$(choose_unused_disk)" || return

    dev="$(readlink -f "$dev")"

    local model serial size
    model="$(lsblk -dn -o MODEL "$dev" | xargs)"
    serial="$(lsblk -dn -o SERIAL "$dev" | xargs)"
    size="$(lsblk -dn -o SIZE "$dev" | xargs)"

    [[ -n "$serial" ]] ||
        die "Selected disk has no readable serial number."

    local typed
    typed="$(
        whiptail \
            --title "DESTRUCTIVE CONFIRMATION" \
            --inputbox \
            "This will ERASE ALL PARTITIONS AND DATA on:

Device: $dev
Size:   $size
Model:  $model
Serial: $serial

Type the exact serial number to continue:" \
            18 78 \
            3>&1 1>&2 2>&3
    )" || return

    if [[ "$typed" != "$serial" ]]; then
        msg "Serial did not match. Nothing changed."
        return
    fi

    local label path byid

    label="$(next_disk_label)"
    path="$DISK_ROOT/$label"

    byid="$(
        find /dev/disk/by-id -maxdepth 1 -type l \
            -lname "../../$(basename "$dev")" \
            -name 'ata-*' \
            ! -name '*-part*' |
            head -1
    )"

    [[ -n "$byid" ]] ||
        die "Could not determine an ATA by-id path for $dev."

    backup_fstab

    whiptail \
        --title "Add disk" \
        --infobox \
        "Preparing $label

$size
$model
$serial" \
        10 70

    wipefs -a "$byid"

    parted -s "$byid" \
        mklabel gpt \
        mkpart primary ext4 0% 100%

    partprobe "$byid"
    udevadm settle

    local part="${byid}-part1"

    [[ -b "$part" ]] ||
        die "Partition $part did not appear."

    mkfs.ext4 -m 0 -L "$label" "$part"

    mkdir -p "$path"

    add_member_fstab_line "$label" "$path"

    systemctl daemon-reload
    mount "$path"

    add_live_branch "$path"
    persist_live_branches

    msg "Added:

$label
$size
$model
$serial

Mounted at:
$path"
}

choose_live_branch() {
    local options=()

    while IFS= read -r path; do
        local src parent size used pct serial model label

        label="$(basename "$path")"
        src="$(findmnt -rn -o SOURCE "$path" 2>/dev/null || true)"

        [[ -n "$src" ]] || continue

        parent="$(parent_disk_for_device "$src")"
        [[ -z "$parent" ]] && parent="$src"

        read -r size used pct < <(
            df -h --output=size,used,pcent "$path" |
                tail -1
        )

        serial="$(lsblk -dn -o SERIAL "$parent" | xargs)"
        model="$(lsblk -dn -o MODEL "$parent" | xargs)"

        options+=(
            "$path"
            "$size | $pct | $model | $serial"
            "OFF"
        )
    done < <(live_branch_paths)

    whiptail \
        --title "Remove disk" \
        --radiolist \
        "Choose a mergerfs branch to evacuate and remove." \
        22 110 12 \
        "${options[@]}" \
        3>&1 1>&2 2>&3
}

state_file_for_path() {
    basename "$1" |
        sed "s#^#$STATE_DIR/removing-#"
}

source_is_empty() {
    local path="$1"

    ! find "$path" \
        -xdev \
        -mindepth 1 \
        ! -path "$path/lost+found" \
        -print -quit |
        grep -q .
}

finish_removal() {
    local path="$1"
    local state

    state="$(state_file_for_path "$path")"

    if ! source_is_empty "$path"; then
        msg "$path is not empty. Removal will remain pending."
        return 1
    fi

    backup_fstab
    remove_member_fstab_line "$path"
    systemctl daemon-reload

    umount "$path"

    rm -f "$state"

    msg "Evacuation completed.

$path has been removed from mergerfs and unmounted.

The physical disk can now be shut down/removed."
}

evacuate_path() {
    local path="$1"

    whiptail \
        --title "Evacuating disk" \
        --msgbox \
        "Files will now move from:

$path

into:

$POOL

The source branch is NOT part of mergerfs, so mergerfs cannot write files back onto it.

This may take a long time." \
        18 78

    set +e

    rsync \
        -aHAX \
        --info=progress2 \
        --remove-source-files \
        "$path/" \
        "$POOL/"

    local rc=$?

    set -e

    find "$path" \
        -depth \
        -xdev \
        -type d \
        -empty \
        ! -path "$path/lost+found" \
        -delete 2>/dev/null || true

    if ((rc != 0)); then
        msg "rsync exited with code $rc.

The removal state has been preserved.

Use:
Resume pending removal

after correcting the problem."
        return
    fi

    finish_removal "$path"
}

remove_disk() {
    local path

    path="$(choose_live_branch)" || return

    local src parent serial model size label

    src="$(findmnt -rn -o SOURCE "$path")"
    parent="$(parent_disk_for_device "$src")"
    [[ -z "$parent" ]] && parent="$src"

    serial="$(lsblk -dn -o SERIAL "$parent" | xargs)"
    model="$(lsblk -dn -o MODEL "$parent" | xargs)"
    size="$(lsblk -dn -o SIZE "$parent" | xargs)"
    label="$(basename "$path")"

    if ! whiptail \
        --title "Confirm removal" \
        --yesno \
        "Remove and evacuate:

$label
$size
$model
$serial

The disk will first be removed from the live mergerfs branch list. Its files will then be copied into the remaining pool.

Continue?" \
        18 78
    then
        return
    fi

    local state
    state="$(state_file_for_path "$path")"

    {
        printf 'PATH=%q\n' "$path"
        printf 'SERIAL=%q\n' "$serial"
        printf 'MODEL=%q\n' "$model"
    } > "$state"

    backup_fstab

    remove_live_branch "$path"
    persist_live_branches

    evacuate_path "$path"
}

resume_removal() {
    local states=("$STATE_DIR"/removing-*)

    if [[ ! -e "${states[0]}" ]]; then
        msg "No pending removals."
        return
    fi

    local options=()
    local state

    for state in "${states[@]}"; do
        # shellcheck disable=SC1090
        source "$state"

        options+=(
            "$state"
            "$(basename "$PATH") | $MODEL | $SERIAL"
            "OFF"
        )
    done

    local selected

    selected="$(
        whiptail \
            --title "Resume removal" \
            --radiolist \
            "Choose the pending evacuation to resume." \
            20 100 10 \
            "${options[@]}" \
            3>&1 1>&2 2>&3
    )" || return

    # shellcheck disable=SC1090
    source "$selected"

    if is_live_branch "$PATH"; then
        die "$PATH unexpectedly exists in the live mergerfs branch list."
    fi

    if ! findmnt -rn "$PATH" >/dev/null; then
        die "$PATH is not currently mounted."
    fi

    evacuate_path "$PATH"
}

balance_pool() {
    if ! command -v mergerfs.balance >/dev/null 2>&1; then
        msg "mergerfs.balance is not installed.

Install mergerfs-tools first."
        return
    fi

    local hardlink

    hardlink="$(
        find "$DISK_ROOT"/disk[0-9]* \
            -xdev \
            -type f \
            -links +1 \
            -print \
            -quit 2>/dev/null || true
    )"

    if [[ -n "$hardlink" ]]; then
        msg "BALANCE ABORTED.

At least one hardlinked file exists:

$hardlink

The stock mergerfs.balance tool can break hardlink relationships when moving files between filesystems."
        return
    fi

    local percent

    percent="$(
        whiptail \
            --title "Balance mergerfs" \
            --inputbox \
            "Balance tolerance in percentage points.

10 is recommended for this pool.
Lower values cause substantially more file movement." \
            14 72 \
            "$DEFAULT_BALANCE_PERCENT" \
            3>&1 1>&2 2>&3
    )" || return

    [[ "$percent" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
        die "Invalid percentage: $percent"

    if ! whiptail \
        --title "Balance mergerfs" \
        --yesno \
        "Run:

mergerfs.balance -p $percent $POOL

This can move multiple terabytes.

Continue?" \
        14 72
    then
        return
    fi

    clear
    echo
    echo "Balancing mergerfs pool."
    echo
    echo "In another terminal you can monitor with:"
    echo
    echo "  watch -n 30 'df -h --output=target,size,used,avail,pcent $DISK_ROOT/disk[0-9]*'"
    echo
    echo "Press Ctrl-C to stop the balance safely."
    echo

    mergerfs.balance -p "$percent" "$POOL"

    echo
    read -r -p "Press Enter to return to the menu..."
}

show_kernel_errors() {
    local tmp

    tmp="$(mktemp)"

    journalctl -k -b --no-pager |
        grep -Ei \
        'mpt3sas|DID_NO_CONNECT|I/O error|device reset|EXT4-fs.*error|Buffer I/O' |
        tail -100 > "$tmp" || true

    whiptail \
        --title "Storage kernel log" \
        --scrolltext \
        --textbox "$tmp" 24 110

    rm -f "$tmp"
}

main_menu() {
    while true; do
        local choice

        choice="$(
            whiptail \
                --title "mergerfs manager" \
                --menu \
                "Pool: $POOL" \
                23 78 12 \
                "1" "Pool status" \
                "2" "Add disk" \
                "3" "Remove disk" \
                "4" "Resume pending removal" \
                "5" "Balance pool" \
                "6" "Storage/HBA kernel errors" \
                "7" "Exit" \
                3>&1 1>&2 2>&3
        )" || exit 0

        case "$choice" in
            1) status_screen ;;
            2) add_disk ;;
            3) remove_disk ;;
            4) resume_removal ;;
            5) balance_pool ;;
            6) show_kernel_errors ;;
            7) exit 0 ;;
        esac
    done
}

require_root
require_commands

[[ -d "$POOL" ]] ||
    die "$POOL does not exist."

[[ -e "$POOL/.mergerfs" ]] ||
    die "$POOL does not appear to be a mounted mergerfs pool."

main_menu
