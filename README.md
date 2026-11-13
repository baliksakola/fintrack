# FinTrack — Personal Finance Manager

FinTrack adalah aplikasi Android pengelolaan keuangan pribadi dengan pendekatan **local-first**. Aplikasi dirancang untuk pencatatan keuangan satu pengguna tanpa akun dan tanpa backend.

## Teknologi

- Flutter dan Dart.
- SQLite melalui Drift.
- Penyimpanan data utama di perangkat.
- Bahasa Indonesia dan mata uang Rupiah (IDR).
- Tema terang dan gelap.
- Versi aplikasi saat ini: `0.2.0+2`.

## Fitur

- Dashboard saldo dan ringkasan keuangan.
- Pengelolaan rekening dan saldo awal.
- Pencatatan pemasukan, pengeluaran, dan transfer.
- Kategori transaksi, pencarian, filter, edit, dan hapus transaksi.
- Anggaran bulanan per kategori.
- Tagihan, pengingat jatuh tempo, dan pencatatan pembayaran.
- Utang dan piutang dengan pembayaran bertahap.
- Tujuan keuangan dan kontribusi.
- Transaksi berulang.
- Kalender aktivitas keuangan.
- Laporan berdasarkan periode dan rentang tanggal.
- Ekspor laporan ke Excel (.xlsx) dan PDF.
- Backup data terenkripsi AES-256-GCM dengan kata sandi dan pemulihan backup.
- Kunci aplikasi dengan PIN serta autentikasi biometrik jika didukung perangkat.

## Privasi dan penyimpanan data

- Data keuangan utama disimpan secara lokal pada perangkat.
- Aplikasi tidak memerlukan akun pengguna atau server backend.
- Backup yang diekspor merupakan file terpisah dan dilindungi kata sandi.
- Pengguna bertanggung jawab menjaga keamanan perangkat, PIN, kata sandi backup, dan salinan backup.
- Menghapus aplikasi atau kehilangan perangkat dapat menyebabkan hilangnya data lokal jika pengguna belum memiliki backup yang dapat dipulihkan.

Jangan menyimpan file backup atau kata sandi backup di tempat yang dapat diakses pihak lain.

## Menjalankan proyek

Persyaratan: Flutter SDK stable dan Android SDK yang sesuai.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run
```

## Android CI

Workflow GitHub Actions berada di `.github/workflows/android.yml`. Workflow saat ini:

1. Menyiapkan Flutter.
2. Membuat platform Android saat folder `android/` belum tersedia.
3. Mengatur compile SDK dan konfigurasi notifikasi Android.
4. Mengambil dependency dan menghasilkan kode Drift.
5. Menjalankan `flutter analyze` dan `flutter test`.
6. Membuat APK release.
7. Mengunggah artifact bernama `fintrack-apk`.

Artifact dapat diunduh dari tab **Actions** pada workflow yang berhasil.

## Catatan distribusi

Build APK dari workflow CI ditujukan untuk pengujian dan distribusi terbatas. Sebelum rilis publik atau publikasi ke Google Play, proyek harus memiliki konfigurasi signing release dengan keystore milik pemilik aplikasi yang disimpan secara aman melalui GitHub Actions Secrets. Jangan pernah memasukkan keystore, kata sandi, atau kunci privat ke repository.

Untuk distribusi Google Play, siapkan dan uji Android App Bundle (AAB), identitas aplikasi yang permanen, ikon aplikasi, kebijakan privasi, serta metadata listing. Jangan menganggap APK CI sebagai paket Google Play yang sudah siap rilis.

## Pengujian

Jalankan pemeriksaan berikut sebelum menggabungkan perubahan:

```bash
flutter analyze
flutter test
flutter build apk --release
```

Pengujian otomatis tidak menggantikan pengujian pada perangkat Android fisik.

## Struktur proyek

```
lib/
  core/
    backup/
    database/
    notifications/
    security/
  features/
    dashboard/
test/
.github/workflows/
``

