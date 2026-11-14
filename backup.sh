
#!/bin/bash

# Interface & Configuration

# Menentukan lokasi script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Konfigurasi default
CONFIG_FILE="$SCRIPT_DIR/backup.conf"

# Fungsi bantuan
show_help() {
    echo "=================================="
    echo "       LOCAL BACKUP SYSTEM"
    echo "=================================="
    echo "Penggunaan: ./backup.sh [opsi]"
    echo ""
    echo "Opsi:"
    echo "-h          Menampilkan bantuan"
    echo "-c FILE     Memilih file konfigurasi"
    echo "-s SRC      Mengganti direktori sumber"
    echo "-d DEST     Mengganti direktori tujuan"
    echo "-l          Menampilkan daftar arsip"
    echo "-r ARSIP    Melakukan restore"
    echo "-i          Memasang cron"
    echo "-U          Menghapus cron"
    echo ""
}

# Membaca konfigurasi
load_config() {

    if [[ ! -f "$CONFIG_FILE" || ! -r "$CONFIG_FILE" ]]; then
        echo "Error: Konfigurasi tidak ditemukan!"
        exit 1
    fi

    source "$CONFIG_FILE"

    if [[ -z "${SOURCE:-}" || -z "${DEST:-}" ||
          -z "${RETENTION:-}" || -z "${CRON:-}" ||
          ! ${EXCLUDE+x} ]]; then
        echo "Error: Konfigurasi tidak lengkap!"
        exit 1
    fi

    if ! [[ "$RETENTION" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: RETENTION tidak valid!"
        exit 1
    fi
}

# Parsing opsi terminal
parse_options() {

    while getopts ":hc:s:d:lr:iU" opt; do

        case "$opt" in

            h)
                show_help
                exit 0
                ;;

            c) CONFIG_FILE="$OPTARG" ;;
            s) OVERRIDE_SOURCE="$OPTARG" ;;
            d) OVERRIDE_DEST="$OPTARG" ;;
            l) ACTION="list" ;;

            r)
                ACTION="restore"
                RESTORE_ARCHIVE="$OPTARG"
                ;;

            i) ACTION="install_cron" ;;
            U) ACTION="remove_cron" ;;

            :)
                echo "Error: Opsi -$OPTARG membutuhkan argumen!"
                exit 1
                ;;

            \?)
                echo "Error: Opsi tidak dikenal -$OPTARG"
                exit 1
                ;;

        esac
    done
}

# Mengubah path relatif menjadi absolut
make_absolute() {

    local path="$1"

    if [[ "$path" == /* ]]; then
        echo "$path"
    else
        echo "$PWD/$path"
    fi
}

# Normalisasi path
resolve_paths() {
    SOURCE="$(make_absolute "$SOURCE")"
    DEST="$(make_absolute "$DEST")"
}

OVERRIDE_SOURCE=""
OVERRIDE_DEST=""
ACTION=""

parse_options "$@"

load_config

# Menerapkan override dari terminal
if [[ -n "$OVERRIDE_SOURCE" ]]; then
    SOURCE="$OVERRIDE_SOURCE"
fi

if [[ -n "$OVERRIDE_DEST" ]]; then
    DEST="$OVERRIDE_DEST"
fi

resolve_paths

echo "Konfigurasi berhasil dibaca!"
echo "SOURCE    : $SOURCE"
echo "DEST      : $DEST"
echo "RETENTION : $RETENTION"
echo "EXCLUDE   : $EXCLUDE"
echo "CRON      : $CRON"
echo "ACTION    : ${ACTION:-backup}"
