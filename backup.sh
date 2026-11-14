#!/bin/bash
# backup.sh - Sistem Backup Lokal (UAS Praktikum Sistem Operasi)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/backup.conf"
OV_SRC=""
OV_DEST=""
ACTION="backup"

usage() {
    cat <<EOF
Penggunaan: $0 [opsi]
  -h         Tampilkan bantuan
  -c FILE    Pakai file konfigurasi FILE
  -s SRC     Override SOURCE
  -d DEST    Override DEST
  -l         Tampilkan daftar arsip
  -r ARSIP   Restore ARSIP ke DEST/restore/
  -i         Pasang crontab
  -U         Hapus crontab
Tanpa argumen: menu interaktif.
EOF
}

# Memuat config, lalu menerapkan override dari CLI
load_config() {
    if [ ! -f "$CONF" ]; then
        echo "Config tidak ditemukan: $CONF" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$CONF"
    [ -n "$OV_SRC" ] && SOURCE="$OV_SRC"
    [ -n "$OV_DEST" ] && DEST="$OV_DEST"
}

# Catat ke log: log_msg NAMA_ARSIP STATUS
log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1 $2" >> "$DEST/backup.log"
}

do_backup() {
    mkdir -p "$DEST" || { echo "Gagal membuat DEST" >&2; return 1; }

    local name="backup_$(date +%Y%m%d-%H%M%S).tar.gz"
    local path="$DEST/$name"

    # SOURCE harus ada
    if [ ! -d "$SOURCE" ]; then
        echo "SOURCE tidak ada: $SOURCE" >&2
        log_msg "$name" "GAGAL"
        return 1
    fi

    # Susun opsi exclude (pola dipisah spasi, wildcard jangan di-glob shell)
    local ex=()
    local pola
    set -f
    for pola in $EXCLUDE; do
        ex+=("--exclude=$pola")
    done
    set +f

    # Jika DEST berada di dalam SOURCE, jangan ikutkan DEST ke arsip
    local src_abs dest_abs
    src_abs="$(cd "$SOURCE" && pwd)"
    dest_abs="$(cd "$DEST" && pwd)"
    case "$dest_abs/" in
        "$src_abs"/*) ex+=("--exclude=.${dest_abs#"$src_abs"}") ;;
    esac

    # Buat arsip dengan path relatif
    if tar -czf "$path" "${ex[@]}" -C "$SOURCE" . 2>/dev/null; then
        echo "Backup berhasil: $path"
        log_msg "$name" "SUKSES"
        return 0
    else
        echo "Backup gagal" >&2
        rm -f "$path"
        log_msg "$name" "GAGAL"
        return 1
    fi
}

# ---------- Parsing opsi ----------
if [ $# -eq 0 ]; then
    echo "Menu interaktif belum dibuat."
    exit 0
fi

while getopts "hc:s:d:lr:iU" opt; do
    case "$opt" in
        h) ACTION="help" ;;
        c) CONF="$OPTARG" ;;
        s) OV_SRC="$OPTARG" ;;
        d) OV_DEST="$OPTARG" ;;
        l) ACTION="list" ;;
        r) ACTION="restore"; ARSIP="$OPTARG" ;;
        i) ACTION="cron_install" ;;
        U) ACTION="cron_remove" ;;
        *) usage; exit 1 ;;
    esac
done

case "$ACTION" in
    help)   usage; exit 0 ;;
    backup) load_config; do_backup; exit $? ;;
    *)      echo "Aksi '$ACTION' belum diimplementasikan"; exit 1 ;;
esac
