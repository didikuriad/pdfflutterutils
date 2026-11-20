# PDF Utils (Flutter Desktop)

Aplikasi desktop berbasis Flutter untuk manipulasi, konversi, dan pengeditan dokumen PDF secara lokal di Windows.

## Fitur Utama

1. **Gabung PDF (Merge)**
   - Menggabungkan beberapa file PDF sesuai urutan (drag-and-drop urutan file) dengan dukungan pemilihan rentang halaman per file (mis. `1-3, 5`).
2. **Putar PDF (Rotate)**
   - Memutar halaman tertentu, halaman ganjil/genap, atau seluruh dokumen (`+90°`, `-90°`, `180°`) secara *lossless* lengkap dengan pratinjau thumbnail halaman.
3. **Pisah PDF (Split)**
   - Memisahkan PDF berdasarkan rentang kustom, setiap halaman menjadi 1 file, atau per *N* halaman.
4. **PDF ke DOCX (Otomasi Microsoft Word COM)**
   - Mengonversi 1 atau banyak file PDF (batch) menjadi dokumen `.docx` menggunakan otomasi Microsoft Word COM via PowerShell di Windows dengan kualitas tata letak terbaik.
5. **Edit PDF Langsung (Overlay, Anotasi & Whiteout)**
   - Menambahkan **Teks** (lengkap dengan opsi tebal, ukuran font, warna, dan **Latar Putih** untuk menimpa teks lama), **Whiteout**, **Highlight**, **Pena** (coretan bebas), **Kotak**, **Tanda Tangan** (pad tanda tangan vektor), dan **Gambar** (PNG/JPG/WebP/BMP) langsung ke halaman PDF secara *lossless* menggunakan PDFium FFI (`pdfrx` + `pdfium_dart`), dilengkapi **Undo/Redo** dan **Zoom**.
6. **Mode Tampilan & System Tray**
   - **Mode Desktop** (`1280 x 800`) dan **Mode Kecil (HP)** (`412 x 780`).
   - **Auto-Hide** 5 detik saat pertama kali dijalankan ke ikon *hidden icons* (system tray) Windows, dapat dimunculkan kembali dari tray tanpa auto-hide, serta tombol **Auto Hide** di dalam aplikasi.

## Menjalankan & Membangun Aplikasi

```bash
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

Hasil build release Windows terletak pada:
`build\windows\x64\runner\Release\pdfutils.exe`
