#!/usr/bin/env bash

set -u

readonly EXIT_OK=0
readonly EXIT_ERR_GENERAL=1
readonly EXIT_ERR_USAGE=2
readonly EXIT_ERR_CONFIG=3
readonly EXIT_ERR_SOURCE=4
readonly EXIT_ERR_BACKUP=5
readonly EXIT_ERR_RESTORE=6
readonly EXIT_ERR_CRON=7

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONF="$SCRIPT_DIR/backup.conf"

die() {
    local code="${1:-$EXIT_ERR_GENERAL}"
    shift || true
    echo "ERROR: $*" >&2
    exit "$code"
}

log_line() {
    local arsip="$1"
    local status="$2"
    local detail="${3:-}"

    [ -n "${DEST:-}" ] || return "$EXIT_ERR_CONFIG"
    mkdir -p "$DEST" 2>/dev/null || return "$EXIT_ERR_GENERAL"

    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    if [ -n "$detail" ]; then
        printf '%s | %s | %s | %s\n' "$ts" "$arsip" "$status" "$detail" >> "$DEST/backup.log"
    else
        printf '%s | %s | %s\n' "$ts" "$arsip" "$status" >> "$DEST/backup.log"
    fi
}

show_help() {
    cat <<EOF
Penggunaan: ./backup.sh [opsi]

Tanpa argumen: membuka menu interaktif.

Opsi:
  -h          Tampilkan bantuan ini dan keluar dengan status 0
  -c FILE     Pakai file konfigurasi FILE (default: backup.conf di folder script)
  -s SRC      Override nilai SOURCE
  -d DEST     Override nilai DEST
  -l          Tampilkan daftar arsip di DEST (nama dan ukuran)
  -r ARSIP    Restore ARSIP ke folder restore/ di dalam DEST
  -i          Pasang baris crontab dari konfigurasi
  -U          Hapus baris crontab yang dipasang
EOF
}

load_conf() {
    local conf="$1"
    [ -f "$conf" ] || die "$EXIT_ERR_CONFIG" "File konfigurasi tidak ditemukan: $conf"
    # shellcheck source=/dev/null
    source "$conf"

    [ -n "${SOURCE:-}" ] || die "$EXIT_ERR_CONFIG" "SOURCE belum diisi di config"
    [ -n "${DEST:-}" ] || die "$EXIT_ERR_CONFIG" "DEST belum diisi di config"
    RETENTION="${RETENTION:-3}"
    EXCLUDE="${EXCLUDE:-}"
    CRON="${CRON:-0 2 * * *}"

    [[ "$RETENTION" =~ ^[1-9][0-9]*$ ]] \
        || die "$EXIT_ERR_CONFIG" "RETENTION harus bilangan bulat >= 1"
}

apply_retention() {
    shopt -s nullglob
    local -a archives=("$DEST"/backup_*.tar.gz)
    shopt -u nullglob

    local jumlah=${#archives[@]}
    if [ "$jumlah" -gt "$RETENTION" ]; then
        local kelebihan=$(( jumlah - RETENTION ))
        local i
        for ((i=0; i<kelebihan; i++)); do
            local arch_name
            arch_name="$(basename "${archives[$i]}")"
            if rm -f "${archives[$i]}"; then
                log_line "$arch_name" "HAPUS" "retensi (batas=$RETENTION)" || true
                echo "Retensi: hapus $arch_name"
            else
                echo "WARNING: Gagal menghapus arsip retensi: $arch_name" >&2
            fi
        done
    fi
}

do_backup() {
    local stamp archive_name target
    stamp="$(date +%Y%m%d-%H%M%S)"
    archive_name="backup_${stamp}.tar.gz"
    target="$DEST/$archive_name"

    if ! mkdir -p "$DEST" 2>/dev/null; then
        echo "ERROR: Gagal membuat direktori tujuan: $DEST" >&2
        return "$EXIT_ERR_BACKUP"
    fi

    if [ ! -d "$SOURCE" ]; then
        echo "ERROR: Direktori sumber tidak ditemukan: $SOURCE" >&2
        log_line "$archive_name" "GAGAL" "SOURCE tidak ditemukan: $SOURCE" || true
        return "$EXIT_ERR_SOURCE"
    fi

    local -a tar_args=("-czf" "$target")
    if [ -n "$EXCLUDE" ]; then
        local -a excl=()
        local pola
        read -ra excl <<< "$EXCLUDE"
        for pola in "${excl[@]}"; do
            tar_args+=("--exclude=$pola")
        done
    fi

    if tar "${tar_args[@]}" -C "$(dirname "$SOURCE")" "$(basename "$SOURCE")" 2>/dev/null; then
        if ! tar -tzf "$target" > /dev/null 2>&1; then
            rm -f "$target"
            echo "ERROR: Arsip yang dihasilkan tidak valid: $target" >&2
            log_line "$archive_name" "GAGAL" "validasi tar -tzf gagal" || true
            return "$EXIT_ERR_BACKUP"
        fi
        log_line "$archive_name" "SUKSES" || true
        echo "Backup selesai: $target"
        apply_retention
        return "$EXIT_OK"
    else
        rm -f "$target"
        echo "ERROR: Gagal membuat arsip backup: $target" >&2
        log_line "$archive_name" "GAGAL" "perintah tar gagal" || true
        return "$EXIT_ERR_BACKUP"
    fi
}

do_list() {
    if [ ! -d "$DEST" ]; then
        echo "Direktori DEST belum ada: $DEST"
        return "$EXIT_OK"
    fi

    shopt -s nullglob
    local -a archives=("$DEST"/backup_*.tar.gz)
    shopt -u nullglob

    if [ "${#archives[@]}" -eq 0 ]; then
        echo "Belum ada arsip backup di $DEST"
        return "$EXIT_OK"
    fi

    local arch size
    for arch in "${archives[@]}"; do
        size="$(du -h "$arch" | cut -f1)"
        printf '%-35s %s\n' "$(basename "$arch")" "$size"
    done
    return "$EXIT_OK"
}

do_restore() {
    local arsip_input="${1:-}"

    if [ -z "$arsip_input" ]; then
        echo "ERROR: Nama atau path arsip harus diberikan untuk restore" >&2
        return "$EXIT_ERR_USAGE"
    fi

    local arsip="$arsip_input"
    if [ ! -f "$arsip" ]; then
        arsip="$DEST/$arsip_input"
    fi

    if [ ! -f "$arsip" ]; then
        echo "ERROR: Arsip tidak ditemukan: $arsip_input" >&2
        log_line "$(basename "$arsip_input")" "RESTORE GAGAL" "arsip tidak ditemukan" || true
        return "$EXIT_ERR_RESTORE"
    fi

    if ! tar -tzf "$arsip" > /dev/null 2>&1; then
        echo "ERROR: Arsip tidak valid atau rusak: $arsip" >&2
        log_line "$(basename "$arsip")" "RESTORE GAGAL" "arsip tidak valid" || true
        return "$EXIT_ERR_RESTORE"
    fi

    local restore_dir="$DEST/restore"
    if ! mkdir -p "$restore_dir" 2>/dev/null; then
        echo "ERROR: Gagal membuat direktori restore: $restore_dir" >&2
        log_line "$(basename "$arsip")" "RESTORE GAGAL" "gagal membuat $restore_dir" || true
        return "$EXIT_ERR_RESTORE"
    fi

    if ! tar -xzf "$arsip" -C "$restore_dir"; then
        echo "ERROR: Ekstraksi arsip gagal: $arsip" >&2
        log_line "$(basename "$arsip")" "RESTORE GAGAL" "ekstraksi tar gagal" || true
        return "$EXIT_ERR_RESTORE"
    fi

    log_line "$(basename "$arsip")" "RESTORE OK" "ke $restore_dir" || true
    echo "Restore selesai ke $restore_dir"
    return "$EXIT_OK"
}

do_cron_install() {
    local line="$CRON $SCRIPT_DIR/backup.sh -c $DEFAULT_CONF"
    if { crontab -l 2>/dev/null | grep -vF "$line"; echo "$line"; } | crontab -; then
        echo "Cron terpasang: $line"
        return "$EXIT_OK"
    else
        echo "ERROR: Gagal menulis crontab" >&2
        return "$EXIT_ERR_CRON"
    fi
}

do_cron_remove() {
    local line="$CRON $SCRIPT_DIR/backup.sh -c $DEFAULT_CONF"
    if { crontab -l 2>/dev/null | grep -vF "$line"; } | crontab -; then
        echo "Cron dihapus (jika sebelumnya terpasang)"
        return "$EXIT_OK"
    else
        echo "ERROR: Gagal memperbarui crontab" >&2
        return "$EXIT_ERR_CRON"
    fi
}

menu() {
    load_conf "$DEFAULT_CONF"
    while true; do
        echo ""
        echo "=== Sistem Backup ==="
        echo "1) Backup sekarang"
        echo "2) List arsip"
        echo "3) Restore arsip"
        echo "4) Pasang cron"
        echo "5) Hapus cron"
        echo "0) Keluar"
        read -r -p "Pilih: " pilih || exit "$EXIT_OK"
        case "$pilih" in
            1) do_backup ;;
            2) do_list ;;
            3)
                read -r -p "Nama atau path arsip: " a || continue
                do_restore "$a"
                ;;
            4) do_cron_install ;;
            5) do_cron_remove ;;
            0) exit "$EXIT_OK" ;;
            *) echo "Pilihan tidak dikenal" ;;
        esac
    done
}

main() {
    if [ "$#" -eq 0 ]; then
        menu
        exit "$EXIT_OK"
    fi

    local conf_file="$DEFAULT_CONF"
    local override_src=""
    local override_dest=""
    local action="backup"
    local restore_target=""
    local opt

    while getopts ":hc:s:d:lr:iU" opt; do
        case "$opt" in
            h)
                show_help
                exit "$EXIT_OK"
                ;;
            c) conf_file="$OPTARG" ;;
            s) override_src="$OPTARG" ;;
            d) override_dest="$OPTARG" ;;
            l) action="list" ;;
            r)
                action="restore"
                restore_target="$OPTARG"
                ;;
            i) action="cron_install" ;;
            U) action="cron_remove" ;;
            :)
                die "$EXIT_ERR_USAGE" "Opsi -$OPTARG memerlukan argumen. Coba -h"
                ;;
            \?)
                die "$EXIT_ERR_USAGE" "Opsi tidak dikenal: -$OPTARG. Coba -h"
                ;;
        esac
    done
    shift $((OPTIND - 1))

    load_conf "$conf_file"
    [ -n "$override_src" ] && SOURCE="$override_src"
    [ -n "$override_dest" ] && DEST="$override_dest"

    case "$action" in
        backup)       do_backup ;;
        list)         do_list ;;
        restore)      do_restore "$restore_target" ;;
        cron_install) do_cron_install ;;
        cron_remove)  do_cron_remove ;;
    esac
    exit $?
}

main "$@"
