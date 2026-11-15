#!/usr/bin/env bash
# backup.sh - Sistem Backup Lokal (UAS Praktikum Sistem Operasi 2026)

set -u

readonly EXIT_OK=0
readonly EXIT_ERR_GENERAL=1
readonly EXIT_ERR_USAGE=2
readonly EXIT_ERR_CONFIG=3
readonly EXIT_ERR_SOURCE=4
readonly EXIT_ERR_BACKUP=5
readonly EXIT_ERR_RESTORE=6
readonly EXIT_ERR_CRON=7
readonly EXIT_ERR_LOCK=8
readonly EXIT_ERR_VERIFY=9

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONF="$SCRIPT_DIR/backup.conf"
LOCK_DIR=""

die() {
    local code="${1:-$EXIT_ERR_GENERAL}"
    shift || true
    echo "ERROR: $*" >&2
    exit "$code"
}

release_lock() {
    if [ -n "${LOCK_DIR:-}" ] && [ -d "$LOCK_DIR" ]; then
        rm -f "$LOCK_DIR/pid" 2>/dev/null || true
        rmdir "$LOCK_DIR" 2>/dev/null || true
        LOCK_DIR=""
    fi
}

trap release_lock EXIT INT TERM

acquire_lock() {
    local lock_path="$DEST/.backup.lock"
    if mkdir "$lock_path" 2>/dev/null; then
        LOCK_DIR="$lock_path"
        echo "$$" > "$LOCK_DIR/pid"
        return 0
    fi

    # Pulihkan lock usang jika proses pemiliknya sudah mati
    if [ -f "$lock_path/pid" ]; then
        local old_pid
        old_pid="$(cat "$lock_path/pid" 2>/dev/null || true)"
        if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
            rm -rf "$lock_path"
            if mkdir "$lock_path" 2>/dev/null; then
                LOCK_DIR="$lock_path"
                echo "$$" > "$LOCK_DIR/pid"
                return 0
            fi
        fi
    fi

    return 1
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

Opsi utama:
  -h          Tampilkan bantuan ini dan keluar dengan status 0
  -c FILE     Pakai file konfigurasi FILE (default: backup.conf di folder script)
  -s SRC      Override nilai SOURCE
  -d DEST     Override nilai DEST
  -l          Tampilkan daftar arsip di DEST (nama dan ukuran)
  -r ARSIP    Restore ARSIP ke folder restore/ di dalam DEST
  -i          Pasang baris crontab dari konfigurasi
  -U          Hapus baris crontab yang dipasang

Opsi bonus:
  -n          Mode dry-run (simulasi backup tanpa menulis arsip atau log)
  -v ARSIP    Verifikasi checksum SHA-256 dan integritas arsip
  -S          Tampilkan statistik ukuran arsip backup di DEST
EOF
}

load_conf() {
    local conf="$1"
    [ -f "$conf" ] && [ -r "$conf" ] || die "$EXIT_ERR_CONFIG" "File konfigurasi tidak ditemukan atau tidak bisa dibaca: $conf"
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

build_exclude_args() {
    local -n out_args=$1
    if [ -n "${EXCLUDE:-}" ]; then
        local -a excl=()
        local pola
        read -ra excl <<< "$EXCLUDE"
        for pola in "${excl[@]}"; do
            out_args+=("--exclude=$pola")
        done
    fi

    # Hindari rekursi arsip jika DEST berada di dalam SOURCE (atau sama dengan SOURCE)
    if [ -d "$SOURCE" ] && [ -d "$DEST" ]; then
        local src_abs dest_abs src_base
        src_abs="$(cd "$SOURCE" && pwd)"
        dest_abs="$(cd "$DEST" && pwd)"
        src_base="$(basename "$src_abs")"
        if [ "$dest_abs" = "$src_abs" ]; then
            out_args+=(
                "--exclude=$src_base/backup_*.tar.gz"
                "--exclude=$src_base/backup_*.tar.gz.sha256"
                "--exclude=$src_base/backup.log"
                "--exclude=$src_base/.backup.lock"
            )
        else
            case "$dest_abs/" in
                "$src_abs"/*)
                    local rel_dest="${dest_abs#"$src_abs"/}"
                    out_args+=("--exclude=$src_base/$rel_dest")
                    ;;
            esac
        fi
    fi
}

generate_checksum() {
    local archive_path="$1"
    local dir_name file_name
    dir_name="$(dirname "$archive_path")"
    file_name="$(basename "$archive_path")"

    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$dir_name" && sha256sum "$file_name" > "${file_name}.sha256")
    fi
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
            if rm -f "${archives[$i]}" "${archives[$i]}.sha256"; then
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

    if ! acquire_lock; then
        echo "ERROR: Proses backup lain sedang berjalan di $DEST" >&2
        log_line "$archive_name" "GAGAL" "lock aktif di $DEST" || true
        return "$EXIT_ERR_LOCK"
    fi

    if [ ! -d "$SOURCE" ]; then
        echo "ERROR: Direktori sumber tidak ditemukan: $SOURCE" >&2
        log_line "$archive_name" "GAGAL" "SOURCE tidak ditemukan: $SOURCE" || true
        release_lock
        return "$EXIT_ERR_SOURCE"
    fi

    local -a exclude_args=()
    build_exclude_args exclude_args

    local -a tar_args=("-czf" "$target" ${exclude_args[@]+"${exclude_args[@]}"})
    if tar "${tar_args[@]}" -C "$(dirname "$SOURCE")" "$(basename "$SOURCE")" 2>/dev/null; then
        if ! tar -tzf "$target" > /dev/null 2>&1; then
            rm -f "$target"
            echo "ERROR: Arsip yang dihasilkan tidak valid: $target" >&2
            log_line "$archive_name" "GAGAL" "validasi tar -tzf gagal" || true
            release_lock
            return "$EXIT_ERR_BACKUP"
        fi
        generate_checksum "$target" || echo "WARNING: Gagal membuat checksum sha256" >&2
        log_line "$archive_name" "SUKSES" || true
        echo "Backup selesai: $target"
        apply_retention
        release_lock
        return "$EXIT_OK"
    else
        rm -f "$target"
        echo "ERROR: Gagal membuat arsip backup: $target" >&2
        log_line "$archive_name" "GAGAL" "perintah tar gagal" || true
        release_lock
        return "$EXIT_ERR_BACKUP"
    fi
}

do_dry_run() {
    local stamp archive_name target
    stamp="$(date +%Y%m%d-%H%M%S)"
    archive_name="backup_${stamp}.tar.gz"
    target="$DEST/$archive_name"

    echo "=== MODE DRY-RUN (Simulasi) ==="
    echo "SOURCE    : $SOURCE"
    echo "DEST      : $DEST"
    echo "RETENTION : $RETENTION"
    echo "EXCLUDE   : ${EXCLUDE:-<kosong>}"
    echo "Target    : $target (tidak dibuat)"

    if [ ! -d "$SOURCE" ]; then
        echo "[DRY-RUN] ERROR: Direktori sumber tidak ditemukan: $SOURCE" >&2
        return "$EXIT_ERR_SOURCE"
    fi

    local -a exclude_args=()
    build_exclude_args exclude_args

    echo ""
    echo "Daftar entri yang akan diarsipkan:"
    if ! tar -cf /dev/null -v ${exclude_args[@]+"${exclude_args[@]}"} -C "$(dirname "$SOURCE")" "$(basename "$SOURCE")" 2>/dev/null; then
        echo "[DRY-RUN] ERROR: Simulasi tar gagal" >&2
        return "$EXIT_ERR_BACKUP"
    fi

    if [ -d "$DEST" ]; then
        shopt -s nullglob
        local -a existing=("$DEST"/backup_*.tar.gz)
        shopt -u nullglob
        local projected=$(( ${#existing[@]} + 1 ))
        if [ "$projected" -gt "$RETENTION" ]; then
            local to_remove=$(( projected - RETENTION ))
            local i
            echo ""
            echo "Simulasi retensi (batas=$RETENTION, akan menghapus $to_remove arsip tertua):"
            for ((i=0; i<to_remove && i<${#existing[@]}; i++)); do
                echo "  - $(basename "${existing[$i]}")"
            done
        fi
    fi

    echo ""
    echo "[DRY-RUN] Selesai tanpa menulis arsip atau log."
    return "$EXIT_OK"
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

resolve_archive_path() {
    local arsip_input="$1"
    if [ -f "$arsip_input" ]; then
        echo "$arsip_input"
    else
        echo "$DEST/$arsip_input"
    fi
}

do_verify() {
    local arsip_input="${1:-}"
    if [ -z "$arsip_input" ]; then
        echo "ERROR: Nama atau path arsip harus diberikan untuk verifikasi" >&2
        return "$EXIT_ERR_USAGE"
    fi

    local arsip
    arsip="$(resolve_archive_path "$arsip_input")"
    if [ ! -f "$arsip" ]; then
        echo "ERROR: Arsip tidak ditemukan: $arsip_input" >&2
        return "$EXIT_ERR_VERIFY"
    fi

    if ! tar -tzf "$arsip" > /dev/null 2>&1; then
        echo "ERROR: Arsip tar.gz rusak atau tidak valid: $arsip" >&2
        return "$EXIT_ERR_VERIFY"
    fi

    local checksum_file="${arsip}.sha256"
    if [ ! -f "$checksum_file" ]; then
        echo "ERROR: File checksum tidak ditemukan: $(basename "$checksum_file")" >&2
        return "$EXIT_ERR_VERIFY"
    fi

    local dir_name file_name
    dir_name="$(dirname "$arsip")"
    file_name="$(basename "$arsip")"
    if (cd "$dir_name" && sha256sum -c "${file_name}.sha256"); then
        echo "Verifikasi checksum dan integritas tar.gz OK: $file_name"
        return "$EXIT_OK"
    else
        echo "ERROR: Checksum SHA-256 tidak cocok untuk $file_name" >&2
        return "$EXIT_ERR_VERIFY"
    fi
}

do_restore() {
    local arsip_input="${1:-}"

    if [ -z "$arsip_input" ]; then
        echo "ERROR: Nama atau path arsip harus diberikan untuk restore" >&2
        return "$EXIT_ERR_USAGE"
    fi

    local arsip
    arsip="$(resolve_archive_path "$arsip_input")"

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

    if [ -f "${arsip}.sha256" ] && command -v sha256sum >/dev/null 2>&1; then
        local dir_name file_name
        dir_name="$(dirname "$arsip")"
        file_name="$(basename "$arsip")"
        if ! (cd "$dir_name" && sha256sum -c "${file_name}.sha256" > /dev/null 2>&1); then
            echo "ERROR: Checksum SHA-256 tidak cocok, restore dibatalkan: $arsip" >&2
            log_line "$file_name" "RESTORE GAGAL" "checksum sha256 tidak cocok" || true
            return "$EXIT_ERR_RESTORE"
        fi
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

format_bytes() {
    local bytes="$1"
    if [ "$bytes" -ge 1048576 ]; then
        local whole=$(( bytes / 1048576 ))
        local frac=$(( (bytes % 1048576) * 100 / 1048576 ))
        printf '%d.%02d MB (%d B)' "$whole" "$frac" "$bytes"
    elif [ "$bytes" -ge 1024 ]; then
        local whole=$(( bytes / 1024 ))
        local frac=$(( (bytes % 1024) * 100 / 1024 ))
        printf '%d.%02d KB (%d B)' "$whole" "$frac" "$bytes"
    else
        printf '%d B' "$bytes"
    fi
}

do_stats() {
    if [ ! -d "$DEST" ]; then
        echo "Direktori DEST belum ada: $DEST"
        return "$EXIT_OK"
    fi

    shopt -s nullglob
    local -a archives=("$DEST"/backup_*.tar.gz)
    shopt -u nullglob

    local count=${#archives[@]}
    if [ "$count" -eq 0 ]; then
        echo "Belum ada arsip backup di $DEST"
        return "$EXIT_OK"
    fi

    local total_bytes=0
    local max_bytes=-1
    local max_name=""
    local arch size_bytes
    for arch in "${archives[@]}"; do
        size_bytes="$(wc -c < "$arch" | tr -d '[:space:]')"
        total_bytes=$(( total_bytes + size_bytes ))
        if [ "$size_bytes" -gt "$max_bytes" ]; then
            max_bytes="$size_bytes"
            max_name="$(basename "$arch")"
        fi
    done

    local avg_bytes=$(( total_bytes / count ))
    echo "=== Statistik Backup ($DEST) ==="
    echo "Jumlah arsip   : $count (batas retensi: $RETENTION)"
    echo "Total ukuran   : $(format_bytes "$total_bytes")"
    echo "Rata-rata      : $(format_bytes "$avg_bytes")"
    echo "Arsip terbesar : $max_name - $(format_bytes "$max_bytes")"
    return "$EXIT_OK"
}

do_cron_install() {
    local cmd="$SCRIPT_DIR/backup.sh -c $DEFAULT_CONF"
    local line="$CRON $cmd"
    if { crontab -l 2>/dev/null | grep -vF "$cmd"; echo "$line"; } | crontab -; then
        echo "Cron terpasang: $line"
        return "$EXIT_OK"
    else
        echo "ERROR: Gagal menulis crontab" >&2
        return "$EXIT_ERR_CRON"
    fi
}

do_cron_remove() {
    local cmd="$SCRIPT_DIR/backup.sh -c $DEFAULT_CONF"
    if { crontab -l 2>/dev/null | grep -vF "$cmd"; } | crontab -; then
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
        echo "=== Sistem Backup Lokal ==="
        echo "Config: SOURCE=$SOURCE | DEST=$DEST | RETENTION=$RETENTION"
        echo "1) Backup sekarang"
        echo "2) List arsip"
        echo "3) Restore arsip"
        echo "4) Pasang cron ($CRON)"
        echo "5) Hapus cron"
        echo "6) Verifikasi checksum arsip [Bonus]"
        echo "7) Simulasi dry-run backup [Bonus]"
        echo "8) Statistik ukuran backup [Bonus]"
        echo "0) Keluar"
        read -r -p "Pilih: " pilih || exit "$EXIT_OK"
        case "$pilih" in
            1) do_backup || true ;;
            2) do_list || true ;;
            3)
                do_list || true
                read -r -p "Nama atau path arsip: " a || continue
                if [ -n "$a" ]; then
                    do_restore "$a" || true
                else
                    echo "Input arsip kosong, dibatalkan."
                fi
                ;;
            4) do_cron_install || true ;;
            5) do_cron_remove || true ;;
            6)
                do_list || true
                read -r -p "Nama atau path arsip yang diverifikasi: " a || continue
                if [ -n "$a" ]; then
                    do_verify "$a" || true
                else
                    echo "Input arsip kosong, dibatalkan."
                fi
                ;;
            7) do_dry_run || true ;;
            8) do_stats || true ;;
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
    local target_archive=""
    local opt

    while getopts ":hc:s:d:lr:iUnv:S" opt; do
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
                target_archive="$OPTARG"
                ;;
            i) action="cron_install" ;;
            U) action="cron_remove" ;;
            n) action="dry_run" ;;
            v)
                action="verify"
                target_archive="$OPTARG"
                ;;
            S) action="stats" ;;
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
        dry_run)      do_dry_run ;;
        list)         do_list ;;
        restore)      do_restore "$target_archive" ;;
        verify)       do_verify "$target_archive" ;;
        stats)        do_stats ;;
        cron_install) do_cron_install ;;
        cron_remove)  do_cron_remove ;;
    esac
    exit $?
}

main "$@"
