# Sistem Backup Lokal (`backup.sh`)

Project UAS Praktikum Sistem Operasi 2026: sistem backup lokal otomatis berbasis **Bash murni** dengan arsip `.tar.gz`, rotasi retensi, restore, pencatatan log, dan penjadwalan `crontab`.

## Struktur File

- `backup.sh` — Script utama (mode CLI dan mode menu interaktif).
- `backup.conf` — File konfigurasi default (`SOURCE`, `DEST`, `RETENTION`, `EXCLUDE`, `CRON`).
- `README.md` — Panduan penggunaan dan pengujian.

## Dependensi

Menggunakan tool standar Linux tanpa Python/Perl/C dan tanpa `sudo`:
- `bash` (>= 4.3)
- `tar`, `gzip`, `date`, `du`, `wc`, `grep`, `sha256sum`
- `cron` / `cronie` (pada Arch Linux: `sudo pacman -S cronie`)
- `shellcheck` (opsional untuk audit kualitas script: `sudo pacman -S shellcheck` atau `sudo apt install shellcheck`)

Pastikan `backup.sh` executable:
```bash
chmod +x backup.sh
```

## Konfigurasi (`backup.conf`)

```bash
SOURCE="/home/mahasiswa/data-penting"
DEST="/home/mahasiswa/backup"
RETENTION=3
EXCLUDE="*.tmp draft"
CRON="0 2 * * *"
```

- `SOURCE`: direktori sumber backup (wajib ada saat backup dijalankan).
- `DEST`: direktori tujuan arsip dan `backup.log` (dibuat otomatis jika belum ada).
- `RETENTION`: jumlah maksimum arsip terbaru yang dipertahankan (`>= 1`).
- `EXCLUDE`: pola file/folder yang dikecualikan, dipisah spasi.
- `CRON`: jadwal 5 field untuk `crontab`.

## Cara Menjalankan

### 1. Mode Interaktif (Menu)
Jalankan tanpa argumen:
```bash
./backup.sh
```

### 2. Mode Argumen (CLI)
```bash
./backup.sh -h                                 # Tampilkan bantuan (exit 0)
./backup.sh -c backup.conf                     # Backup memakai file konfigurasi tertentu
./backup.sh -s /path/src -d /path/dest         # Backup dengan override SOURCE dan DEST
./backup.sh -l                                 # Daftar arsip dan ukurannya di DEST
./backup.sh -r backup_20261115-120000.tar.gz   # Restore arsip ke DEST/restore/
./backup.sh -i                                 # Pasang jadwal crontab (idempoten)
./backup.sh -U                                 # Hapus jadwal crontab milik script ini
```

### 3. Fitur Bonus
- **Verifikasi Checksum SHA-256**: file `.sha256` dibuat otomatis per arsip, ikut terhapus saat rotasi retensi, diverifikasi otomatis saat restore, dan dapat dicek manual:
  ```bash
  ./backup.sh -v backup_20261115-120000.tar.gz
  ```
- **Mode Dry-Run (`-n`)**: simulasi backup tanpa menulis arsip atau log:
  ```bash
  ./backup.sh -n
  ./backup.sh -n -s /path/src -d /path/dest
  ```
- **Statistik Ukuran Backup (`-S`)**: menampilkan jumlah arsip, total ukuran, rata-rata, dan arsip terbesar:
  ```bash
  ./backup.sh -S
  ```
- **Lock File (`DEST/.backup.lock` + `trap`)**: mencegah dua proses backup berjalan bersamaan pada direktori tujuan yang sama.

## Pengujian

```bash
shellcheck backup.sh
./check-sample.sh /path/ke/folder-proyek
```
