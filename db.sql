CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TYPE user_role AS ENUM ('admin', 'dosen_wali', 'mahasiswa');

CREATE TYPE status_akademik AS ENUM (
  'aktif',
  'cuti',
  'mengundurkan_diri',
  'drop_out',
  'lulus'
);

CREATE TYPE tipe_semester AS ENUM ('ganjil', 'genap', 'pendek');

CREATE TYPE jenis_matkul AS ENUM ('wajib', 'pilihan', 'praktikum');

CREATE TYPE grade_nilai AS ENUM ('A', 'AB', 'B', 'BC', 'C', 'D', 'E');

CREATE TYPE tipe_alert AS ENUM (
  'nilai_rendah',
  'kehadiran_buruk',
  'ipk_turun',
  'sks_tidak_cukup',
  'belum_konsultasi'
);

CREATE TYPE status_alert AS ENUM ('aktif', 'diproses', 'selesai', 'diabaikan');

CREATE TYPE status_notif AS ENUM ('belum_dibaca', 'sudah_dibaca');

CREATE TYPE tipe_notif AS ENUM ('alert', 'pengingat', 'info', 'jadwal');

CREATE TYPE status_catatan AS ENUM ('draft', 'final');

CREATE TYPE status_jadwal AS ENUM ('menunggu', 'dikonfirmasi', 'selesai', 'dibatalkan');

CREATE TABLE IF NOT EXISTS public.users (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT NOT NULL UNIQUE,
  full_name   TEXT NOT NULL,
  avatar_url  TEXT,
  role        user_role NOT NULL DEFAULT 'mahasiswa',
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.dosen_wali (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  nip           TEXT NOT NULL UNIQUE,
  nama_lengkap  TEXT NOT NULL,
  gelar_depan   TEXT,
  gelar_belakang TEXT,
  prodi         TEXT NOT NULL,
  jurusan       TEXT NOT NULL DEFAULT 'Teknik Informatika',
  no_hp         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.mahasiswa (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  dosen_wali_id   UUID REFERENCES public.dosen_wali(id) ON DELETE SET NULL,
  nrp             TEXT NOT NULL UNIQUE,
  nama_lengkap    TEXT NOT NULL,
  kelas           TEXT NOT NULL,
  prodi           TEXT NOT NULL,
  jurusan         TEXT NOT NULL DEFAULT 'Teknik Informatika',
  angkatan        INT NOT NULL CHECK (angkatan >= 2000 AND angkatan <= 2100),
  status_akademik status_akademik NOT NULL DEFAULT 'aktif',
  no_hp           TEXT,
  alamat          TEXT,
  tanggal_lahir   DATE,
  tempat_lahir    TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.semester (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  kode            TEXT NOT NULL UNIQUE,
  nama            TEXT NOT NULL,
  tahun_akademik  TEXT NOT NULL,
  tipe            tipe_semester NOT NULL,
  tanggal_mulai   DATE NOT NULL,
  tanggal_selesai DATE NOT NULL,
  is_aktif        BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_semester_tanggal CHECK (tanggal_selesai > tanggal_mulai)
);


CREATE TABLE IF NOT EXISTS public.mata_kuliah (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  kode        TEXT NOT NULL UNIQUE,
  nama        TEXT NOT NULL,
  sks         INT NOT NULL CHECK (sks > 0 AND sks <= 6),
  prodi       TEXT NOT NULL,
  jurusan     TEXT NOT NULL DEFAULT 'Teknik Informatika',
  jenis       jenis_matkul NOT NULL DEFAULT 'wajib',
  deskripsi   TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


CREATE TABLE IF NOT EXISTS public.nilai_mahasiswa (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  mahasiswa_id    UUID NOT NULL REFERENCES public.mahasiswa(id) ON DELETE CASCADE,
  semester_id     UUID NOT NULL REFERENCES public.semester(id) ON DELETE RESTRICT,
  mata_kuliah_id  UUID NOT NULL REFERENCES public.mata_kuliah(id) ON DELETE RESTRICT,
  nilai_tugas     NUMERIC(5,2) CHECK (nilai_tugas >= 0 AND nilai_tugas <= 100),
  nilai_uts       NUMERIC(5,2) CHECK (nilai_uts >= 0 AND nilai_uts <= 100),
  nilai_uas       NUMERIC(5,2) CHECK (nilai_uas >= 0 AND nilai_uas <= 100),
  nilai_akhir     NUMERIC(5,2) GENERATED ALWAYS AS (
                    ROUND(
                      COALESCE(nilai_tugas, 0) * 0.30 +
                      COALESCE(nilai_uts, 0)   * 0.35 +
                      COALESCE(nilai_uas, 0)   * 0.35,
                      2
                    )
                  ) STORED,
  grade           grade_nilai,
  bobot_nilai     NUMERIC(3,2) CHECK (bobot_nilai >= 0 AND bobot_nilai <= 4),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (mahasiswa_id, semester_id, mata_kuliah_id)
);


CREATE TABLE IF NOT EXISTS public.kehadiran (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  mahasiswa_id          UUID NOT NULL REFERENCES public.mahasiswa(id) ON DELETE CASCADE,
  semester_id           UUID NOT NULL REFERENCES public.semester(id) ON DELETE RESTRICT,
  mata_kuliah_id        UUID NOT NULL REFERENCES public.mata_kuliah(id) ON DELETE RESTRICT,
  total_pertemuan       INT NOT NULL DEFAULT 0 CHECK (total_pertemuan >= 0),
  hadir                 INT NOT NULL DEFAULT 0 CHECK (hadir >= 0),
  izin                  INT NOT NULL DEFAULT 0 CHECK (izin >= 0),
  sakit                 INT NOT NULL DEFAULT 0 CHECK (sakit >= 0),
  alpha                 INT NOT NULL DEFAULT 0 CHECK (alpha >= 0),
  persentase_kehadiran  NUMERIC(5,2) GENERATED ALWAYS AS (
                          CASE
                            WHEN total_pertemuan = 0 THEN 0
                            ELSE ROUND((hadir::NUMERIC / total_pertemuan) * 100, 2)
                          END
                        ) STORED,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (mahasiswa_id, semester_id, mata_kuliah_id),
  CONSTRAINT chk_kehadiran_total CHECK (
    hadir + izin + sakit + alpha <= total_pertemuan
  )
);


CREATE TABLE IF NOT EXISTS public.ipk_history (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  mahasiswa_id    UUID NOT NULL REFERENCES public.mahasiswa(id) ON DELETE CASCADE,
  semester_id     UUID NOT NULL REFERENCES public.semester(id) ON DELETE RESTRICT,
  ips             NUMERIC(4,2) NOT NULL CHECK (ips >= 0 AND ips <= 4),
  ipk_kumulatif   NUMERIC(4,2) NOT NULL CHECK (ipk_kumulatif >= 0 AND ipk_kumulatif <= 4),
  sks_semester    INT NOT NULL CHECK (sks_semester >= 0),
  sks_kumulatif   INT NOT NULL CHECK (sks_kumulatif >= 0),
  sks_lulus       INT NOT NULL DEFAULT 0 CHECK (sks_lulus >= 0),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (mahasiswa_id, semester_id)
);


CREATE TABLE IF NOT EXISTS public.catatan_perwalian (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  mahasiswa_id    UUID NOT NULL REFERENCES public.mahasiswa(id) ON DELETE CASCADE,
  dosen_wali_id   UUID NOT NULL REFERENCES public.dosen_wali(id) ON DELETE RESTRICT,
  semester_id     UUID NOT NULL REFERENCES public.semester(id) ON DELETE RESTRICT,
  judul           TEXT NOT NULL,
  isi_catatan     TEXT NOT NULL,
  tindak_lanjut   TEXT,
  status          status_catatan NOT NULL DEFAULT 'draft',
  tanggal         DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


CREATE TABLE IF NOT EXISTS public.alert_akademik (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  mahasiswa_id    UUID NOT NULL REFERENCES public.mahasiswa(id) ON DELETE CASCADE,
  semester_id     UUID NOT NULL REFERENCES public.semester(id) ON DELETE RESTRICT,
  tipe_alert      tipe_alert NOT NULL,
  deskripsi       TEXT NOT NULL,
  status          status_alert NOT NULL DEFAULT 'aktif',
  threshold_value NUMERIC(8,2),
  actual_value    NUMERIC(8,2),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at     TIMESTAMPTZ,
  resolved_by     UUID REFERENCES public.users(id) ON DELETE SET NULL
);


CREATE TABLE IF NOT EXISTS public.notifikasi (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  mahasiswa_id  UUID REFERENCES public.mahasiswa(id) ON DELETE CASCADE,
  alert_id      UUID REFERENCES public.alert_akademik(id) ON DELETE SET NULL,
  judul         TEXT NOT NULL,
  pesan         TEXT NOT NULL,
  tipe          tipe_notif NOT NULL DEFAULT 'info',
  status        status_notif NOT NULL DEFAULT 'belum_dibaca',
  link_target   TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  dibaca_at     TIMESTAMPTZ
);


CREATE TABLE IF NOT EXISTS public.jadwal_konsultasi (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  mahasiswa_id    UUID NOT NULL REFERENCES public.mahasiswa(id) ON DELETE CASCADE,
  dosen_wali_id   UUID NOT NULL REFERENCES public.dosen_wali(id) ON DELETE RESTRICT,
  semester_id     UUID REFERENCES public.semester(id) ON DELETE SET NULL,
  waktu_mulai     TIMESTAMPTZ NOT NULL,
  waktu_selesai   TIMESTAMPTZ NOT NULL,
  status          status_jadwal NOT NULL DEFAULT 'menunggu',
  catatan         TEXT,
  lokasi          TEXT,
  dibuat_oleh     UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_jadwal_waktu CHECK (waktu_selesai > waktu_mulai)
);


CREATE TABLE IF NOT EXISTS public.konfigurasi_alert (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tipe_alert      tipe_alert NOT NULL UNIQUE,
  nama            TEXT NOT NULL,
  deskripsi       TEXT,
  threshold_value NUMERIC(8,2) NOT NULL,
  is_aktif        BOOLEAN NOT NULL DEFAULT TRUE,
  updated_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.konfigurasi_alert (tipe_alert, nama, deskripsi, threshold_value) VALUES
  ('nilai_rendah',       'Nilai Rendah',          'Alert jika nilai akhir matkul di bawah threshold', 60.00),
  ('kehadiran_buruk',    'Kehadiran Buruk',        'Alert jika persentase kehadiran di bawah threshold', 75.00),
  ('ipk_turun',          'IPK Menurun',            'Alert jika IPK turun lebih dari threshold poin', 0.50),
  ('sks_tidak_cukup',    'SKS Tidak Cukup',        'Alert jika SKS diambil di bawah threshold per semester', 12),
  ('belum_konsultasi',   'Belum Konsultasi',       'Alert jika belum ada catatan perwalian dalam N hari', 60);


CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);

CREATE INDEX IF NOT EXISTS idx_mahasiswa_dosen_wali ON public.mahasiswa(dosen_wali_id);
CREATE INDEX IF NOT EXISTS idx_mahasiswa_nrp ON public.mahasiswa(nrp);
CREATE INDEX IF NOT EXISTS idx_mahasiswa_status ON public.mahasiswa(status_akademik);
CREATE INDEX IF NOT EXISTS idx_mahasiswa_angkatan ON public.mahasiswa(angkatan);
CREATE INDEX IF NOT EXISTS idx_mahasiswa_prodi ON public.mahasiswa(prodi);

CREATE INDEX IF NOT EXISTS idx_nilai_mahasiswa ON public.nilai_mahasiswa(mahasiswa_id);
CREATE INDEX IF NOT EXISTS idx_nilai_semester ON public.nilai_mahasiswa(semester_id);
CREATE INDEX IF NOT EXISTS idx_nilai_matkul ON public.nilai_mahasiswa(mata_kuliah_id);
CREATE INDEX IF NOT EXISTS idx_nilai_grade ON public.nilai_mahasiswa(grade);

CREATE INDEX IF NOT EXISTS idx_kehadiran_mahasiswa ON public.kehadiran(mahasiswa_id);
CREATE INDEX IF NOT EXISTS idx_kehadiran_semester ON public.kehadiran(semester_id);
CREATE INDEX IF NOT EXISTS idx_kehadiran_persen ON public.kehadiran(persentase_kehadiran);

CREATE INDEX IF NOT EXISTS idx_ipk_mahasiswa ON public.ipk_history(mahasiswa_id);
CREATE INDEX IF NOT EXISTS idx_ipk_semester ON public.ipk_history(semester_id);

CREATE INDEX IF NOT EXISTS idx_alert_mahasiswa ON public.alert_akademik(mahasiswa_id);
CREATE INDEX IF NOT EXISTS idx_alert_status ON public.alert_akademik(status);
CREATE INDEX IF NOT EXISTS idx_alert_tipe ON public.alert_akademik(tipe_alert);

CREATE INDEX IF NOT EXISTS idx_notif_user ON public.notifikasi(user_id);
CREATE INDEX IF NOT EXISTS idx_notif_status ON public.notifikasi(status);
CREATE INDEX IF NOT EXISTS idx_notif_created ON public.notifikasi(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_catatan_mahasiswa ON public.catatan_perwalian(mahasiswa_id);
CREATE INDEX IF NOT EXISTS idx_catatan_dosen ON public.catatan_perwalian(dosen_wali_id);
CREATE INDEX IF NOT EXISTS idx_catatan_semester ON public.catatan_perwalian(semester_id);

CREATE INDEX IF NOT EXISTS idx_jadwal_mahasiswa ON public.jadwal_konsultasi(mahasiswa_id);
CREATE INDEX IF NOT EXISTS idx_jadwal_dosen ON public.jadwal_konsultasi(dosen_wali_id);
CREATE INDEX IF NOT EXISTS idx_jadwal_waktu ON public.jadwal_konsultasi(waktu_mulai);
CREATE INDEX IF NOT EXISTS idx_jadwal_status ON public.jadwal_konsultasi(status);


CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_dosen_wali_updated_at
  BEFORE UPDATE ON public.dosen_wali
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_mahasiswa_updated_at
  BEFORE UPDATE ON public.mahasiswa
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_mata_kuliah_updated_at
  BEFORE UPDATE ON public.mata_kuliah
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_nilai_updated_at
  BEFORE UPDATE ON public.nilai_mahasiswa
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_catatan_updated_at
  BEFORE UPDATE ON public.catatan_perwalian
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_jadwal_updated_at
  BEFORE UPDATE ON public.jadwal_konsultasi
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


CREATE OR REPLACE FUNCTION public.set_grade_bobot()
RETURNS TRIGGER AS $$
BEGIN
  DECLARE
    na NUMERIC := ROUND(
      COALESCE(NEW.nilai_tugas, 0) * 0.30 +
      COALESCE(NEW.nilai_uts, 0)   * 0.35 +
      COALESCE(NEW.nilai_uas, 0)   * 0.35,
      2
    );
  BEGIN
    IF na >= 87 THEN
      NEW.grade := 'A';  NEW.bobot_nilai := 4.00;
    ELSIF na >= 78 THEN
      NEW.grade := 'AB'; NEW.bobot_nilai := 3.50;
    ELSIF na >= 69 THEN
      NEW.grade := 'B';  NEW.bobot_nilai := 3.00;
    ELSIF na >= 60 THEN
      NEW.grade := 'BC'; NEW.bobot_nilai := 2.50;
    ELSIF na >= 51 THEN
      NEW.grade := 'C';  NEW.bobot_nilai := 2.00;
    ELSIF na >= 41 THEN
      NEW.grade := 'D';  NEW.bobot_nilai := 1.00;
    ELSE
      NEW.grade := 'E';  NEW.bobot_nilai := 0.00;
    END IF;
  END;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_grade_bobot
  BEFORE INSERT OR UPDATE ON public.nilai_mahasiswa
  FOR EACH ROW EXECUTE FUNCTION public.set_grade_bobot();


CREATE OR REPLACE FUNCTION public.check_alert_kehadiran()
RETURNS TRIGGER AS $$
DECLARE
  threshold NUMERIC;
BEGIN
  SELECT threshold_value INTO threshold
  FROM public.konfigurasi_alert
  WHERE tipe_alert = 'kehadiran_buruk' AND is_aktif = TRUE;

  IF threshold IS NOT NULL AND NEW.persentase_kehadiran < threshold THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.alert_akademik
      WHERE mahasiswa_id = NEW.mahasiswa_id
        AND semester_id = NEW.semester_id
        AND tipe_alert = 'kehadiran_buruk'
        AND status = 'aktif'
    ) THEN
      INSERT INTO public.alert_akademik
        (mahasiswa_id, semester_id, tipe_alert, deskripsi, threshold_value, actual_value)
      VALUES (
        NEW.mahasiswa_id,
        NEW.semester_id,
        'kehadiran_buruk',
        'Persentase kehadiran di bawah ' || threshold || '%',
        threshold,
        NEW.persentase_kehadiran
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_kehadiran_alert
  AFTER INSERT OR UPDATE ON public.kehadiran
  FOR EACH ROW EXECUTE FUNCTION public.check_alert_kehadiran();


CREATE OR REPLACE FUNCTION public.check_alert_nilai()
RETURNS TRIGGER AS $$
DECLARE
  threshold NUMERIC;
  na NUMERIC;
BEGIN
  SELECT threshold_value INTO threshold
  FROM public.konfigurasi_alert
  WHERE tipe_alert = 'nilai_rendah' AND is_aktif = TRUE;

  na := ROUND(
    COALESCE(NEW.nilai_tugas, 0) * 0.30 +
    COALESCE(NEW.nilai_uts, 0)   * 0.35 +
    COALESCE(NEW.nilai_uas, 0)   * 0.35,
    2
  );

  IF threshold IS NOT NULL AND na < threshold THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.alert_akademik
      WHERE mahasiswa_id = NEW.mahasiswa_id
        AND semester_id = NEW.semester_id
        AND tipe_alert = 'nilai_rendah'
        AND status = 'aktif'
    ) THEN
      INSERT INTO public.alert_akademik
        (mahasiswa_id, semester_id, tipe_alert, deskripsi, threshold_value, actual_value)
      VALUES (
        NEW.mahasiswa_id,
        NEW.semester_id,
        'nilai_rendah',
        'Terdapat nilai akhir matkul di bawah ' || threshold,
        threshold,
        na
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_nilai_alert
  AFTER INSERT OR UPDATE ON public.nilai_mahasiswa
  FOR EACH ROW EXECUTE FUNCTION public.check_alert_nilai();


CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'Pengguna Baru'),
    COALESCE(
      (NEW.raw_user_meta_data->>'role')::user_role,
      'mahasiswa'
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


CREATE OR REPLACE VIEW public.v_ringkasan_mahasiswa AS
SELECT
  m.id,
  m.nrp,
  m.nama_lengkap,
  m.kelas,
  m.prodi,
  m.angkatan,
  m.status_akademik,
  dw.nama_lengkap    AS dosen_wali_nama,
  ipk.ipk_kumulatif,
  ipk.ips            AS ips_terakhir,
  ipk.sks_kumulatif,
  ROUND(AVG(k.persentase_kehadiran), 2) AS avg_kehadiran,
  (
    SELECT COUNT(*) FROM public.alert_akademik aa
    WHERE aa.mahasiswa_id = m.id AND aa.status = 'aktif'
  ) AS jumlah_alert_aktif
FROM public.mahasiswa m
LEFT JOIN public.dosen_wali dw ON dw.id = m.dosen_wali_id
LEFT JOIN LATERAL (
  SELECT * FROM public.ipk_history
  WHERE mahasiswa_id = m.id
  ORDER BY created_at DESC LIMIT 1
) ipk ON TRUE
LEFT JOIN public.semester s ON s.is_aktif = TRUE
LEFT JOIN public.kehadiran k ON k.mahasiswa_id = m.id AND k.semester_id = s.id
GROUP BY m.id, m.nrp, m.nama_lengkap, m.kelas, m.prodi, m.angkatan,
         m.status_akademik, dw.nama_lengkap, ipk.ipk_kumulatif, ipk.ips, ipk.sks_kumulatif;


CREATE OR REPLACE VIEW public.v_nilai_per_semester AS
SELECT
  nm.mahasiswa_id,
  m.nama_lengkap,
  m.nrp,
  s.nama            AS semester,
  s.kode            AS kode_semester,
  mk.kode           AS kode_matkul,
  mk.nama           AS nama_matkul,
  mk.sks,
  nm.nilai_tugas,
  nm.nilai_uts,
  nm.nilai_uas,
  nm.nilai_akhir,
  nm.grade,
  nm.bobot_nilai
FROM public.nilai_mahasiswa nm
JOIN public.mahasiswa m      ON m.id = nm.mahasiswa_id
JOIN public.semester s       ON s.id = nm.semester_id
JOIN public.mata_kuliah mk   ON mk.id = nm.mata_kuliah_id;


CREATE OR REPLACE VIEW public.v_kehadiran_per_semester AS
SELECT
  k.mahasiswa_id,
  m.nama_lengkap,
  m.nrp,
  s.nama            AS semester,
  mk.nama           AS mata_kuliah,
  k.total_pertemuan,
  k.hadir,
  k.izin,
  k.sakit,
  k.alpha,
  k.persentase_kehadiran,
  CASE
    WHEN k.persentase_kehadiran >= 80 THEN 'aman'
    WHEN k.persentase_kehadiran >= 75 THEN 'peringatan'
    ELSE 'berbahaya'
  END AS status_kehadiran
FROM public.kehadiran k
JOIN public.mahasiswa m     ON m.id = k.mahasiswa_id
JOIN public.semester s      ON s.id = k.semester_id
JOIN public.mata_kuliah mk  ON mk.id = k.mata_kuliah_id;


CREATE OR REPLACE VIEW public.v_alert_aktif AS
SELECT
  aa.id,
  aa.tipe_alert,
  aa.deskripsi,
  aa.threshold_value,
  aa.actual_value,
  aa.created_at,
  m.id              AS mahasiswa_id,
  m.nrp,
  m.nama_lengkap,
  m.kelas,
  dw.nama_lengkap   AS dosen_wali_nama,
  dw.id             AS dosen_wali_id,
  s.nama            AS semester
FROM public.alert_akademik aa
JOIN public.mahasiswa m   ON m.id = aa.mahasiswa_id
JOIN public.semester s    ON s.id = aa.semester_id
LEFT JOIN public.dosen_wali dw ON dw.id = m.dosen_wali_id
WHERE aa.status = 'aktif';


ALTER TABLE public.users               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dosen_wali          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mahasiswa           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.semester            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mata_kuliah         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nilai_mahasiswa     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kehadiran           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ipk_history         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catatan_perwalian   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_akademik      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifikasi          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jadwal_konsultasi   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.konfigurasi_alert   ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS user_role AS $$
  SELECT role FROM public.users WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.get_current_dosen_wali_id()
RETURNS UUID AS $$
  SELECT id FROM public.dosen_wali WHERE user_id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.get_current_mahasiswa_id()
RETURNS UUID AS $$
  SELECT id FROM public.mahasiswa WHERE user_id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;


CREATE POLICY "users: lihat profil sendiri"
  ON public.users FOR SELECT
  USING (id = auth.uid());

CREATE POLICY "users: admin lihat semua"
  ON public.users FOR SELECT
  USING (public.get_current_user_role() = 'admin');

CREATE POLICY "users: update profil sendiri"
  ON public.users FOR UPDATE
  USING (id = auth.uid());


CREATE POLICY "mahasiswa: lihat data sendiri"
  ON public.mahasiswa FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "mahasiswa: dosen wali lihat binaan"
  ON public.mahasiswa FOR SELECT
  USING (
    dosen_wali_id = public.get_current_dosen_wali_id()
  );

CREATE POLICY "mahasiswa: admin full access"
  ON public.mahasiswa FOR ALL
  USING (public.get_current_user_role() = 'admin');


CREATE POLICY "nilai: mahasiswa lihat nilai sendiri"
  ON public.nilai_mahasiswa FOR SELECT
  USING (mahasiswa_id = public.get_current_mahasiswa_id());

CREATE POLICY "nilai: dosen wali lihat nilai binaan"
  ON public.nilai_mahasiswa FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.mahasiswa
      WHERE id = nilai_mahasiswa.mahasiswa_id
        AND dosen_wali_id = public.get_current_dosen_wali_id()
    )
  );

CREATE POLICY "nilai: admin full access"
  ON public.nilai_mahasiswa FOR ALL
  USING (public.get_current_user_role() = 'admin');


CREATE POLICY "kehadiran: mahasiswa lihat sendiri"
  ON public.kehadiran FOR SELECT
  USING (mahasiswa_id = public.get_current_mahasiswa_id());

CREATE POLICY "kehadiran: dosen wali lihat binaan"
  ON public.kehadiran FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.mahasiswa
      WHERE id = kehadiran.mahasiswa_id
        AND dosen_wali_id = public.get_current_dosen_wali_id()
    )
  );

CREATE POLICY "kehadiran: admin full access"
  ON public.kehadiran FOR ALL
  USING (public.get_current_user_role() = 'admin');


CREATE POLICY "notifikasi: user lihat milik sendiri"
  ON public.notifikasi FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "notifikasi: user update milik sendiri"
  ON public.notifikasi FOR UPDATE
  USING (user_id = auth.uid());


CREATE POLICY "catatan: dosen wali kelola catatan sendiri"
  ON public.catatan_perwalian FOR ALL
  USING (dosen_wali_id = public.get_current_dosen_wali_id());

CREATE POLICY "catatan: mahasiswa lihat catatan sendiri"
  ON public.catatan_perwalian FOR SELECT
  USING (mahasiswa_id = public.get_current_mahasiswa_id());

CREATE POLICY "catatan: admin full access"
  ON public.catatan_perwalian FOR ALL
  USING (public.get_current_user_role() = 'admin');


CREATE POLICY "alert: dosen wali lihat alert binaan"
  ON public.alert_akademik FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.mahasiswa
      WHERE id = alert_akademik.mahasiswa_id
        AND dosen_wali_id = public.get_current_dosen_wali_id()
    )
  );

CREATE POLICY "alert: mahasiswa lihat alert sendiri"
  ON public.alert_akademik FOR SELECT
  USING (mahasiswa_id = public.get_current_mahasiswa_id());

CREATE POLICY "alert: admin full access"
  ON public.alert_akademik FOR ALL
  USING (public.get_current_user_role() = 'admin');


CREATE POLICY "semester: semua bisa baca"
  ON public.semester FOR SELECT
  USING (TRUE);

CREATE POLICY "matkul: semua bisa baca"
  ON public.mata_kuliah FOR SELECT
  USING (TRUE);

CREATE POLICY "konfigurasi_alert: admin full access"
  ON public.konfigurasi_alert FOR ALL
  USING (public.get_current_user_role() = 'admin');

CREATE POLICY "konfigurasi_alert: semua bisa baca"
  ON public.konfigurasi_alert FOR SELECT
  USING (TRUE);


CREATE POLICY "jadwal: mahasiswa lihat jadwal sendiri"
  ON public.jadwal_konsultasi FOR SELECT
  USING (mahasiswa_id = public.get_current_mahasiswa_id());

CREATE POLICY "jadwal: dosen wali kelola jadwal sendiri"
  ON public.jadwal_konsultasi FOR ALL
  USING (dosen_wali_id = public.get_current_dosen_wali_id());

CREATE POLICY "jadwal: admin full access"
  ON public.jadwal_konsultasi FOR ALL
  USING (public.get_current_user_role() = 'admin');


CREATE POLICY "ipk: mahasiswa lihat sendiri"
  ON public.ipk_history FOR SELECT
  USING (mahasiswa_id = public.get_current_mahasiswa_id());

CREATE POLICY "ipk: dosen wali lihat binaan"
  ON public.ipk_history FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.mahasiswa
      WHERE id = ipk_history.mahasiswa_id
        AND dosen_wali_id = public.get_current_dosen_wali_id()
    )
  );

CREATE POLICY "ipk: admin full access"
  ON public.ipk_history FOR ALL
  USING (public.get_current_user_role() = 'admin');


INSERT INTO public.semester (kode, nama, tahun_akademik, tipe, tanggal_mulai, tanggal_selesai, is_aktif)
VALUES
  ('2025/2026-1', 'Semester Ganjil 2025/2026', '2025/2026', 'ganjil', '2025-09-01', '2026-01-31', FALSE),
  ('2025/2026-2', 'Semester Genap 2025/2026',  '2025/2026', 'genap',  '2026-02-01', '2026-06-30', TRUE);

INSERT INTO public.mata_kuliah (kode, nama, sks, prodi, jenis) VALUES
  ('IF101', 'Algoritma dan Pemrograman',         2, 'D3 Teknik Informatika', 'wajib'),
  ('IF102', 'Basis Data',                        2, 'D3 Teknik Informatika', 'wajib'),
  ('IF103', 'Pemrograman Web',                   2, 'D3 Teknik Informatika', 'wajib'),
  ('IF104', 'Administrasi Jaringan',             2, 'D3 Teknik Informatika', 'wajib'),
  ('IF105', 'Sistem Operasi',                    2, 'D3 Teknik Informatika', 'wajib'),
  ('IF201', 'Pemrograman Berorientasi Objek',    2, 'D3 Teknik Informatika', 'wajib'),
  ('IF202', 'Pengembangan Aplikasi Mobile',      2, 'D3 Teknik Informatika', 'pilihan'),
  ('IF203', 'Kecerdasan Buatan',                 2, 'D3 Teknik Informatika', 'pilihan'),
  ('IF204', 'Proyek Akhir',                      2, 'D3 Teknik Informatika', 'wajib'),
  ('MTK101','Matematika Diskrit',                2, 'D3 Teknik Informatika', 'wajib');
