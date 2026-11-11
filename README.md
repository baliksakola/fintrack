# FinTrack — Personal Finance Manager

Aplikasi Android pengelolaan keuangan pribadi dengan pendekatan **local-first**.

## Spesifikasi
- Flutter + Dart.
- SQLite melalui Drift.
- Single user, tanpa login dan tanpa backend.
- Data tersimpan lokal di perangkat.
- Sinkronisasi dan pemindahan data melalui backup/import manual (fitur backup lanjutan menyusul).
- Bahasa Indonesia, Rupiah (IDR).
- Light/Dark Mode mengikuti pengaturan sistem.

## Fitur yang sudah masuk source
- Dashboard saldo total.
- Tambah rekening dengan saldo awal.
- Pencatatan pemasukan.
- Pencatatan pengeluaran.
- Kategori pemasukan dan pengeluaran.
- Pencarian transaksi berdasarkan keterangan atau kategori.
- Filter riwayat berdasarkan jenis transaksi.
- Edit pemasukan/pengeluaran dan hapus transaksi dengan penyesuaian saldo.
- Transfer antar-rekening.
- Anggaran bulanan per kategori dengan indikator penggunaan dan peringatan batas.
- Pencatatan tagihan dengan tanggal jatuh tempo dan status pembayaran.
- Tagihan bulanan berulang dibuat otomatis setelah pembayaran.
- Backup seluruh data ke file terenkripsi AES-256-GCM dengan kata sandi.
- Pemulihan backup terenkripsi dengan validasi integritas file dan kata sandi.
- Pembayaran tagihan otomatis dicatat sebagai transaksi pengeluaran dan mengurangi saldo rekening.
- Laporan pemasukan/pengeluaran, grafik 7 hari, dan rekap kategori.
- Ledger untuk menghitung saldo rekening.
- Test dasar untuk pemasukan, pengeluaran, transfer, dan validasi nominal.

## Menjalankan di komputer
Pastikan Flutter SDK stable dan Android SDK sudah terpasang.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run
```

## Build APK melalui GitHub Actions
Setiap push ke `main` menjalankan workflow Android CI:
1. Menyiapkan Flutter.
2. Membuat folder platform Android bila belum tersedia.
3. Mengambil dependency.
4. Menghasilkan kode Drift.
5. Menjalankan analyzer dan test.
6. Membuat APK release.
7. Mengunggah APK sebagai artifact `fintrack-apk`.

Unduh APK dari tab **Actions**, pilih workflow yang berhasil, lalu ambil artifact `fintrack-apk`.

## Struktur
```
lib/
  core/database/       # Drift tables dan database
  features/dashboard/  # Dashboard dan input transaksi
test/                  # Pengujian ledger
.github/workflows/     # Android CI
```

## Catatan pengembangan
Source saat ini adalah implementasi inti tahap awal. Fitur biaya transfer, notifikasi push jatuh tempo, cicilan, utang/piutang, aset, kalender, backup terenkripsi dan sinkronisasi cloud masih masuk roadmap dan tidak boleh dianggap tersedia sebelum diimplementasikan serta diuji.
