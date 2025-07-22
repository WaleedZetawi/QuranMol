/***************************************************************
 *  server.js – Moltaqa API  (طلاب + مشرفون + exam‑requests + تسجيل)
 *  17 Jul 2025 – دمج كامل بين النسختين مع تحسينات الربط بالمشرفين
 *  npm i express cors body-parser pg bcryptjs jsonwebtoken joi
 *         nodemailer dotenv crypto
 ***************************************************************/

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const Joi = require('joi');
const nodemailer = require('nodemailer');
const crypto = require('crypto');
const PASS_MARK = 60;   // ← غيّر 60 إلى 80 أو أي رقم تريده من 0..100

const app = express();
app.use(cors());
app.use(bodyParser.json());

/* ───── PG ───── */
const pool = new Pool({
  user: process.env.DB_USER,
  host: 'localhost',
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: process.env.DB_PORT,
});
pool.connect().then(() => console.log('✅ PG connected'))
              .catch(e => console.error('❌ PG error', e));

/* ───── Mail ───── */
const mailer = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: +process.env.SMTP_PORT,
  secure: false,
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
});

/* ───── JWT ───── */
const auth = (req,res,next)=>{
  const token = req.headers.authorization?.split(' ')[1];
  if(!token) return res.status(401).json({message:'token'});
  jwt.verify(token,process.env.JWT_SECRET,
    (e,u)=>e?res.status(403).json({message:'bad token'}):(req.user=u,next()));
};

/* ───── ثوابت ───── */
const VALID_COLLEGES=['Engineering','Medical','Sharia'];
const VALID_CODES = ['F1','F2','F3','F4','F5','F6','T1','T2','T3','H1','H2','Q'];

/* ────────────────── Helper: ترقية الطالب إلى حافظ ────────────────── */
async function promoteIfQualified(stuId) {
  /* 1) الطالب */
  const sRes = await pool.query(
    'SELECT id, name, email, student_type, is_hafidh FROM students WHERE id=$1',
    [stuId]
  );
  if (!sRes.rowCount) return;
  const s = sRes.rows[0];
  if (s.is_hafidh) return;

  /* 2) الامتحانات الرسمية الناجحة */
  const { rows: ex } = await pool.query(`
     SELECT exam_code, created_at
       FROM exams
      WHERE student_id=$1 AND passed AND official`,
      [stuId]);

  if (!ex.length) return;

  const have = ex.map(r => r.exam_code);
  const needReg = ['F1','F2','F3','F4','F5','F6'];
  const needInt = ['T1','T2','T3','H1','H2','Q'];
  const ok = s.student_type === 'regular'
               ? needReg.every(c => have.includes(c))
               : needInt.every(c => have.includes(c));
  if (!ok) return;

  /* 3) آخر تاريخ */
  const lastDate = ex.reduce(
    (m, r) => (r.created_at > m ? r.created_at : m),
    ex[0].created_at
  );

  /* 4) حدِّث students */
  await pool.query(`
       UPDATE students
          SET is_hafidh  = TRUE,
              hafidh_date = $2
        WHERE id = $1`, [stuId, lastDate]);

  /* 5) NEW – انسخ فى جدول hafadh (إذا موجود) */
  await pool.query(`
      INSERT INTO hafadh (student_id, hafidh_date)
      VALUES ($1,$2)
      ON CONFLICT (student_id) DO UPDATE
        SET hafidh_date = EXCLUDED.hafidh_date`,
      [stuId, lastDate]);

  /* 6) الإيميل (اختياري) */
  if (s.email) {
    try {
      await mailer.sendMail({
        from   : `"Quran App" <${process.env.SMTP_USER}>`,
        to     : s.email,
        subject: '🌟 مبااارك — أنت حافظ الآن!',
        text   :
`أخي/أختي ${s.name}،

مبارك ختم القرآن الكريم وفق النظام المعتمد في الملتفى، ونسأل الله لك القَبول.

هنيئاً لك تواجد اسمك في قائمة الحفل القادم في ملتقى القران الكريم.

إدارة ملتقى القرآن الكريم`
      });
    } catch (e) { console.error('✉️ خطأ الإيميل', e.message); }
  }
  console.log(`🎉 الطالب ${stuId} صار حافظاً`);
}



/* ═════════════════════ 1) CRUD الطلاب ═════════════════════ */

/* POST /api/students */
/* ═════════════════════ الطلاب ═════════════════════ */

app.post('/api/students', auth, async (req, res) => {
  if (!['EngAdmin','MedicalAdmin','shariaAdmin','admin_dashboard']
        .includes(req.user.role))
    return res.status(403).json({ message: 'غير مخوَّل' });

  const { value:v, error } = Joi.object({
    reg_number  : Joi.string().max(50).required(),
    name        : Joi.string().min(3).max(100).required(),
    phone       : Joi.string().max(20).allow('',null),
    email       : Joi.string().email().allow('',null),
    college     : Joi.string().valid(...VALID_COLLEGES).required(),
    supervisor_id: Joi.number().integer().allow(null),
    student_type: Joi.string().valid('regular','intensive').required(),
    password    : Joi.string().min(4).max(50).default('123456')
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  const emailNorm = v.email && v.email.trim()!=='' ? v.email.trim() : null;

  const dup = await pool.query(
    `SELECT 1 FROM students WHERE reg_number=$1 OR email=$2`,
    [v.reg_number, emailNorm]);
  if (dup.rowCount) return res.status(400).json({ message: 'رقم أو بريد مكرر' });

  const hash = await bcrypt.hash(v.password, 10);
  await pool.query(`
      INSERT INTO students
        (reg_number,name,password,phone,email,college,
         supervisor_id,student_type)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [v.reg_number, v.name, hash, v.phone, emailNorm,
       v.college, v.supervisor_id, v.student_type]);

  res.status(201).json({ message: 'تمت الإضافة' });
});

/* إرجاع اسم المشرف بالـ JOIN */
app.get('/api/students',auth,async(_req,res)=>{
  const {rows}=await pool.query(`
    SELECT s.*, sp.name AS supervisor_name
      FROM students s
 LEFT JOIN supervisors sp ON sp.id=s.supervisor_id
  ORDER BY s.id`);
  res.json(rows);
});

/* PUT /api/students/:id */
app.put('/api/students/:id', auth, async (req, res) => {
  const { value:v, error } = Joi.object({
    name        : Joi.string().min(3).max(100).required(),
    phone       : Joi.string().max(20).allow('',null),
    email       : Joi.string().email().allow('',null),
    college     : Joi.string().valid(...VALID_COLLEGES).required(),
    supervisor_id: Joi.number().integer().allow(null),
    student_type: Joi.string().valid('regular','intensive').required()
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  const emailNorm = v.email && v.email.trim()!=='' ? v.email.trim() : null;
  const id = +req.params.id;

  const { rowCount } = await pool.query(`
      UPDATE students SET
        name=$1, phone=$2, email=$3, college=$4,
        supervisor_id=$5, student_type=$6
      WHERE id=$7`,
      [v.name, v.phone, emailNorm, v.college,
       v.supervisor_id, v.student_type, id]);
  if (!rowCount) return res.status(404).json({ message: 'لم يُوجد' });
  res.json({ message: 'تم التعديل' });
});

/* DELETE /api/students/:id */
app.delete('/api/students/:id', auth, async (req, res) => {
  const id = +req.params.id;
  const { rowCount } = await pool.query(
    'DELETE FROM students WHERE id=$1', [id]);
  if (!rowCount) return res.status(404).json({ message: 'غير موجود' });
  res.json({ message: 'تم الحذف' });
});

/* ═════════════════════ 2) CRUD المشرفين ═════════════════════ */

app.get('/api/supervisors',auth,async(_req,res)=>{
  const {rows}=await pool.query(`
    SELECT COALESCE(is_regular,false)  AS is_regular ,
           COALESCE(is_trial,false)    AS is_trial  ,
           COALESCE(is_doctor,false)   AS is_doctor ,
           COALESCE(is_examiner,false) AS is_examiner ,
           *
      FROM supervisors
  ORDER BY college,name`);
  res.json(rows);
});

app.post('/api/supervisors', auth, async (req, res) => {
  const { value:v, error } = Joi.object({
    name        : Joi.string().min(3).max(100).required(),
    phone       : Joi.string().max(20).allow('',null),
    email       : Joi.string().email().allow('',null),
    college     : Joi.string().valid(...VALID_COLLEGES).required(),
    is_regular  : Joi.boolean().default(true),
    is_trial    : Joi.boolean().default(false),
    is_doctor   : Joi.boolean().default(false),
    is_examiner : Joi.boolean().default(false)
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  const reg = crypto.randomUUID();
  const emailNorm = v.email && v.email.trim()!=='' ? v.email.trim() : null;

  await pool.query(`
      INSERT INTO supervisors
        (reg_number,name,phone,email,college,
         is_regular,is_trial,is_doctor,is_examiner)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [reg, v.name, v.phone, emailNorm, v.college,
       v.is_regular, v.is_trial, v.is_doctor, v.is_examiner]);

  res.status(201).json({ message: 'تم إضافة المشرف' });
});

app.put('/api/supervisors/:id', auth, async (req, res) => {
  const { value:v, error } = Joi.object({
    name        : Joi.string().min(3).max(100).required(),
    phone       : Joi.string().max(20).allow('',null),
    email       : Joi.string().email().allow('',null),
    college     : Joi.string().valid(...VALID_COLLEGES).required(),
    is_regular  : Joi.boolean().default(true),
    is_trial    : Joi.boolean().default(false),
    is_doctor   : Joi.boolean().default(false),
    is_examiner : Joi.boolean().default(false)
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  const emailNorm = v.email && v.email.trim()!=='' ? v.email.trim() : null;
  const id = +req.params.id;

  const { rowCount } = await pool.query(`
      UPDATE supervisors SET
        name=$1, phone=$2, email=$3, college=$4,
        is_regular=$5, is_trial=$6, is_doctor=$7, is_examiner=$8
      WHERE id=$9`,
      [v.name, v.phone, emailNorm, v.college,
       v.is_regular, v.is_trial, v.is_doctor, v.is_examiner, id]);
  if (!rowCount) return res.status(404).json({ message: 'غير موجود' });
  res.json({ message: 'تم التحديث' });
});

app.delete('/api/supervisors/:id', auth, async (req, res) => {
  const { rowCount } = await pool.query(
    'DELETE FROM supervisors WHERE id=$1', [+req.params.id]);
  if (!rowCount) return res.status(404).json({ message: 'غير موجود' });
  res.json({ message: 'تم الحذف' });
});
/* ─── المشرفون العاديون (عامّ) ─── */
app.get('/api/public/regular-supervisors', async (req, res) => {
  const params = [];
  let where    = 'is_regular = TRUE';

  if (req.query.college) {           // ?college=Engineering
    params.push(req.query.college);
    where += ` AND college = $${params.length}`;
  }

  const { rows } = await pool.query(
    `SELECT id, name, college
       FROM supervisors
      WHERE ${where}
   ORDER BY name`,
    params
  );

  res.json(rows);
});


/* ═════════════════════ 3) الامتحانات ═════════════════════ */

app.post('/api/exams', auth, async (req, res) => {
  const { value:v, error } = Joi.object({
    student_id : Joi.number().integer().required(),
    exam_code  : Joi.string()
                    .regex(/^(J(0[1-9]|[12][0-9]|30)|F[1-6]|T[1-3]|H[12]|Q)$/)
                    .required(),
    passed  : Joi.boolean().required(),
    official: Joi.boolean().required()
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  await pool.query(`
      INSERT INTO exams (student_id, exam_code, passed, official)
      VALUES ($1,$2,$3,$4)`,
      [v.student_id, v.exam_code, v.passed, v.official]);

  if (v.passed && v.official)
    await promoteIfQualified(v.student_id);

  res.status(201).json({ message: 'تم تسجيل الامتحان' });
});
/* ⬇️ أضِف بعد POST /api/exams مباشرة */
/* -------------------- grade – يفرّق بين التجريبي والرسمي ------------- */
app.post('/api/grade', auth, async (req, res) => {
  const { value:v, error } = Joi.object({
    request_id: Joi.number().integer().required(),
    score     : Joi.number().precision(2).min(0).max(100).required(),
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  /* الطلب */
  const { rows } = await pool.query(
    'SELECT * FROM exam_requests WHERE id=$1 AND approved=TRUE',
    [v.request_id],
  );
  if (!rows.length) return res.status(404).json({ message: 'not found' });
  const er   = rows[0];

  /* هل سبق تسجيل التجريبي؟ */
  const trialDone = await pool.query(
    'SELECT 1 FROM exams WHERE request_id=$1 AND official=FALSE',
    [v.request_id],
  );

  /* stage */
  const official = trialDone.rowCount ? true : false;
  const passed   = v.score >= PASS_MARK;

  /* الكود والتاريخ */
  const examCode = er.kind === 'part'
        ? `J${er.part.toString().padStart(2, '0')}`
        : er.exam_code;
  const examDate =
        official ? (er.official_date || new Date())
                 : (er.trial_date   || new Date());

  /* INSERT / UPSERT */
  await pool.query(`
      INSERT INTO exams
        (student_id, exam_code, passed, official,
         score, request_id, created_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7)
      ON CONFLICT (request_id, official)
      DO UPDATE SET
        score      = EXCLUDED.score,
        passed     = EXCLUDED.passed,
        created_at = EXCLUDED.created_at`,
    [
      er.student_id, examCode, passed,
      /* فقط متغير  official  الذى حسبناه قبل قليل */
      official,
      v.score, v.request_id, examDate,
    ]);

  /* ترقية لو الرسمي ناجح */
  if (official && passed)
    await promoteIfQualified(er.student_id);

  /* إن فشل التجريبي → ألغِ الرسمي */
  if (!official && !passed) {
    await pool.query(`
        UPDATE exam_requests
           SET official_date          = NULL,
               supervisor_official_id = NULL,
               approved               = NULL   -- يعود الطلب إلى “معلّق”
         WHERE id = $1`, [v.request_id]);
  }

  res.status(201).json({ message: 'تم رصد العلامة' });
});
  /* INSERT / UPSERT */


/* سحب العلامة (يمسح كل الامتحانات المرتبطة بالطلب) */
app.delete('/api/grade/:requestId', auth, async (req, res) => {
  const requestId = +req.params.requestId;

  // تحقَّق من الطلب
  const { rows: rq } = await pool.query(
    'SELECT id, kind FROM exam_requests WHERE id=$1',
    [requestId]
  );
  if (!rq.length) return res.status(404).json({ message: 'الطلب غير موجود' });

  // احذف الامتحانات
  const del = await pool.query(
    'DELETE FROM exams WHERE request_id=$1 RETURNING official, passed',
    [requestId]
  );

  // لو حذفنا التجريبي الرسمي (official=false) وكان هناك رسمي سابق
  // أو تريد إعادة الطلب إلى معلق (حسب سياستك):
  if (del.rowCount) {
    if (rq[0].kind === 'official') {
      await pool.query(`
        UPDATE exam_requests
           SET official_date = CASE
               WHEN EXISTS (
                 SELECT 1 FROM exams WHERE request_id=$1 AND official=TRUE
               ) THEN official_date
               ELSE official_date
             END,
               supervisor_official_id = CASE
                 WHEN NOT EXISTS (
                   SELECT 1 FROM exams WHERE request_id=$1 AND official=TRUE
                 ) THEN NULL ELSE supervisor_official_id END
         WHERE id=$1`, [requestId]);
    } else {
      /* جزء: لا شيء إضافي */
    }
  }

  res.json({ message: 'تم سحب العلامة', deleted: del.rowCount });
});


app.get('/api/exams/:studentId', auth, async (req, res) => {
  const stuId = +req.params.studentId;
  const { rows } = await pool.query(`
      SELECT * FROM exams
       WHERE student_id = $1
    ORDER BY created_at DESC`, [stuId]);
  res.json(rows);
});

/* ─── GET /hafadh ───*/
app.get('/api/hafadh', auth, async (_req, res) => {
  const { rows } = await pool.query(`
    SELECT s.id, s.reg_number, s.name, s.college,
           COALESCE(h.hafidh_date, s.hafidh_date) AS hafidh_date
      FROM students  s
 LEFT JOIN hafadh     h ON h.student_id = s.id
     WHERE s.is_hafidh = TRUE
  ORDER BY COALESCE(h.hafidh_date, s.hafidh_date) DESC`);
  res.json(rows);
});
/* ─── إضافة حافظ يدويًا ─── */
// ─── إضافة حافظ يدويًا + ملء الامتحانات الرسمية تلقائيًا ───
app.post('/api/hafadh', auth, async (req, res) => {
  if (req.user.role !== 'admin_dashboard')
    return res.status(403).json({ message: 'غير مخوَّل' });

  // 1) تحقق من البيانات الواردة
  const { value: v, error } = Joi.object({
    student_id : Joi.number().integer().required(),
    hafidh_date: Joi.date().optional()
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  // 2) حدّد تاريخ الختمة (إن وُجد) أو الآن
  const hafidhDate = v.hafidh_date || new Date();

  // 3) حدّث جدول students
  await pool.query(`
     UPDATE students
        SET is_hafidh   = TRUE,
            hafidh_date = $2
      WHERE id = $1
  `, [v.student_id, hafidhDate]);

  // 4) أدرج/حدّث جدول hafadh
  await pool.query(`
    INSERT INTO hafadh (student_id, hafidh_date)
    VALUES ($1, $2)
    ON CONFLICT (student_id)
      DO UPDATE SET hafidh_date = EXCLUDED.hafidh_date
  `, [v.student_id, hafidhDate]);

  // 5) جلب خطة الطالب لتحديد الأكواد المطلوبة
  const { rows: stuRows } = await pool.query(
    'SELECT student_type FROM students WHERE id=$1',
    [v.student_id]
  );
  if (stuRows.length) {
    const studentType = stuRows[0].student_type;
    const requiredCodes = studentType === 'regular'
      ? ['F1','F2','F3','F4','F5','F6']
      : ['T1','T2','T3','H1','H2','Q'];

    // 6) أدرج في جدول exams كل رمز امتحان رسمي ناجح
    for (const code of requiredCodes) {
      await pool.query(`
        INSERT INTO exams
          (student_id, exam_code, passed, official, created_at)
        VALUES ($1, $2, TRUE, TRUE, $3)
        ON CONFLICT (student_id, exam_code, official)
          DO NOTHING
      `, [v.student_id, code, hafidhDate]);
    }
  }

  // 7) أعد الاستجابة للعميل
  res.status(201).json({ message: 'تمت إضافة الحافظ' });
});

// PATCH /api/students/:id/hafidh
app.patch('/api/students/:id/hafidh', auth, async (req,res)=>{
  if (req.user.role!=='admin_dashboard')
    return res.status(403).json({message:'غير مخوَّل'});
  await pool.query(`
     UPDATE students
        SET is_hafidh = TRUE,
            hafidh_date = $1
      WHERE id=$2`, [req.body.date || new Date(), +req.params.id]);
  res.json({message:'ok'});
});


/* ═════════════════════ 4) exam‑requests ═════════════════════ */

/* -------------------- exam‑requests – POST (طالب) -------------------- */
/* -------------------- exam‑requests – POST (طالب) -------------------- */
app.post('/api/exam-requests', auth, async (req, res) => {
  /* 1) تحقُّق من أنّ المُرسِل طالب */
  const uid = req.user.id;
  const stu = await pool.query('SELECT * FROM students WHERE id=$1', [uid]);
  if (!stu.rowCount) return res.status(403).json({ message: 'not student' });

  /* 2) التحقق من البيانات */
  const { value:e, error } = Joi.object({
    kind : Joi.string().valid('part', 'official').required(),

    /* طلب جزء */
    part : Joi.number().integer().min(1).max(30)
               .when('kind', { is: 'part', then: Joi.required() }),
    date : Joi.date()
               .when('kind', { is: 'part', then: Joi.required() }),

    /* طلب رسمى */
    exam_code  : Joi.string().valid(...VALID_CODES)
               .when('kind', { is: 'official', then: Joi.required() }),
    trial_date : Joi.date()
               .when('kind', { is: 'official', then: Joi.required() }),

    /* اختيارى عند الإنشاء */
    /* داخل مخطط Joi في POST /api/exam-requests */
    official_date : Joi.date()
                  .min(Joi.ref('trial_date'))  // يسمح بنفس اليوم أو بعده
                  .allow(null),

  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  /* 3) تحضير القيم بما يلائم نوع الطلب */
  const isPart     = e.kind === 'part';
  const part        = isPart ? e.part : null;
  const partDate    = isPart ? new Date(e.date) : null;          // ← تحويل
  const examCode    = isPart ? null : e.exam_code;
  const trialDate   = isPart ? null : new Date(e.trial_date);    // ← تحويل
  const officialDate= isPart ? null
                              : (e.official_date ? new Date(e.official_date)
                                                 : null);

  /* 4) الإدراج */
  await pool.query(`
    INSERT INTO exam_requests
      (student_id, kind,  part, "date",
       exam_code , trial_date, official_date, college)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
  `, [
    uid, e.kind,
    part, partDate,
    examCode, trialDate, officialDate,
    stu.rows[0].college,
  ]);

  res.status(201).json({ message: 'ok' });
});


/* ═════════════ my‑exam‑requests (تاريخ ثابت) ═════════════ */
app.get('/api/my-exam-requests', auth, async (req, res) => {
  const { rows } = await pool.query(`
    SELECT er.id,
           er.kind,
            CASE
              WHEN kind = 'part'                     THEN 'جزء '||part
              WHEN exam_code::text LIKE 'F%'         THEN 'خمسة أجزاء '||substr(exam_code::text,2,1)
              WHEN exam_code::text LIKE 'T%'         THEN 'عشرة أجزاء '||substr(exam_code::text,2,1)
              WHEN exam_code::text = 'H1'            THEN 'خمسة عشر الأولى'
              WHEN exam_code::text = 'H2'            THEN 'خمسة عشر الثانية'
              WHEN exam_code::text =  'Q'            THEN 'القرآن كامل'
            END AS display,
            COALESCE(date, trial_date, official_date) AS exam_date,
           er.approved,
           sp.name        AS supervisor_name,
           st_trial.name  AS trial_supervisor,
           st_doc.name    AS doctor_supervisor
       FROM exam_requests er
    JOIN students     st   ON st.id  = er.student_id
 LEFT JOIN supervisors sp ON sp.id = st.supervisor_id
 LEFT JOIN supervisors st_trial ON st_trial.id = er.supervisor_trial_id
 LEFT JOIN supervisors st_doc   ON st_doc.id   = er.supervisor_official_id
     WHERE er.student_id=$1
   ORDER BY er.id DESC`, [req.user.id]);
   res.json(rows);
});


/* كل الطلبات (root أو إداري مجمع) */
/* كل الطلبات (root أو إداري مجمع) */
/* كل الطلبات (root أو إداري مجمع) */
// ─── في server.js ───
app.get('/api/exam-requests', auth, async (req, res) => {
  const role   = req.user.role;
  const params = [];
  // نبدأ بشرط "معلق" فقط
  let where = 'er.approved IS NULL';

  if (role === 'admin_dashboard') {
    // المدير العام: يرى فقط الطلبات الرسمية
    where += ` AND er.kind = 'official'`;
  } else {
    // مسؤولو الكليات: يرون طلبات الأجزاء الخاصة بكليتهم
    const college =
      req.user.college ||
      (role === 'EngAdmin'     ? 'Engineering' :
       role === 'MedicalAdmin' ? 'Medical'     :
                                  'Sharia');
    params.push(college);
    where += ` AND er.college = $${params.length} AND er.kind = 'part'`;
  }

  const { rows } = await pool.query(`
        SELECT
      er.id,
      er.kind,
      er.part,
      er."date"        AS date,         
      er.exam_code,
      er.trial_date,
      er.official_date,
      er.approved,
      er.college,                    
      st.name        AS student_name,
      sp.name        AS orig_supervisor,
      ex.name        AS examiner_name,
      er.supervisor_trial_id,
      er.supervisor_official_id

    FROM exam_requests er
    JOIN students     st ON st.id = er.student_id
    LEFT JOIN supervisors sp ON sp.id = st.supervisor_id
    LEFT JOIN supervisors ex ON ex.id = er.supervisor_trial_id
    WHERE ${where}
    ORDER BY er.id DESC
  `, params);

  res.json(rows);
});




/* -------------------- exam‑requests – PATCH (قبول / تعيين مواعيد) --- */
app.patch('/api/exam-requests/:id', auth, async (req, res) => {
  const { value: v, error } = Joi.object({
    approved               : Joi.boolean().required(),
    supervisor_trial_id    : Joi.number().integer().allow(null),
    supervisor_official_id : Joi.number().integer().allow(null),
    official_date          : Joi.date().allow(null)
  }).validate(req.body);
  if (error)
    return res.status(400).json({ message: error.message });

  const id = +req.params.id;

  // نحتاج نوع الطلب وتاريخ التجريبي
  const { rows: cur } = await pool.query(
    'SELECT kind, trial_date FROM exam_requests WHERE id=$1',
    [id]
  );
  if (!cur.length)
    return res.status(404).json({ message: 'الطلب غير موجود' });

  const kind      = cur[0].kind;
  const trialDate = cur[0].trial_date; // null لو طلب جزء

  // منع القبول لطلب رسمي بدون اختيار المشرفين
  if (v.approved === true && kind === 'official') {
    if (!v.supervisor_trial_id || !v.supervisor_official_id) {
      return res.status(400).json({
        message: 'اختر مشرف التجريبي ومشرف الرسمي قبل القبول'
      });
    }
  }

  // السماح أن يكون الرسمي في نفس يوم التجريبي أو بعده
  if (
    kind === 'official' &&
    trialDate &&
    v.official_date &&
    v.supervisor_trial_id &&
    v.supervisor_official_id
  ) {
    const off = new Date(v.official_date);
    const tr  = new Date(trialDate);

    // السماح بنفس اليوم: >=
    if (!(off >= tr)) {
      return res.status(400).json({
        message: 'تاريخ الامتحان الرسمي يجب أن يكون في نفس اليوم أو بعد التجريبي'
      });
    }
  }

  await pool.query(
    `UPDATE exam_requests SET
        approved               = $1,
        approver_id            = $2,
        supervisor_trial_id    = $3,
        supervisor_official_id = $4,
        official_date          = COALESCE($5, official_date)
      WHERE id = $6`,
    [
      v.approved,
      req.user.id,
      v.supervisor_trial_id,
      v.supervisor_official_id,
      v.official_date,
      id
    ]
  );

  res.json({ message: 'done' });
});

/* DELETE /api/exam-requests/:id */
app.delete('/api/exam-requests/:id', auth, async (req, res) => {
  const id    = +req.params.id;
  const role  = req.user.role;
  const col   = req.user.college;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // قيد السماحية
    const { rows: reqRows } = await client.query(
      'SELECT id, college FROM exam_requests WHERE id=$1', [id]
    );
    if (!reqRows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'غير موجود' });
    }
    if (role !== 'admin_dashboard' && reqRows[0].college !== col) {
      await client.query('ROLLBACK');
      return res.status(403).json({ message: 'غير مخوَّل' });
    }

    // احذف الامتحانات التابعة (إن وُجدت)
    await client.query('DELETE FROM exams WHERE request_id=$1', [id]);

    // احذف الطلب
    await client.query('DELETE FROM exam_requests WHERE id=$1', [id]);

    await client.query('COMMIT');
    res.json({ message: 'تم الحذف' });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    res.status(500).json({ message: 'خطأ أثناء الحذف' });
  } finally {
    client.release();
  }
});

/* -------------------- pending‑scores (تجريبي + رسمي) ---------------- */
/* -------------------- pending‑scores (Part + Trial + Official) -------- */
/* -------------------- pending‑scores (Part + Trial + Official) -------- */
app.get('/api/pending-scores', auth, async (req, res) => {
  const role    = req.user.role;
  const college = req.user.college;
  const params  = [];
  let q = '';

  if (role === 'admin_dashboard') {
    /* المدير العام: تجريبي + رسمي (لا أجزاء) */
    q = `
      /* تجريبي لم يُصحَّح */
      SELECT er.id AS req_id,
             er.kind,
             'trial' AS stage,
             er.exam_code::text AS exam_code,
             er.trial_date AS exam_date,
             st.id AS student_id,
             st.name AS student_name,
             er.college
        FROM exam_requests er
        JOIN students st ON st.id = er.student_id
   LEFT JOIN exams  e  ON e.request_id = er.id AND e.official = FALSE
       WHERE er.kind = 'official' AND er.approved = TRUE
         AND e.id IS NULL

      UNION ALL

      /* رسمي بعد نجاح التجريبي */
      SELECT er.id,
             er.kind,
             'official' AS stage,
             er.exam_code::text AS exam_code,
             er.official_date AS exam_date,
             st.id,
             st.name,
             er.college
        FROM exam_requests er
        JOIN students st ON st.id = er.student_id
        JOIN exams et ON et.request_id = er.id
                     AND et.official = FALSE
                     AND et.passed = TRUE
   LEFT JOIN exams eo ON eo.request_id = er.id AND eo.official = TRUE
       WHERE eo.id IS NULL
      ORDER BY exam_date NULLS LAST, req_id;
    `;
  } else {
    /* مسؤولو المجمّعات: أجزاء فقط */
    params.push(college);
    q = `
      SELECT er.id AS req_id,
             er.kind,
             'part' AS stage,
             'J' || LPAD(er.part::text,2,'0') AS exam_code,
             er.date AS exam_date,
             st.id AS student_id,
             st.name AS student_name,
             er.college
        FROM exam_requests er
        JOIN students st ON st.id = er.student_id
   LEFT JOIN exams e ON e.request_id = er.id
       WHERE er.kind='part'
         AND er.approved = TRUE
         AND er.college = $1
         AND e.id IS NULL
      ORDER BY exam_date NULLS LAST, req_id;
    `;
  }

  const { rows } = await pool.query(q, params);
  res.json(rows);
});




/* ═════════════════════ 5) تسجيل + المستخدمون ═════════════════════ */

/* تسجيل طلب جديد */
app.post('/api/register', async (req, res) => {
  const { value, error } = Joi.object({
  role         : Joi.string().valid('student', 'supervisor').required(),
  name         : Joi.string().min(3).max(100).required(),
  reg_number   : Joi.string().max(50).required(),
  email        : Joi.string().email().required(),
  phone        : Joi.string().max(20).allow('', null),
  college      : Joi.string().valid(...VALID_COLLEGES).required(),
  password     : Joi.string().min(4).max(50).required(),

  // يقبل فقط مع دور "طالب"
  supervisor_id: Joi.when('role', {
    is : 'student',
    then: Joi.number().integer().required(),
    otherwise: Joi.forbidden()
  }),

  student_type : Joi.when('role', {
    is : 'student',
    then: Joi.string().valid('regular', 'intensive').required(),
    otherwise: Joi.forbidden()
  })
}).validate(req.body);

  if (error) return res.status(400).json({ message: error.message });

  const { reg_number, email } = value;

  const dup = await pool.query(`
        SELECT 1 FROM users       WHERE reg_number=$1 OR email=$2
        UNION
        SELECT 1 FROM students    WHERE reg_number=$1 OR email=$2
        UNION
        SELECT 1 FROM supervisors WHERE reg_number=$1 OR email=$2
        UNION
        SELECT 1 FROM registration_requests
               WHERE (reg_number=$1 OR email=$2) AND status='pending'`,
      [reg_number, email]);
  if (dup.rowCount)
    return res.status(400).json({ message: 'رقم التسجيل أو البريد مستخدم' });

  await pool.query(`
      INSERT INTO registration_requests
        (role, reg_number, name, email, phone, college,
         supervisor_id, student_type, password)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [value.role, reg_number, value.name, email,
       value.phone, value.college,
       value.supervisor_id, value.student_type, value.password]);

  res.status(201).json({ message: 'تم استلام طلبك وسيُراجع قريبًا' });
});

/* طلبات التسجيل - عدّد */
app.get('/api/requests/count', auth, async (req, res) => {
  if (req.user.role !== 'admin_dashboard')
    return res.status(403).json({ message: 'غير مخوَّل' });

  const { rows } = await pool.query(`
      SELECT COUNT(*)::int AS c
        FROM registration_requests
       WHERE status='pending'`);
  res.json({ pending: rows[0].c });
});

/* جميع طلبات التسجيل */
app.get('/api/requests', auth, async (req, res) => {
  if (req.user.role !== 'admin_dashboard')
    return res.status(403).json({ message: 'غير مخوَّل' });

  const { rows } = await pool.query(`
      SELECT * FROM registration_requests
       WHERE status='pending'
    ORDER BY created_at`);
  res.json(rows);
});

/* قبول طلب */
app.post('/api/requests/:id/approve', auth, async (req, res) => {
  if (req.user.role !== 'admin_dashboard')
    return res.status(403).json({ message: 'غير مخوَّل' });

  const id = +req.params.id;
  const { rows } = await pool.query(`
      SELECT * FROM registration_requests
       WHERE id=$1 AND status='pending'`, [id]);
  if (!rows.length) return res.status(404).json({ message: 'الطلب غير موجود' });

  const r = rows[0];
  const dup = await pool.query(`
      SELECT 1 FROM users       WHERE reg_number=$1 OR email=$2
      UNION
      SELECT 1 FROM students    WHERE reg_number=$1 OR email=$2
      UNION
      SELECT 1 FROM supervisors WHERE reg_number=$1 OR email=$2`,
    [r.reg_number, r.email]);
  if (dup.rowCount)
    return res.status(400).json({ message: 'الرقم أو البريد مستخدم بالفعل' });

  const hash = await bcrypt.hash(r.password, 10);

  if (r.role === 'student') {
    /* حاول إيجاد مشرف بالاسم إن وُجد */
    /* رقم المشرف (قد يكون null) */
  const supId = r.supervisor_id;

  await pool.query(`
      INSERT INTO students
        (reg_number, name, password, phone, email, college,
         supervisor_id, student_type)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [
        r.reg_number,
        r.name,
        hash,
        r.phone,
        r.email,
        r.college,
        supId,
        r.student_type || 'regular'   
      ]);
  } else {
    await pool.query(`
        INSERT INTO supervisors
          (reg_number,name,phone,college,password,email)
        VALUES ($1,$2,$3,$4,$5,$6)`,
      [r.reg_number, r.name, r.phone, r.college, hash, r.email]);
  }

  await pool.query(`
      UPDATE registration_requests
         SET status='approved'
       WHERE id=$1`, [id]);

  await mailer.sendMail({
    from   : `"Quran App" <${process.env.SMTP_USER}>`,
    to     : r.email,
    subject: 'تم قبول طلبك',
    text   :
`مرحبًا ${r.name}،

تمت الموافقة على طلب انضمامك. يمكنك الآن تسجيل الدخول
باستخدام رقم التسجيل وكلمة السر التي أدخلتها.

أهلاً وسهلاً بك 🌸`
  });

  res.json({ message: 'تم القبول' });
});

/* رفض طلب */
app.post('/api/requests/:id/reject', auth, async (req, res) => {
  if (req.user.role !== 'admin_dashboard')
    return res.status(403).json({ message: 'غير مخوَّل' });

  const id = +req.params.id;
  const { rows } = await pool.query(`
      UPDATE registration_requests
         SET status='rejected'
       WHERE id=$1 AND status='pending'
   RETURNING email,name`, [id]);
  if (!rows.length)
    return res.status(404).json({ message: 'الطلب غير موجود أو تم معالجته' });

  await mailer.sendMail({
    from   : `"Quran App" <${process.env.SMTP_USER}>`,
    to     : rows[0].email,
    subject: 'تم رفض طلبك',
    text   :
`عزيزنا ${rows[0].name}،

نأسف لإبلاغك أن طلب انضمامك لم يُقبَل حاليًا.
يسعدنا استلام طلب جديد منك مستقبلًا إن شئت.`
  });

  res.json({ message: 'تم الرفض' });
});

/* ═════════════════════ 6) تسجيل الدخول وإعادة الضبط ═════════════════════ */

/* ❶ تسجيل دخول المسؤولين / المشرفين */
app.post('/api/login', async (req, res) => {
  const { reg_number, password } = req.body;
  if (!reg_number || !password)
    return res.status(400).json({ message: 'رقم التسجيل وكلمة السر مطلوبة' });

  /* ابحث عن المستخدم */
  const { rows } = await pool.query(
    'SELECT * FROM users WHERE reg_number = $1',
    [reg_number],
  );
  if (!rows.length)
    return res.status(400).json({ message: 'بيانات خاطئة' });

  const user = rows[0];
  const ok   = await bcrypt.compare(password, user.password);
  if (!ok)   return res.status(400).json({ message: 'بيانات خاطئة' });

  /* ✅  أضِف college إلى الـ JWT  */
  /* ✅  أضِف college إلى الـ JWT  مع قيمة افتراضية عند الحاجة */
const fallback = {
  EngAdmin     : 'Engineering',
  MedicalAdmin : 'Medical',
  shariaAdmin  : 'Sharia',
};

const token = jwt.sign(
  {
    id        : user.id,
    reg_number: user.reg_number,
    role      : user.role,
    // إن كان العمود `college` فارغًا نستخدم fallback تلقائيًا
    college   : user.college || fallback[user.role] || null,
  },
  process.env.JWT_SECRET,
  { expiresIn: '2h' },
);


  res.json({ message: 'تم', token, user });
});


/* ❷ تسجيل دخول الطلاب */
app.post('/api/student-login', async (req, res) => {
  const { reg_number, password } = req.body;
  if (!reg_number || !password)
    return res.status(400).json({ message: 'رقم التسجيل وكلمة السر مطلوبة' });

  /* ابحث عن الطالب */
  const { rows } = await pool.query(
    'SELECT * FROM students WHERE reg_number = $1',
    [reg_number],
  );
  if (!rows.length)
    return res.status(400).json({ message: 'بيانات خاطئة' });

  const stu = rows[0];
  const ok  = await bcrypt.compare(password, stu.password);
  if (!ok)  return res.status(400).json({ message: 'بيانات خاطئة' });

  /* ✅   college داخل الـ JWT */
  const token = jwt.sign(
    {
      id        : stu.id,
      reg_number: stu.reg_number,
      college   : stu.college     // ← الحقل المهم
    },
    process.env.JWT_SECRET,
    { expiresIn: '2h' },
  );

  res.json({ message: 'تم', token, student: stu });
});

/* نسيت كلمة السر */
app.post('/api/forgot-password', async (req, res) => {
  const { value, error } = Joi.object({
    email: Joi.string().email().required()
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  const { rows } = await pool.query(`
      SELECT email FROM users       WHERE email=$1
      UNION
      SELECT email FROM students    WHERE email=$1
      UNION
      SELECT email FROM supervisors WHERE email=$1`, [value.email]);
  if (!rows.length)
    return res.status(404).json({ message: 'البريد غير مسجَّل' });

  const code   = crypto.randomInt(100000, 999999).toString();
  const expire = new Date(Date.now() + 15 * 60 * 1000);

  await pool.query(`
      INSERT INTO password_resets (email,code,expires_at)
      VALUES ($1,$2,$3)`, [value.email, code, expire]);

  await mailer.sendMail({
    from   : `"Quran App" <${process.env.SMTP_USER}>`,
    to     : value.email,
    subject: 'كود إعادة تعيين كلمة السر',
    text   : `رمز التحقق الخاص بك هو: ${code} (صالح لـ15 دقيقة)`
  });

  res.json({ message: 'تم إرسال الكود' });
});

/* reset password */
app.post('/api/reset-password', async (req, res) => {
  const { value, error } = Joi.object({
    email       : Joi.string().email().required(),
    code        : Joi.string().length(6).required(),
    new_password: Joi.string().min(4).max(50).required()
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  const { rows } = await pool.query(`
      SELECT * FROM password_resets
       WHERE email=$1 AND code=$2 AND expires_at>NOW()
    ORDER BY id DESC LIMIT 1`, [value.email, value.code]);
  if (!rows.length)
    return res.status(400).json({ message: 'كود غير صالح' });

  const hash = await bcrypt.hash(value.new_password, 10);
  const tables = ['users','students','supervisors'];
  let updated = false;
  for (const t of tables) {
    const r = await pool.query(
      `UPDATE ${t} SET password=$1 WHERE email=$2`,
      [hash, value.email]);
    if (r.rowCount) { updated = true; break; }
  }
  if (!updated)
    return res.status(500).json({ message: 'الحساب غير موجود' });

  await pool.query('DELETE FROM password_resets WHERE email=$1',[value.email]);
  res.json({ message: 'تم تحديث كلمة السر' });
});

/* ═════════════════════ 7) المستخدمون (إدمن) ═════════════════════ */

app.get('/api/users', auth, async (_req, res) => {
  const { rows } = await pool.query(`
      SELECT id, reg_number, role, college, name, phone, email
        FROM users
    ORDER BY role`);
  res.json(rows);
});

app.put('/api/users/:id', auth, async (req, res) => {
  if (req.user.role !== 'admin_dashboard')
    return res.status(403).json({ message: 'غير مخوَّل' });

  const { value, error } = Joi.object({
    name      : Joi.string().min(3).max(100).required(),
    reg_number: Joi.string().max(50).required(),
    phone     : Joi.string().max(20).allow('',null),
    email     : Joi.string().email().allow('',null)
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  const id = +req.params.id;
  const emailNorm = value.email && value.email.trim()!=='' ? value.email.trim() : null;

  const dup = await pool.query(`
      SELECT id FROM users
       WHERE (reg_number=$1 OR (email=$2 AND $2 IS NOT NULL)) AND id<>$3`,
      [value.reg_number, emailNorm, id]);
  if (dup.rowCount)
    return res.status(400).json({ message: 'رقم أو بريد مكرَّر' });

  const { rowCount } = await pool.query(`
      UPDATE users SET
        name=$1, reg_number=$2, phone=$3, email=$4
      WHERE id=$5`,
      [value.name, value.reg_number, value.phone, emailNorm, id]);
  if (!rowCount)
    return res.status(404).json({ message: 'المستخدم غير موجود' });

  res.json({ message: 'تم التحديث' });
});

app.delete('/api/users/:id', auth, async (req, res) => {
  if (req.user.role !== 'admin_dashboard')
    return res.status(403).json({ message: 'غير مخوَّل' });

  const id = +req.params.id;
  const { rowCount } = await pool.query(
    'DELETE FROM users WHERE id=$1', [id]);
  if (!rowCount)
    return res.status(404).json({ message: 'المستخدم غير موجود' });
  res.json({ message: 'تم الحذف' });
});
// ─── 0) احرص أن تكون الدالة auth موجودة قبل هذا الجزء ───

// 1) عدّ الطلاب
app.get('/api/students/count', auth, async (req, res) => {
  const { rows } = await pool.query(`
    SELECT COUNT(*)::int AS c
      FROM students
  `);
  res.json({ count: rows[0].c });
});

// 2) عدّ المشرفين
app.get('/api/supervisors/count', auth, async (req, res) => {
  const { rows } = await pool.query(`
    SELECT COUNT(*)::int AS c
      FROM supervisors
  `);
  res.json({ count: rows[0].c });
});

// 3) عدّ طلبات الامتحانات المعلقة (للـ dashboard فقط الرسمية)
app.get('/api/exam-requests/count', auth, async (req, res) => {
  const { rows } = await pool.query(`
    SELECT COUNT(*)::int AS c
      FROM exam_requests
     WHERE approved IS NULL
       AND kind = 'official'
  `);
  res.json({ pending: rows[0].c });
});

// 4) عدّ العلامات (pending‑scores) لكن نُعيد فقط العدد
app.get('/api/scores/pending-count', auth, async (req, res) => {
  // الاستعلام بعد إضافة er.kind = 'official' في كلا الجزأين
  const q = `
    SELECT COUNT(*)::int AS c
      FROM (
        /* 1) تجربة رسمي (trial) لم يُرصَّد بعد */
        SELECT er.id
          FROM exam_requests er
          LEFT JOIN exams e
            ON e.request_id = er.id
           AND e.official = FALSE
         WHERE er.kind     = 'official'
           AND er.approved = TRUE
           AND e.id IS NULL

        UNION ALL

        /* 2) رسمي (official) بعد نجاح التجريبي ولم يُرصَّد بعد */
        SELECT er.id
          FROM exam_requests er
          JOIN exams et
            ON et.request_id = er.id
           AND et.official = FALSE
           AND et.passed   = TRUE
          LEFT JOIN exams eo
            ON eo.request_id = er.id
           AND eo.official = TRUE
         WHERE er.kind     = 'official'
           AND er.approved = TRUE
           AND eo.id IS NULL
      ) t
  `;

  const { rows } = await pool.query(q);
  res.json({ pending: rows[0].c });
});

// 5) عدّ الحفاظ
app.get('/api/hafadh/count', auth, async (req, res) => {
  const { rows } = await pool.query(`
    SELECT COUNT(*)::int AS c
      FROM students
     WHERE is_hafidh = TRUE
  `);
  res.json({ count: rows[0].c });
});

/* ───────── تشغيل الخادم ───────── */
const PORT = process.env.PORT || 5000;
app.listen(PORT, () => console.log(`✅ Server running on port ${PORT}`));
