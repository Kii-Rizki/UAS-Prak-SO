<div align="center">

# 📦 Sistem Backup Lokal (`backup.sh`)

**Proyek UAS Praktikum Sistem Operasi 2026**  
Sistem backup lokal otomatis berbasis **Bash murni** dengan kompresi `.tar.gz`, rotasi retensi, restore, logging terpusat, dan penjadwalan `crontab`.

![Bash](https://img.shields.io/badge/Bash-4.3%2B-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)
![Mode](https://img.shields.io/badge/Mode-CLI%20%26%20Menu%20Interaktif-0A66C2?style=flat-square)
![Constraint](https://img.shields.io/badge/Akses-Tanpa%20Sudo%20%26%20Offline-6E40C9?style=flat-square)
![ShellCheck](https://img.shields.io/badge/ShellCheck-Clean-2EA44F?style=flat-square)

</div>

---

## 📁 Isi Repositori

| File | Deskripsi |
| :--- | :--- |
| `backup.sh` | Script utama (mendukung mode argumen CLI dan mode menu interaktif). |
| `backup.conf` | File konfigurasi default (`SOURCE`, `DEST`, `RETENTION`, `EXCLUDE`, `CRON`). |
| `README.md` | Dokumentasi instalasi, konfigurasi, penggunaan, dan pengujian. |

---

## ⚙️ Kebutuhan Sistem

Script berjalan dengan tool standar Linux tanpa `sudo` dan tanpa bahasa eksternal (Python/Perl/C):

- **Shell:** `bash` (>= 4.3)
- **Utilitas inti:** `tar`, `gzip`, `date`, `du`, `wc`, `grep`, `sha256sum`
- **Penjadwalan:** `cron` atau `cronie` (pengguna Arch Linux: `sudo pacman -S cronie`)
- **Linter (opsional):** `shellcheck` (`sudo pacman -S shellcheck` atau `sudo apt install shellcheck`)

Berikan izin eksekusi sebelum penggunaan pertama:

```bash
chmod +x backup.sh
```

---

## 🛠️ Konfigurasi (`backup.conf`)

```bash
SOURCE="/home/mahasiswa/data-penting"
DEST="/home/mahasiswa/backup"
RETENTION=3
EXCLUDE="*.tmp draft"
CRON="0 2 * * *"
```

| Variabel | Keterangan |
| :--- | :--- |
| `SOURCE` | Direktori sumber yang akan dicadangkan. Wajib tersedia saat backup dijalankan. |
| `DEST` | Direktori tujuan arsip dan `backup.log`. Dibuat otomatis jika belum ada. |
| `RETENTION` | Jumlah maksimal arsip terbaru yang dipertahankan (bilangan bulat minimal `1`). |
| `EXCLUDE` | Pola berkas atau folder yang dikecualikan, dipisahkan spasi. Boleh dikosongkan. |
| `CRON` | Jadwal eksekusi otomatis dalam format 5 kolom `crontab`. |

---

## 🚀 Cara Penggunaan

### 1. Mode Interaktif (Menu Terminal)

Jalankan script tanpa argumen apa pun untuk masuk ke menu berbasis teks:

```bash
./backup.sh
```

| Pilihan | Aksi |
| :---: | :--- |
| `1` | Backup sekarang |
| `2` | List arsip di `DEST` |
| `3` | Restore arsip ke `DEST/restore/` |
| `4` | Pasang jadwal cron |
| `5` | Hapus jadwal cron |
| `6` | Verifikasi checksum SHA-256 *(Bonus)* |
| `7` | Simulasi dry-run backup *(Bonus)* |
| `8` | Statistik ukuran backup *(Bonus)* |
| `0` | Keluar |

### 2. Mode Argumen (CLI)

| Opsi | Fungsi |
| :--- | :--- |
| `-h` | Menampilkan panduan penggunaan dan keluar dengan status `0`. |
| `-c FILE` | Menggunakan file konfigurasi tertentu (default: `backup.conf` di folder script). |
| `-s SRC` | Menimpa nilai `SOURCE` dari file konfigurasi. |
| `-d DEST` | Menimpa nilai `DEST` dari file konfigurasi. |
| `-l` | Menampilkan daftar nama dan ukuran arsip di `DEST`. |
| `-r ARSIP` | Memulihkan isi `ARSIP` ke folder `DEST/restore/`. |
| `-i` | Memasang baris `crontab` secara idempoten (tidak menduplikasi entri). |
| `-U` | Menghapus baris `crontab` milik script ini tanpa mengubah jadwal lain. |

```bash
# Menampilkan bantuan
./backup.sh -h

# Menjalankan backup dengan konfigurasi tertentu
./backup.sh -c backup.conf

# Menjalankan backup dengan override sumber dan tujuan
./backup.sh -s /path/sumber -d /path/tujuan

# Melihat daftar arsip beserta ukurannya
./backup.sh -l

# Restore arsip ke DEST/restore/
./backup.sh -r backup_20261115-120000.tar.gz

# Memasang dan menghapus penjadwalan cron
./backup.sh -i
./backup.sh -U
```

> [!TIP]
> Opsi data (`-c`, `-s`, `-d`) dapat dikombinasikan dengan opsi aksi seperti `./backup.sh -l -d /tmp/dest` atau `./backup.sh -r arsip.tar.gz -d /tmp/dest`.

---

## ✨ Fitur Tambahan (Bonus)

| Fitur | Opsi | Ringkasan |
| :--- | :---: | :--- |
| **Checksum SHA-256** | `-v ARSIP` | Membuat file `.sha256` otomatis per arsip, ikut dihapus saat retensi, diverifikasi saat restore, dan bisa dicek manual. |
| **Mode Dry-Run** | `-n` | Menampilkan daftar berkas yang akan diarsipkan serta prediksi retensi tanpa menulis arsip maupun log. |
| **Statistik Backup** | `-S` | Menampilkan jumlah arsip, total ukuran penyimpanan, rata-rata ukuran, dan arsip terbesar. |
| **Lock File Atomic** | Otomatis | Menggunakan `DEST/.backup.lock` dan `trap` untuk mencegah dua proses backup berjalan bersamaan pada `DEST` yang sama. |

```bash
./backup.sh -v backup_20261115-120000.tar.gz   # Verifikasi integritas & checksum arsip
./backup.sh -n                                 # Simulasi backup tanpa menulis file
./backup.sh -S                                 # Tampilkan statistik ukuran arsip
```

---

## 📝 Format Log & Kode Keluar

Setiap aktivitas dicatat ke `$DEST/backup.log`:

```text
YYYY-MM-DD HH:MM:SS | nama_arsip | STATUS | keterangan
```

Status log yang digunakan: `SUKSES`, `GAGAL`, `HAPUS`, `RESTORE OK`, dan `RESTORE GAGAL`.

| Kode Keluar | Arti |
| :---: | :--- |
| `0` | Operasi berhasil (`EXIT_OK`) |
| `2` | Argumen CLI tidak valid (`EXIT_ERR_USAGE`) |
| `3` | File atau isi konfigurasi tidak valid (`EXIT_ERR_CONFIG`) |
| `4` | Direktori `SOURCE` tidak ditemukan (`EXIT_ERR_SOURCE`) |
| `5` | Pembuatan atau validasi arsip gagal (`EXIT_ERR_BACKUP`) |
| `6` | Proses restore gagal (`EXIT_ERR_RESTORE`) |
| `7` | Pembaruan `crontab` gagal (`EXIT_ERR_CRON`) |
| `8` | Proses backup lain sedang memegang lock (`EXIT_ERR_LOCK`) |
| `9` | Verifikasi checksum atau arsip gagal (`EXIT_ERR_VERIFY`) |

---

## 🧪 Pengujian

```bash
shellcheck backup.sh
./check-sample.sh /path/ke/folder-proyek
```
