-- ============================================
-- DATABASE: db_kas  (KasPro - Sistem Manajemen Kas)
-- Jalankan seluruh skrip ini di MySQL 8.x
--   mysql -u root -p < database/db_kas.sql
-- atau buka di MySQL Workbench lalu Run.
-- ============================================

CREATE DATABASE IF NOT EXISTS db_kas
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE db_kas;

-- Bersihkan jika ada (urutan memperhatikan foreign key)
DROP TRIGGER IF EXISTS trg_update_rekap;
DROP TABLE IF EXISTS notifikasi;
DROP TABLE IF EXISTS rekap_kas;
DROP TABLE IF EXISTS pembayaran;
DROP TABLE IF EXISTS tagihan;
DROP TABLE IF EXISTS periode_kas;
DROP TABLE IF EXISTS users;

-- --------------------------------------------
-- TABEL: users
-- --------------------------------------------
CREATE TABLE users (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL UNIQUE,
    password      VARCHAR(255) NOT NULL,
    nama_lengkap  VARCHAR(100) NOT NULL,
    email         VARCHAR(100),
    no_hp         VARCHAR(20),
    role          ENUM('admin','bendahara','anggota') NOT NULL DEFAULT 'anggota',
    no_anggota    VARCHAR(30) UNIQUE,
    aktif         TINYINT(1) DEFAULT 1,
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------
-- TABEL: periode_kas
-- --------------------------------------------
CREATE TABLE periode_kas (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    nama_periode  VARCHAR(100) NOT NULL,
    nominal       DECIMAL(12,2) NOT NULL,
    tanggal_mulai DATE NOT NULL,
    tanggal_jatuh_tempo DATE NOT NULL,
    deskripsi     TEXT,
    status        ENUM('aktif','tutup') DEFAULT 'aktif',
    dibuat_oleh   INT,
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (dibuat_oleh) REFERENCES users(id) ON DELETE SET NULL
);

-- --------------------------------------------
-- TABEL: tagihan
-- --------------------------------------------
CREATE TABLE tagihan (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    id_periode    INT NOT NULL,
    id_anggota    INT NOT NULL,
    nominal       DECIMAL(12,2) NOT NULL,
    status        ENUM('belum_bayar','menunggu_verifikasi','lunas','ditolak')
                  DEFAULT 'belum_bayar',
    catatan       TEXT,
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (id_periode)  REFERENCES periode_kas(id) ON DELETE CASCADE,
    FOREIGN KEY (id_anggota)  REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY uq_tagihan (id_periode, id_anggota)
);

-- --------------------------------------------
-- TABEL: pembayaran
-- --------------------------------------------
CREATE TABLE pembayaran (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    id_tagihan      INT NOT NULL UNIQUE,
    id_anggota      INT NOT NULL,
    nominal_bayar   DECIMAL(12,2) NOT NULL,
    metode          ENUM('transfer_bank','dompet_digital','tunai','lainnya')
                    NOT NULL DEFAULT 'transfer_bank',
    nama_bank       VARCHAR(50),
    no_referensi    VARCHAR(100),
    path_bukti      VARCHAR(500),
    nama_file_bukti VARCHAR(255),
    catatan_anggota TEXT,
    status          ENUM('menunggu','disetujui','ditolak') DEFAULT 'menunggu',
    diperiksa_oleh  INT,
    catatan_penolakan TEXT,
    dikirim_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    diverifikasi_at DATETIME,
    FOREIGN KEY (id_tagihan)     REFERENCES tagihan(id)   ON DELETE CASCADE,
    FOREIGN KEY (id_anggota)     REFERENCES users(id)     ON DELETE CASCADE,
    FOREIGN KEY (diperiksa_oleh) REFERENCES users(id)     ON DELETE SET NULL
);

-- --------------------------------------------
-- TABEL: rekap_kas
-- --------------------------------------------
CREATE TABLE rekap_kas (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    id_periode    INT NOT NULL,
    total_tagihan DECIMAL(14,2) DEFAULT 0,
    total_terkumpul DECIMAL(14,2) DEFAULT 0,
    jumlah_lunas  INT DEFAULT 0,
    jumlah_belum  INT DEFAULT 0,
    updated_at    DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (id_periode) REFERENCES periode_kas(id) ON DELETE CASCADE
);

-- --------------------------------------------
-- TABEL: notifikasi
-- --------------------------------------------
CREATE TABLE notifikasi (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    id_penerima   INT NOT NULL,
    pesan         TEXT NOT NULL,
    tipe          ENUM('pembayaran_masuk','disetujui','ditolak','tagihan_baru','pengingat')
                  DEFAULT 'tagihan_baru',
    id_referensi  INT,
    sudah_dibaca  TINYINT(1) DEFAULT 0,
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_penerima) REFERENCES users(id) ON DELETE CASCADE
);

-- ============================================
-- TRIGGER: update rekap setelah pembayaran disetujui
-- ============================================
DELIMITER $$

CREATE TRIGGER trg_update_rekap
AFTER UPDATE ON pembayaran
FOR EACH ROW
BEGIN
    DECLARE v_id_periode INT;

    IF NEW.status = 'disetujui' AND OLD.status <> 'disetujui' THEN
        SELECT id_periode INTO v_id_periode
        FROM tagihan WHERE id = NEW.id_tagihan;

        UPDATE rekap_kas
        SET total_terkumpul = total_terkumpul + NEW.nominal_bayar,
            jumlah_lunas    = jumlah_lunas + 1,
            jumlah_belum    = GREATEST(jumlah_belum - 1, 0),
            updated_at      = NOW()
        WHERE id_periode = v_id_periode;
    END IF;
END$$

DELIMITER ;

-- ============================================
-- DATA AWAL (SEEDER)
-- Password disimpan sebagai SHA-256 hex (cocok dengan PasswordUtil.hash di Java)
-- ============================================

INSERT INTO users (username, password, nama_lengkap, role) VALUES
('admin',     SHA2('admin123', 256), 'Administrator',   'admin'),
('bendahara', SHA2('kas12345', 256), 'Bendahara Utama', 'bendahara');

INSERT INTO users (username, password, nama_lengkap, role, no_anggota) VALUES
('budi',  SHA2('budi123', 256),  'Budi Santoso',   'anggota', 'A001'),
('rina',  SHA2('rina123', 256),  'Rina Kusuma',    'anggota', 'A002'),
('deni',  SHA2('deni123', 256),  'Deni Pratama',   'anggota', 'A003');

-- ============================================
-- (OPSIONAL) Contoh periode + tagihan agar dasbor langsung berisi data.
-- Hapus blok di bawah bila ingin mulai dari kosong.
-- ============================================
INSERT INTO periode_kas (nama_periode, nominal, tanggal_mulai, tanggal_jatuh_tempo, deskripsi, dibuat_oleh)
VALUES ('Kas Bulanan - Contoh', 50000, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 7 DAY),
        'Periode contoh hasil seeder', 2);

SET @pid = LAST_INSERT_ID();

INSERT INTO tagihan (id_periode, id_anggota, nominal)
SELECT @pid, id, 50000 FROM users WHERE role = 'anggota' AND aktif = 1;

INSERT INTO rekap_kas (id_periode, total_tagihan, total_terkumpul, jumlah_lunas, jumlah_belum)
SELECT @pid,
       50000 * (SELECT COUNT(*) FROM users WHERE role='anggota' AND aktif=1),
       0, 0,
       (SELECT COUNT(*) FROM users WHERE role='anggota' AND aktif=1);

INSERT INTO notifikasi (id_penerima, pesan, tipe, id_referensi)
SELECT id, 'Tagihan baru: Kas Bulanan - Contoh sebesar 50000. Silakan lakukan pembayaran.',
       'tagihan_baru', @pid
FROM users WHERE role='anggota' AND aktif=1;
