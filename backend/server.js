/***************************************************************
 *  server.js – Moltaqa API  (طلاب + مشرفون + Exam‑Requests + تسجيل)
 *  23 Jul 2025 – نسخة كاملة مع إصلاح شامل للتواريخ فقط (بدون تغيير وظائف)
 *  npm i express cors body-parser pg bcryptjs jsonwebtoken joi
 *         nodemailer dotenv crypto exceljs
 ***************************************************************/

require('dotenv').config();

const express    = require('express');
const cors       = require('cors');
const bodyParser = require('body-parser');
const { Pool, types }   = require('pg');
const bcrypt     = require('bcryptjs');
const jwt        = require('jsonwebtoken');
const Joi        = require('joi');
const nodemailer = require('nodemailer');
const crypto     = require('crypto');
const ExcelJS    = require('exceljs');
const archiver = require('archiver');
const cron = require('node-cron');

const settings = {
  examRegistrationDisabled: false,
  disabledFrom: null,    // ← جديد
  disabledUntil: null
};

const drawCertificate = require('./drawCertificate.js');

// ↑↓ هذا السطر يسجل فونت Amiri
const PDFDocument = require('pdfkit');

const PASS_MARK = 60; // ← عدّلها عند الحاجة
const GENDERS = ['male','female'];
// سجّل فونت Amiri
// أعلى الملف بعد constants
const ADMIN_ROLES = ['admin_dashboard','admin_dash_f','CollegeAdmin','EngAdmin','MedicalAdmin','shariaAdmin'];

const requireAdmin = (req, res) => {
  if (!ADMIN_ROLES.includes(req.user?.role)) {
    res.status(403).json({ message: 'غير مخوَّل' });
    return false;
  }
  return true;
};




/* ───────── Fix PG date/timestamp parsing ───────── */

/*  إعداد محوِّلات الأنواع مرة واحدة  */
const intParser = v => (v === null ? null : parseInt(v, 10));

[
  [1082, v => v],      // DATE
  [1114, v => v],      // TIMESTAMP (بدون منطقة زمنية)
  [1184, v => v],      // TIMESTAMPTZ
  [20,   intParser],   // INT8  (bigint)
  [23,   intParser],   // INT4  (integer)
  [21,   intParser],   // INT2  (smallint)
].forEach(([oid, fn]) => types.setTypeParser(oid, fn));

// في أعلى ملف server.js، إلى جانب settings الحالي
const partExamSettings = {
  Engineering: { disabledFrom: null, disabledUntil: null },
  Medical: { disabledFrom: null, disabledUntil: null },
  Sharia: { disabledFrom: null, disabledUntil: null },
};

const FEMALE_COLLEGES = ['NewCampus','OldCampus','Agriculture'];
const MALE_COLLEGES   = ['Engineering','Medical','Sharia'];

function collegeToGender(college){
  return FEMALE_COLLEGES.includes(college) ? 'female' : 'male';
}
function isGirlsRole(user){ return user?.role === 'admin_dash_f'; }
function isBoysRole(user){  return user?.role === 'admin_dashboard'; }
function isAdminAny(user){  return ['admin_dashboard','admin_dash_f','CollegeAdmin'].includes(user?.role); }

/* ───────── Utils ───────── */
const todayStr  = () => new Date().toISOString().split('T')[0];
const toDateStr = (x) => {
  if (!x) return null;
  if (typeof x === 'string' && x.length === 10 && /^\d{4}-\d{2}-\d{2}$/.test(x)) return x;
  const d = x instanceof Date ? x : new Date(x);
  return isNaN(d.getTime()) ? null : d.toISOString().split('T')[0];
};

// من يَرى من؟
function canSee(viewerGender, recordGender) {
  if ((viewerGender || 'male') === 'male' && (recordGender || 'male') === 'female') return false;
  return true;
}

// فلتر عام لأي صفوف (students/supervisors)
function filterByVisibility(rows, viewerGender) {
  return rows.filter(r => canSee(viewerGender, r.gender || 'male'));
}



/* ───────── util لبناء شهادة رسمية ───────── */
/** 
 * يفحص إن كان الطالب stuId قد نجح في جميع الأجزاء من partStart إلى partEnd 
 * (أي في جدول exams رسمياً أو تجريبياً مع علامة ناجحة).
 */
async function hasPassedParts(stuId, partStart, partEnd) {
  const codes = [];
  for (let i = partStart; i <= partEnd; i++) {
    codes.push(`J${i.toString().padStart(2, '0')}`);
  }
  const { rowCount } = await pool.query(`
    SELECT 1
      FROM exams
     WHERE student_id = $1
       AND passed = TRUE
       AND exam_code = ANY($2)
  `, [stuId, codes]);
  return rowCount === codes.length;
}

 /**
  * يُرجِع مصفوفة الأكواد الرسميّة المطلوبة عند بلوغ edgePart
  * – منتظمة (regular): F1…F6
  * – تثبيت   (intensive): T1, H1, T2, **T3 + H2 + Q** عند 30
  */
 function requiredOfficialExam(studentType, edgePart) {
   if (studentType === 'regular') {
     return ['F' + (edgePart / 5)];        // 5 ,10 ,…
   }
   switch (edgePart) {
     case 10: return ['T1'];               // الأجزاء 1 – 10
     case 15: return ['H1'];               // الأجزاء 1 – 15
     case 20: return ['T2'];               // الأجزاء 11 – 20
     case 30: return ['T3', 'H2', 'Q'];    // الأجزاء 21 – 30 + الختم
     default: return [];
   }
 }




// في أعلى الملف، قبل أي نقطة نهاية:
function calculateDueDate(durationType, durationValue) {
  const d = new Date();
  if (durationType === 'week') {
    d.setDate(d.getDate() + durationValue * 7);
  } else {
    d.setDate(d.getDate() + durationValue);
  }
  return toDateStr(d);
}



// داخل أى Endpoint
function sendCertificate(req, res, data, next) {
  const doc = new PDFDocument({ size: 'A4', margin: 50 });

  // أى خطأ أثناء الرسم أو الكتابة
  doc.on('error', err => {
    console.error('❌ PDF error:', err.message);
    if (!res.headersSent) {
      return next ? next(err) : res.status(500).json({ message: 'PDF error' });
    }
    // الرأس أُرسل فعلاً، اكتفِ بإغلاق الـsocket
    res.end();
  });

  res.setHeader('Content-Type', 'application/pdf');

  /* تعديل وضع التصدير:
     - افتراضياً نعرض الشهادة داخل المتصفح (inline)
     - إذا تم تمرير download=1 فى الـ query، تتحول إلى Attachment */
  if (req.query.download === '1') {
    res.setHeader(
      'Content-Disposition',
      'attachment; filename="certificate.pdf"'
    );
  } else {
    res.setHeader(
      'Content-Disposition',
      'inline; filename="certificate.pdf"'
    );
  }
  doc.pipe(res);
  drawCertificate(doc, data);
  doc.end();
}

function edgePartFromOfficialExam(code) {
  if (code.startsWith('F'))      return parseInt(code.slice(1), 10) * 5; // F1→5, F2→10…
  switch (code) {
    case 'T1': return 10;
    case 'H1': return 15;
    case 'T2': return 20;
    case 'T3': return 30;
    case 'H2': return 30;
    case 'Q' : return 30;
    default  : return null;
  }
}
// helper: استنتاج/فرض الجنس حسب دور/كلية المستخدم
function resolveGenderForUser(req, incoming) {
  const FEMALE_COLLEGES = ['NewCampus','OldCampus','Agriculture'];

  // أدوار/كليات تفرض جنسًا محددًا
  const forced =
    req.user?.role === 'admin_dash_f'    ? 'female' :
    req.user?.role === 'admin_dashboard' ? 'male'   :
    (FEMALE_COLLEGES.includes(req.user?.college) ? 'female' : null);

  if (forced) return forced;   // حتى لو حاول يمرّر مخالف
  return (incoming === 'male' || incoming === 'female') ? incoming : null;
}


/* ───────── util: تحديث الخطة بعد نجاح جزء J ───────── */
async function advancePlanAfterPartSuccess(client, studentId, partNumber) {
  /* ❶ أحدث خطة معتمَدة */
  const { rows: [pl] } = await client.query(`
    SELECT id,
           current_part,
           duration_value,
           paused_for_official,
           official_exams
      FROM plans
     WHERE student_id = $1
       AND approved    = TRUE
  ORDER BY created_at DESC
     LIMIT 1`, [studentId]);
  if (!pl) return;

  /* ❷ نوع الطالب */
  const { rows: [stu] } = await client.query(
    'SELECT student_type FROM students WHERE id = $1', [studentId]);
  const studentType = stu?.student_type || 'regular';

  /* ❸ هل اكتملت أية حزمة حدّية؟ */
  const edgeNumbers = studentType === 'regular'
        ? [5, 10, 15, 20, 25, 30]
        : [10, 15, 20, 30];

  let completedEdge = null;
  for (const edge of edgeNumbers) {
    const prev = edgeNumbers.filter(n => n < edge).pop() || 0;
    if (partNumber >= prev + 1 && partNumber <= edge) {
      if (await hasPassedParts(studentId, prev + 1, edge))
        completedEdge = edge;
      break;
    }
  }

  /* ❹ الرسمى المطلوب للحزمة المكتملة (إن وُجدت) */
  let pendingCodes = [];
  let passedSet    = new Set();
  if (completedEdge !== null) {
    const needed = requiredOfficialExam(studentType, completedEdge);
    const { rows: ok } = await client.query(`
      SELECT exam_code FROM exams
       WHERE student_id = $1
         AND official    = TRUE
         AND passed      = TRUE
         AND exam_code   = ANY($2)`,
      [studentId, needed]);
    passedSet    = new Set(ok.map(r => r.exam_code));
    pendingCodes = needed.filter(c => !passedSet.has(c));
  }

  /* ❺ هل نوقِف الخطة؟ */
  const pauseOfficial = pendingCodes.length > 0 || pl.paused_for_official;

  /* ❻ تحديث قائمة الرسمى الناقص */
  const cleanPrev      = (pl.official_exams || []).filter(c => !passedSet.has(c));
  const official_exams = Array.from(new Set([...cleanPrev, ...pendingCodes]));

  /* ❼ تحديد المؤشِّر الجديد */
  let newCurrent = pl.current_part;

  if (!pauseOfficial) {
    /* اجلب الأجزاء المسموعة */
    const { rows: heardRows } = await client.query(`
      SELECT DISTINCT CAST(SUBSTRING(exam_code FROM 2)::int AS int) AS p
        FROM exams
       WHERE student_id = $1
         AND passed      = TRUE
         AND exam_code   LIKE 'J%'`,
      [studentId]);
    const heard = new Set(heardRows.map(r => r.p));

    /* ابحث من الجزء التالى ثم التفافاً حتى تجد ثغرة */
    let probe   = (partNumber % 30) + 1;   // يبدأ من +1 وقد يلتف بعد 30
    let steps   = 0;
    while (steps < 30 && heard.has(probe)) {
      probe = (probe % 30) + 1;            // يتحرّك مع التفاف
      steps++;
    }
    newCurrent = steps === 30 ? 30 : probe; // 30 ↦ كل الأجزاء مسموعة
  }

  /* ❽ التحديث فى قاعدة البيانات */
  await client.query(`
    UPDATE plans SET
      current_part        = $2,
      paused_for_official = $3,
      official_exams      = COALESCE($4::text[], '{}'),
      due_date = CASE
                  WHEN $3 THEN due_date
                  ELSE due_date + CASE duration_type WHEN 'week' THEN (duration_value * 7) ELSE duration_value END
                END

    WHERE id = $1`,
    [pl.id, newCurrent, pauseOfficial, official_exams]);
}





/**
 * ينشئ خطة جديدة بناءً على ما اختاره الطالب.
 * (نُبقى ‎paused_for_official‎ = false ما دام الطالب صرّح أنّه
 *  اجتاز كلّ الرسميات المذكورة؛ التحقق الواقعى يتمّ لاحقاً.)
 */
async function createPlan(
  studentId,
  official_attended,
  official_exams = [],
  parts_attended,
  parts_range_start,
  parts_range_end,
  continuation_mode,        // 'from_start' | 'from_end' | 'specific'
  specific_part,            // رقم الجزء إذا continuation_mode === 'specific'
  computedCurrent,          // current_part المحسوب أوليًا
  duration_type,            // 'week' أو 'day'
  duration_value,
  studentType               // 'regular' أو 'intensive'
) {
  /* ❶ التواريخ */
  const startDate = todayStr();
  const dueDate   = calculateDueDate(duration_type, duration_value);

  /* ❷ المؤشرات المبدئية */
  let current_part        = computedCurrent;
  let paused_for_official = false;      // لا نوقف الخطة هنا

  /* ❸ الحِزم الرسمية المطلوبة حتى ‎current_part‎ */
  if (parts_attended) {
    const edgeNumbers =
      studentType === 'regular'
        ? [5, 10, 15, 20, 25, 30]
        : [10, 15, 20, 30];

    const neededCodes = edgeNumbers
      .filter(n => n <= computedCurrent)
      .flatMap(n => requiredOfficialExam(studentType, n));

    const { rows: done } = await pool.query(`
      SELECT exam_code
        FROM exams
       WHERE student_id = $1
         AND official   = TRUE
         AND passed     = TRUE
         AND exam_code  = ANY($2)`,
      [studentId, neededCodes]);

    const passedCodes  = done.map(r => r.exam_code);
    const pendingCodes = neededCodes.filter(c => !passedCodes.includes(c));

    if (pendingCodes.length) {
      official_exams = Array.from(
        new Set([...(official_exams || []), ...pendingCodes])
      );
      paused_for_official = true;       // نوقف فقط إن وُجد ناقص حقيقى
    }
  }

  /* ❹ حفظ الخطة */
  const { rows } = await pool.query(`
    INSERT INTO plans (
       student_id,
       official_attended,
       official_exams,
       parts_attended,
       parts_range_start,
       parts_range_end,
       continuation_mode,
       specific_part,
       current_part,
       paused_for_official,
       start_date,
       due_date,
       duration_type,
       duration_value
     ) VALUES (
       $1,$2,COALESCE($3::text[], '{}'),$4,$5,$6,$7,$8,$9,$10,
       $11::date,$12::date,$13,$14
     )
     RETURNING *`,
    [
      studentId,
      official_attended,
      official_exams,
      parts_attended,
      parts_range_start,
      parts_range_end,
      continuation_mode,
      specific_part,
      current_part,
      paused_for_official,
      startDate,
      dueDate,
      duration_type,
      duration_value,
    ]
  );

  return rows[0];
}





/* ───────── util: فكّ إيقاف الخطة بعد نجاح رسمى ───────── */
async function clearOfficialPause(client, studentId, examCode) {
  // ① آخر خطة معتمَدة
  const { rows: [pl] } = await client.query(`
      SELECT id, official_exams, duration_value,
             student_type, current_part
        FROM plans
       WHERE student_id = $1 AND approved = TRUE
    ORDER BY created_at DESC
       LIMIT 1`, [studentId]);

  if (!pl) return;

  // ② أزل الامتحان الذى نجح فيه للتوّ
  const newList = (pl.official_exams || []).filter(c => c !== examCode);

  // ③ هل ما زال هناك أى كود ناقص؟
  const stillMissing = await Promise.all(
    newList.map(async code => {
      const { rowCount } = await client.query(`
        SELECT 1 FROM exams
         WHERE student_id = $1 AND exam_code = $2
           AND official = TRUE AND passed = TRUE
         LIMIT 1`, [studentId, code]);
      return rowCount === 0;           // true ↦ كود ناقص
    })
  ).then(arr => arr.some(Boolean));

  /* ④ استئناف الخطة من دون تحريك ‎current_part‎ –-
        سيظل المؤشِّر عند الجزء الحالى حتى يُنجَز امتحانه الرسمى فعلاً. */
  const newCurrent = pl.current_part;

  // ⑤ التحديث
  await client.query(`
      UPDATE plans SET
        official_exams      = COALESCE($2::text[], '{}'),
        paused_for_official = $3,
        current_part        = $4,
        due_date = CASE
                    WHEN $3 THEN due_date
                    ELSE due_date + CASE duration_type WHEN 'week' THEN (duration_value * 7) ELSE duration_value END
                  END
      WHERE id = $1`,
    [pl.id, newList, stillMissing, newCurrent]);
}





// جلب خطط طالب محدد
async function getPlansByStudent(studentId) {
  const { rows } = await pool.query(
    `SELECT p.*,
            to_char(p.start_date,'YYYY-MM-DD') AS start,
            to_char(p.due_date,'YYYY-MM-DD')   AS due,
            s.name AS student_name
     FROM plans p
     JOIN students s ON s.id = p.student_id
     WHERE p.student_id = $1
     ORDER BY p.created_at DESC`,
    [studentId]
  );
  return rows;
}

// REPLACE this whole function
async function getPlansByCollege(college) {
  const { rows } = await pool.query(
    `SELECT p.*,
            to_char(p.start_date,'YYYY-MM-DD') AS start,
            to_char(p.due_date,'YYYY-MM-DD')   AS due,
            s.name AS student_name,
            /* كانت موجودة سابقًا */
            CASE WHEN now()::date <= p.due_date THEN TRUE ELSE FALSE END AS on_time,
            (now()::date - p.due_date) AS late_days,
            /* الجديد: اعتباره متأخرًا فقط إذا تجاوز due_date+2
               ولا يوجد طلب امتحان جزء لنفس الجزء الحالي */
            (
              now()::date > p.due_date + 2
              AND NOT EXISTS (
                SELECT 1
                  FROM exam_requests er
                 WHERE er.student_id = p.student_id
                   AND er.kind       = 'part'
                   AND er.part       = p.current_part
              )
            ) AS is_overdue
     FROM plans p
     JOIN students s ON s.id = p.student_id
     WHERE s.college = $1
     ORDER BY p.due_date`,
    [college]
  );
  return rows;
}




/* ───────── App ───────── */
const app = express();
app.use(cors());
app.use(bodyParser.json());

/* ───── PG ───── */
const pool = new Pool({
  user    : process.env.DB_USER,
  host    : process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port    : process.env.DB_PORT
});
pool.connect()
  .then(c => { c.release(); console.log('✅ PG connected'); })
  .catch(e => console.error('❌ PG error', e));


async function migrateExistingPlans() {
  const plans = (await pool.query(`
    SELECT id, student_id, parts_attended, parts_range_start, 
           parts_range_end, official_attended, official_exams
      FROM plans WHERE approved = TRUE
  `)).rows;

  for (const p of plans) {
    // أجزاء
    if (p.parts_attended) {
      for (let i = p.parts_range_start; i <= p.parts_range_end; i++) {
        const code = 'J' + String(i).padStart(2,'0');
        await pool.query(`
          INSERT INTO exams
            (student_id, exam_code, passed, official, created_at)
          VALUES ($1,$2,TRUE,FALSE,now()::date)
          ON CONFLICT (student_id, exam_code, official) DO NOTHING
        `, [p.student_id, code]);
      }
    }
    // رسمي
    if (p.official_attended && Array.isArray(p.official_exams)) {
      for (const code of p.official_exams) {
        await pool.query(`
          INSERT INTO exams
            (student_id, exam_code, passed, official, created_at)
          VALUES ($1,$2,TRUE,TRUE,now()::date)
          ON CONFLICT (student_id, exam_code, official) DO NOTHING
        `, [p.student_id, code]);
      }
    }
  }
  console.log('Migration done');
}

if (process.env.RUN_MIGRATION === '1') {
  migrateExistingPlans().catch(console.error);
}



/* ───── Mail ───── */
const mailer = nodemailer.createTransport({
  host  : process.env.SMTP_HOST,
  port  : +process.env.SMTP_PORT,
  secure: false,
  auth  : { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
});

/* ───── JWT ───── */
const auth = (req,res,next)=>{
  const token = req.headers.authorization?.split(' ')[1];
  if(!token) return res.status(401).json({message:'token'});
  jwt.verify(token,process.env.JWT_SECRET,(e,u)=>{
    if(e) return res.status(403).json({message:'bad token'});
    req.user = u;
    next();
  });
};

/* ───── ثوابت ───── */
const VALID_COLLEGES = [
  'Engineering', 'Medical', 'Sharia',
  'NewCampus', 'OldCampus', 'Agriculture'
];


const VALID_CODES    = ['F1','F2','F3','F4','F5','F6','T1','T2','T3','H1','H2','Q'];
// functions for official exam registration
async function getOfficialRegistration(scope) {
  const { rows } = await pool.query(
    "SELECT disabled_from, disabled_until FROM exam_registration WHERE type='official' AND gender_scope = $1 LIMIT 1",
    [scope || 'both']
  );
  return rows[0] || { disabled_from: null, disabled_until: null };
}
// الرسمي
async function setOfficialRegistration(from, until, scope='both') {
  await pool.query(`
    INSERT INTO exam_registration (type, gender_scope, disabled_from, disabled_until)
    VALUES ('official', $1, $2, $3)
    ON CONFLICT (type, gender_scope) WHERE (type = 'official')
    DO UPDATE SET
      disabled_from = EXCLUDED.disabled_from,
      disabled_until = EXCLUDED.disabled_until;

  `, [scope, from, until]);
}



async function getPartRegistration(college) {
  const { rows } = await pool.query(
    "SELECT disabled_from, disabled_until FROM exam_registration WHERE type='part' AND college=$1 LIMIT 1",
    [college]
  );
  return rows[0] || { disabled_from: null, disabled_until: null };
}

// الأجزاء
async function setPartRegistration(college, from, until) {
  await pool.query(`
    INSERT INTO exam_registration (type, college, disabled_from, disabled_until)
    VALUES ('part', $1, $2, $3)
    ON CONFLICT (type, college) WHERE (type = 'part')
    DO UPDATE SET
      disabled_from = EXCLUDED.disabled_from,
      disabled_until = EXCLUDED.disabled_until;

  `, [college, from, until]);
}



/* ─────────────────── ترقية الطالب إلى حافظ ─────────────────── */
async function promoteIfQualified(stuId) {
  const sRes = await pool.query(
    'SELECT id, name, email, student_type, is_hafidh FROM students WHERE id=$1',
    [stuId]
  );
  if (!sRes.rowCount) return;
  const s = sRes.rows[0];
  if (s.is_hafidh) return;

  const { rows: ex } = await pool.query(`
    SELECT exam_code, created_at
      FROM exams
     WHERE student_id=$1 AND passed AND official`, [stuId]
  );
  if (!ex.length) return;

  const have    = ex.map(r=>r.exam_code);
  const needReg = ['F1','F2','F3','F4','F5','F6'];
  const needInt = ['T1','T2','T3','H1','H2','Q'];

  const ok = (s.student_type === 'regular')
      ? needReg.every(c=>have.includes(c))
      : needInt.every(c=>have.includes(c));
  if (!ok) return;

  const lastDate = ex.reduce((m,r)=> (r.created_at>m? r.created_at : m), ex[0].created_at);
  const dStr = toDateStr(lastDate) || todayStr();

  await pool.query(`
     UPDATE students
        SET is_hafidh   = TRUE,
            hafidh_date = $2::date
      WHERE id = $1`, [stuId, dStr]);

  await pool.query(`
    INSERT INTO hafadh (student_id, hafidh_date)
    VALUES ($1,$2::date)
    ON CONFLICT (student_id) DO UPDATE
      SET hafidh_date = EXCLUDED.hafidh_date`, [stuId, dStr]);

  if (s.email) {
    try{
      await mailer.sendMail({
        from   : `"Quran App" <${process.env.SMTP_USER}>`,
        to     : s.email,
        subject: '🌟 مبااارك — أنت حافظ الآن!',
        text   :
`أخي/أختي ${s.name}،

مبارك ختم القرآن الكريم وفق النظام المعتمد في الملتقى، ونسأل الله لك القَبول.

هنيئاً لك تواجد اسمك في قائمة الحفل القادم في ملتقى القرآن الكريم.

إدارة ملتقى القرآن الكريم`
      });
    }catch(e){ console.error('✉️ خطأ الإيميل', e.message); }
  }
  console.log(`🎉 الطالب ${stuId} صار حافظاً`);
}


/* ═════════════════════ 1) CRUD الطلاب ═════════════════════ */

app.post('/api/students', auth, async (req, res) => {
  const allowedRoles = ['admin_dashboard','admin_dash_f'];
  if (!allowedRoles.includes(req.user.role))
    return res.status(403).json({ message: 'غير مخوَّل' });

  const { value: v, error } = Joi.object({
    reg_number   : Joi.string().max(50).required(),
    name         : Joi.string().min(3).max(100).required(),
    phone        : Joi.string().max(20).allow('', null),
    email        : Joi.string().email().allow('', null),
    college      : Joi.string().valid(...VALID_COLLEGES).required(),
    supervisor_id: Joi.number().integer().allow(null),
    student_type : Joi.string().valid('regular','intensive').required(),
    password     : Joi.string().min(4).max(50).default('123456'),
    // ✅ أزلنا الافتراضي "female" وخليّنا الحقل اختياري
    gender       : Joi.string().valid('male','female').optional()
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  const emailNorm = v.email?.trim() || null;

  // منع التكرار
  const dup = await pool.query(
    `SELECT 1 FROM students WHERE reg_number=$1 OR (email IS NOT NULL AND email=$2)`,
    [v.reg_number, emailNorm]
  );
  if (dup.rowCount) return res.status(400).json({ message: 'رقم أو بريد مكرر' });

  // 🔽 احسب الجنس لو لم يُرسل من الواجهة اعتمادًا على الكلية
  const femaleSet = new Set(FEMALE_COLLEGES);
  const gender = v.gender ?? (femaleSet.has(v.college) ? 'female' : 'male');

  // هاش كلمة السر
  const hash = await bcrypt.hash(v.password, 10);

  // الإدراج
  await pool.query(
    `
    INSERT INTO students
      (reg_number, name, password, phone, email, college, supervisor_id, student_type, gender)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
    `,
    [v.reg_number, v.name, hash, v.phone, emailNorm, v.college, v.supervisor_id, v.student_type, gender]
  );

  res.status(201).json({ message: 'تمت الإضافة' });
});


app.get('/api/students', auth, async (req, res) => {
  if (!requireAdmin(req,res)) return;
  const gender = req.query.gender;
  const params = [];
  const where = [];

  // NEW: فرض الجنس حسب الدور لو لم يُرسل بالـ query
  if (!gender) {
    if (req.user.role === 'admin_dash_f') {
      params.push('female'); where.push(`s.gender = $${params.length}`);
    } else if (req.user.role === 'admin_dashboard') {
      params.push('male');   where.push(`s.gender = $${params.length}`);
    }
  } else {
    params.push(gender); where.push(`s.gender = $${params.length}`);
  }

  // تقييد الكلية لغير admin_dashboard
  if (req.user.role !== 'admin_dashboard' && req.user.college) {
    params.push(req.user.college);
    where.push(`s.college = $${params.length}`);
  }

  // مسؤولة مجمّع بنات (إن له college نسائي)
  const FEMALE_COLLEGES = ['NewCampus','OldCampus','Agriculture'];
  if (FEMALE_COLLEGES.includes(req.user.college)) {
    params.push('female');
    where.push(`s.gender = $${params.length}`);
  }

  const sql = `
    SELECT s.*, sp.name AS supervisor_name
      FROM students s
      LEFT JOIN supervisors sp ON sp.id = s.supervisor_id
     ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
     ORDER BY s.id`;
  const { rows } = await pool.query(sql, params);
  res.json(rows);
});




app.put('/api/students/:id', auth, async (req,res)=>{
  const allowedRoles = ['admin_dashboard','admin_dash_f'];
  if (!allowedRoles.includes(req.user.role))
    return res.status(403).json({ message: 'غير مخوَّل' });

  const { value:v, error } = Joi.object({
    name        : Joi.string().min(3).max(100).required(),
    phone       : Joi.string().max(20).allow('',null),
    email       : Joi.string().email().allow('',null),
    college     : Joi.string().valid(...VALID_COLLEGES).required(),
    supervisor_id: Joi.number().integer().allow(null),
    student_type: Joi.string().valid('regular','intensive').required()
  }).validate(req.body);
  if (error) return res.status(400).json({ message:error.message });

  const id = +req.params.id;
  const emailNorm = v.email?.trim() || null;

  const { rowCount } = await pool.query(`
    UPDATE students SET
      name=$1, phone=$2, email=$3, college=$4,
      supervisor_id=$5, student_type=$6
    WHERE id=$7`,
    [v.name, v.phone, emailNorm, v.college, v.supervisor_id, v.student_type, id]
  );
  if(!rowCount) return res.status(404).json({message:'لم يُوجد'});
  res.json({message:'تم التعديل'});
});

app.delete('/api/students/:id', auth, async (req,res)=>{
  const { rowCount } = await pool.query('DELETE FROM students WHERE id=$1',[+req.params.id]);
  if(!rowCount) return res.status(404).json({message:'غير موجود'});
  res.json({message:'تم الحذف'});
});


/* ═════════════════════ 2) CRUD المشرفين ═════════════════════ */

// حقوق: admin_dashboard فقط
app.get('/api/colleges', auth, async (req,res)=>{
  if (req.user.role!=='admin_dashboard') return res.status(403).json({message:'ممنوع'});
  const { rows } = await pool.query('SELECT * FROM colleges WHERE active = TRUE ORDER BY id');
  res.json(rows);
});

app.post('/api/colleges', auth, async (req,res)=>{
  if (req.user.role!=='admin_dashboard') return res.status(403).json({message:'ممنوع'});
  const { code, name_ar, gender_scope='both' } = req.body;
  await pool.query(
    `INSERT INTO colleges (code, name_ar, gender_scope) VALUES ($1,$2,$3)`,
    [code, name_ar, gender_scope]
  );
  res.status(201).json({message:'تمت إضافة الكلية'});
});

// تعيين مسؤول لكلية من الواجهة
app.post('/api/colleges/:code/assign-admin', auth, async (req,res)=>{
  if (req.user.role!=='admin_dashboard') return res.status(403).json({message:'ممنوع'});
  const { user_id } = req.body;
  const code = req.params.code;

  // بنحدّث المستخدم: نقشّط role عام ونعطيه college
  await pool.query(
    `UPDATE users SET role = 'CollegeAdmin', college = $2 WHERE id = $1`,
    [user_id, code]
  );
  res.json({message:'تم تعيين المسؤول'});
});


/* GET /api/supervisors
   — يرجع مشرفي نفس الجهة تلقائيًا:
     • مسؤول عام (admin_dashboard): ذكور فقط
     • مسؤولة البنات (admin_dash_f): إناث فقط
     • CollegeAdmin: من كليّته فقط، والجنس يُستدلّ (إن كانت كليته من كليات البنات → إناث)
     • طالب: من كليته فقط + نفس جنسه (بناءً على التوكن) */
app.get('/api/supervisors', auth, async (req,res)=>{
  const gender = req.query.gender; // اختياري
  const params = [];
  const where = ['1=1'];

  // ❶ حسم الجنس حسب الدور إذا لم يُرسل
  if (!gender) {
    if (req.user.role === 'admin_dash_f') {
      params.push('female'); where.push(`gender = $${params.length}`);
    } else if (req.user.role === 'admin_dashboard') {
      params.push('male');   where.push(`gender = $${params.length}`);
    } else if (!ADMIN_ROLES.includes(req.user.role)) {
      // مستخدم عادي (طالب/مشرف) → حسب جنسه في التوكن
      const g = (req.user.gender === 'female') ? 'female' : 'male';
      params.push(g); where.push(`gender = $${params.length}`);
    }
  } else {
    params.push(gender); where.push(`gender = $${params.length}`);
  }

  // ❷ تقييد الكلية للمسؤولين الفرعيين والطلاب
  if (ADMIN_ROLES.includes(req.user.role)) {
    if (req.user.role !== 'admin_dashboard' && req.user.college) {
      params.push(req.user.college);
      where.push(`college = $${params.length}`);
    }
    // مسؤولة مجمّع بنات (إن كانت كليتها نسائية)
    const FEMALE_COLLEGES = ['NewCampus','OldCampus','Agriculture'];
    if (FEMALE_COLLEGES.includes(req.user.college)) {
      params.push('female');
      where.push(`gender = $${params.length}`);
    }
  } else {
    // طالب: حصراً من كليّته
    if (req.user.college) {
      params.push(req.user.college);
      where.push(`college = $${params.length}`);
    }
  }

  const { rows } = await pool.query(`
    SELECT id, reg_number, name, phone, email, college, gender,
           COALESCE(is_regular,false)  AS is_regular,
           COALESCE(is_trial,false)    AS is_trial,
           COALESCE(is_doctor,false)   AS is_doctor,
           COALESCE(is_examiner,false) AS is_examiner
      FROM supervisors
     WHERE ${where.join(' AND ')}
  ORDER BY college, name`, params);

  res.json(rows);
});



app.post('/api/supervisors', auth, async (req, res) => {
  const allowedRoles = ['EngAdmin','MedicalAdmin','shariaAdmin','admin_dashboard','CollegeAdmin','admin_dash_f'];
  if (!allowedRoles.includes(req.user.role))
    return res.status(403).json({ message: 'غير مخوَّل' });

  const { value:v, error } = Joi.object({
    name        : Joi.string().min(3).max(100).required(),
    phone       : Joi.string().max(20).allow('',null),
    email       : Joi.string().email().allow('',null),
    college     : Joi.string().valid(...VALID_COLLEGES).required(),
    is_regular  : Joi.boolean().default(true),
    is_trial    : Joi.boolean().default(false),
    is_doctor   : Joi.boolean().default(false),
    is_examiner : Joi.boolean().default(false),
    gender      : Joi.string().valid('male','female').default('male')
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  const reg = crypto.randomUUID();
  const emailNorm = v.email?.trim() || null;

  await pool.query(`
    INSERT INTO supervisors
      (reg_number, name, phone, email, college,
       is_regular, is_trial, is_doctor, is_examiner, gender)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
    [reg, v.name, v.phone, emailNorm, v.college,
     v.is_regular, v.is_trial, v.is_doctor, v.is_examiner, v.gender]
  );

  res.status(201).json({ message:'تم إضافة المشرف' });
});


app.put('/api/supervisors/:id', auth, async (req, res) => {
  const allowedRoles = ['EngAdmin','MedicalAdmin','shariaAdmin','admin_dashboard','CollegeAdmin','admin_dash_f'];
  if (!allowedRoles.includes(req.user.role))
    return res.status(403).json({ message: 'غير مخوَّل' });

  const { value:v, error } = Joi.object({
    name        : Joi.string().min(3).max(100).required(),
    phone       : Joi.string().max(20).allow('',null),
    email       : Joi.string().email().allow('',null),
    college     : Joi.string().valid(...VALID_COLLEGES).required(),
    is_regular  : Joi.boolean().default(true),
    is_trial    : Joi.boolean().default(false),
    is_doctor   : Joi.boolean().default(false),
    is_examiner : Joi.boolean().default(false),
    gender      : Joi.string().valid('male','female').default('male')
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  const id = +req.params.id;
  const emailNorm = v.email?.trim() || null;

  const { rowCount } = await pool.query(`
    UPDATE supervisors SET
      name=$1, phone=$2, email=$3, college=$4,
      is_regular=$5, is_trial=$6, is_doctor=$7, is_examiner=$8, gender=$9
    WHERE id=$10`,
    [v.name, v.phone, emailNorm, v.college,
     v.is_regular, v.is_trial, v.is_doctor, v.is_examiner, v.gender, id]
  );
  if (!rowCount) return res.status(404).json({ message:'غير موجود' });
  res.json({ message:'تم التحديث' });
});


app.delete('/api/supervisors/:id', auth, async (req,res)=>{
  const { rowCount } = await pool.query('DELETE FROM supervisors WHERE id=$1',[+req.params.id]);
  if(!rowCount) return res.status(404).json({message:'غير موجود'});
  res.json({message:'تم الحذف'});
});

/* واجهة عامة: مشرفون منتظمون فقط (للشاشات العامة إن وُجدت) */
app.get('/api/public/regular-supervisors', async (req, res) => {
  const params = [];
  const where  = ['is_regular = TRUE'];

  if (req.query.college) {
    params.push(req.query.college);
    where.push(`college = $${params.length}`);
  }
  if (req.query.gender) {
    params.push(req.query.gender);
    where.push(`gender  = $${params.length}`);
  }

  const { rows } = await pool.query(`
    SELECT id, name, college, gender
      FROM supervisors
     WHERE ${where.join(' AND ')}
  ORDER BY name`, params);

  // حماية إضافية: لا نُظهر مشرفات إلا لو كان gender=female أو الكلية نسائية
  const FEMALE_COLLEGES = ['NewCampus','OldCampus','Agriculture'];
  const col = req.query.college;
  const allowFemales = req.query.gender === 'female' || (col && FEMALE_COLLEGES.includes(col));
  const safe = allowFemales ? rows : rows.filter(r => r.gender !== 'female');

  res.json(safe);
});


// إنشاء طلب
app.post('/api/supervisor-change-requests', auth, async (req,res)=>{
  const { desired_supervisor_id, reason='' } = req.body;
  // تأكد أن الطالبة أنثى وأن المفضّل مشرفة أنثى ومن نفس الكلية
  const { rows: curRows } = await pool.query(
    'SELECT supervisor_id FROM students WHERE id=$1',[req.user.id]);
  const cur = curRows[0]?.supervisor_id || null;

  await pool.query(`
    INSERT INTO supervisor_change_requests
      (student_id,current_supervisor_id,desired_supervisor_id,reason)
    VALUES ($1,$2,$3,$4)`,
    [req.user.id, cur, desired_supervisor_id, reason]
  );
  res.status(201).json({message:'تم إرسال الطلب'});
});

app.get('/api/supervisor-change-requests', auth, async (req,res)=>{
  const role = req.user.role;
  const ps = [];
  let where = `r.status='pending'`;

  if (role === 'admin_dashboard') {
    where += ` AND s.gender='male'`;
  } else if (role === 'admin_dash_f') {
    where += ` AND s.gender='female'`;
  } else if (role === 'CollegeAdmin') {
    ps.push(req.user.college);
    where += ` AND s.college = $${ps.length}`;
  } else {
    return res.status(403).json({message:'ممنوع'});
  }

  if (req.query.college && role !== 'CollegeAdmin') {
    ps.push(req.query.college);
    where += ` AND s.college = $${ps.length}`;
  }

  const { rows } = await pool.query(`
    SELECT r.*,
           s.name    AS student_name,
           s.college AS college,
           s.gender  AS student_gender,
           cur.name  AS current_name,
           sv.name   AS desired_name
      FROM supervisor_change_requests r
      JOIN students s       ON s.id  = r.student_id
      LEFT JOIN supervisors cur ON cur.id = r.current_supervisor_id
      LEFT JOIN supervisors sv  ON sv.id  = r.desired_supervisor_id
     WHERE ${where}
  ORDER BY r.id DESC`, ps);

  res.json(rows);
});



app.post('/api/supervisor-change-requests/:id/resolve', auth, async (req,res)=>{
  if (!['CollegeAdmin','admin_dash_f','admin_dashboard'].includes(req.user.role))
    return res.status(403).json({message:'ممنوع'});

  const { approve, supervisor_id } = req.body;
  const client = await pool.connect();

  try{
    await client.query('BEGIN');

    const { rows } = await client.query(`
      SELECT r.student_id,
             r.desired_supervisor_id,
             s.college,
             s.gender AS student_gender
        FROM supervisor_change_requests r
        JOIN students s ON s.id = r.student_id
       WHERE r.id=$1
       FOR UPDATE`,
      [+req.params.id]
    );
    if (!rows.length) { await client.query('ROLLBACK'); return res.status(404).json({message:'غير موجود'}); }

    const sid        = rows[0].student_id;
    const stCollege  = rows[0].college;
    const stGender   = rows[0].student_gender; // male أو female
    const desiredId  = rows[0].desired_supervisor_id;

    // CollegeAdmin لا يعتمد لكلية أخرى
    if (req.user.role==='CollegeAdmin' && req.user.college !== stCollege) {
      await client.query('ROLLBACK');
      return res.status(403).json({message:'طلب يخص كلية أخرى'});
    }

    if (approve) {
      const finalSupId = supervisor_id ?? desiredId;
      if (!finalSupId) {
        await client.query('ROLLBACK');
        return res.status(400).json({message:'لا يوجد مشرف مقترح في الطلب'});
      }

      // تحقق: نفس جنس الطالب + نفس الكلية
      const { rows: supRows } = await client.query(
        'SELECT gender, college FROM supervisors WHERE id=$1',[finalSupId]
      );
      if (!supRows.length ||
          supRows[0].gender !== stGender ||
          supRows[0].college !== stCollege) {
        await client.query('ROLLBACK');
        return res.status(400).json({message:'مشرف غير صالح للجنس/الكلية'});
      }

      await client.query('UPDATE students SET supervisor_id=$1 WHERE id=$2',[finalSupId, sid]);
      await client.query(`
        UPDATE supervisor_change_requests
           SET status='approved', processed_by=$1, processed_at=now()
         WHERE id=$2`, [req.user.id, +req.params.id]);
    } else {
      await client.query(`
        UPDATE supervisor_change_requests
           SET status='rejected', processed_by=$1, processed_at=now()
         WHERE id=$2`, [req.user.id, +req.params.id]);
    }

    await client.query('COMMIT');
    res.json({message:'تم'});
  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    res.status(500).json({message:'خطأ'});
  } finally {
    client.release();
  }
});



app.delete('/api/supervisor-change-requests/:id', auth, async (req,res)=>{
  if (!['CollegeAdmin','admin_dash_f','admin_dashboard'].includes(req.user.role))
    return res.status(403).json({message:'ممنوع'});

  const id = +req.params.id;
  const client = await pool.connect();
  try{
    await client.query('BEGIN');
    const { rows } = await client.query(`
      SELECT s.college
        FROM supervisor_change_requests r
        JOIN students s ON s.id = r.student_id
       WHERE r.id = $1`, [id]);
    if(!rows.length){
      await client.query('ROLLBACK');
      return res.status(404).json({message:'غير موجود'});
    }
    const stCollege = rows[0].college;
    if (req.user.role==='CollegeAdmin' && req.user.college !== stCollege) {
      await client.query('ROLLBACK');
      return res.status(403).json({message:'طلب يخص كلية أخرى'});
    }

    await client.query('DELETE FROM supervisor_change_requests WHERE id=$1',[id]);
    await client.query('COMMIT');
    res.json({message:'تم الحذف'});
  }catch(e){
    await client.query('ROLLBACK');
    console.error('delete scr error', e);
    res.status(500).json({message:'خطأ في الحذف'});
  }finally{
    client.release();
  }
});




/* ═════════════════════ 3) الامتحانات ═════════════════════ */
// نقطة النهاية لفحص حالة تسجيل الأجزاء
app.get('/api/settings/part-exam-registration', auth, async (req, res) => {
  const college = req.query.college;
  if (!college || !VALID_COLLEGES.includes(college)) {
    return res.status(400).json({ message: 'يجب تحديد كلية صالحة' });
  }

  const { rows } = await pool.query(
    `SELECT disabled_from, disabled_until 
     FROM exam_registration 
     WHERE type = 'part' AND college = $1`,
    [college]
  );

  if (rows.length === 0) {
    return res.json({ disabledFrom: null, disabledUntil: null });
  }

  const result = rows[0];
  res.json({
    disabledFrom: result.disabled_from 
        ? new Date(result.disabled_from).toISOString().split('T')[0] 
        : null,
    disabledUntil: result.disabled_until 
        ? new Date(result.disabled_until).toISOString().split('T')[0] 
        : null
  });
});

// PATCH /api/settings/part-exam-registration
// body: { college: 'Engineering', from: '2025-07-28', until: '2025-08-10' }
app.patch('/api/settings/part-exam-registration', auth, async (req, res) => {
  const { college, from, until } = req.body;
  if (!college || !VALID_COLLEGES.includes(college)) {
    return res.status(400).json({ message: 'college مطلوب' });
  }
  await setPartRegistration(college, from || null, until || null);
  const row = await getPartRegistration(college);
  return res.json(row);
});


app.get('/api/settings/exam-registration', auth, async (req,res)=>{
  const scope = req.query.gender === 'female' ? 'female' : 'both';
  const row = await getOfficialRegistration(scope);
  const fmt = x => toDateStr(x); 
  res.json({
    disabledFrom: fmt(row.disabled_from),
    disabledUntil: fmt(row.disabled_until)
  });
});


app.patch('/api/settings/exam-registration', auth, async (req,res)=>{
  const scope = req.query.gender === 'female' ? 'female' : 'both';
  const { from, until } = req.body;
  await setOfficialRegistration(from || null, until || null, scope);
  res.json(await getOfficialRegistration(scope));
});



// ------------------------------
// POST /api/exams
// ------------------------------
app.post('/api/exams', auth, async (req, res) => {
  /* ❶ التحقق من المدخلات */
  const { value: v, error } = Joi.object({
    student_id : Joi.number().integer().required(),
    exam_code  : Joi.string()
                     .regex(/^(J(0[1-9]|[12][0-9]|30)|F[1-6]|T[1-3]|H[12]|Q)$/)
                     .required(),
    passed     : Joi.boolean().required(),
    official   : Joi.boolean().required(),
    created_at : Joi.date().optional(),
    request_id : Joi.number().integer().allow(null)
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });
  const createdAt = toDateStr(v.created_at) || todayStr();

  /* ❷ الإدراج (أو الدمج) */
  const { rows: [row] } = await pool.query(`
    INSERT INTO exams
      (student_id, exam_code, passed, official, score,
       request_id, created_at)
    VALUES ($1,$2,$3,$4,NULL,$5,$6::date)
    ON CONFLICT ON CONSTRAINT exams_unique_student_exam_official
    DO UPDATE SET
      passed     = EXCLUDED.passed,
      official   = EXCLUDED.official,
      score      = EXCLUDED.score,
      created_at = EXCLUDED.created_at,
      request_id = COALESCE(EXCLUDED.request_id, exams.request_id)
    RETURNING request_id
  `, [
    v.student_id,
    v.exam_code,
    v.passed,
    v.official,
    v.request_id || null,
    createdAt
  ]);

  const isPart = v.exam_code.startsWith('J');

  /* ❸ هل هو امتحان إعادة part؟ */
  let isRedo = false;
  if (row.request_id) {
    const { rows:[rq] } = await pool.query(
      'SELECT run_mode FROM exam_requests WHERE id=$1',
      [row.request_id]
    );
    isRedo = rq && rq.run_mode === 'redo';
  }

  /* ───────────────────────── (أ) نجاح امتحان جزء ───────────────────────── */
  if (isPart && v.passed && !isRedo) {
   const partNum = parseInt(v.exam_code.slice(1), 10);   // J05 → 5
   await advancePlanAfterPartSuccess(pool, v.student_id, partNum);
 }

  /* ───────────────────────── (ب) نجاح امتحان رسمى ───────────────────────── */
 if (v.passed && v.official) {
   await clearOfficialPause(pool, v.student_id, v.exam_code);
   await promoteIfQualified(v.student_id);   // كما كان
 }

  return res.status(201).json({ message: 'تم تسجيل الامتحان' });
});



app.delete('/api/exams/:id', auth, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1) احصل على بيانات الامتحان (request_id, official, exam_code, student_id)
    const { rows } = await client.query(
      `SELECT request_id, official, exam_code, student_id
         FROM exams
        WHERE id = $1`,
      [+req.params.id]
    );
    if (!rows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'الامتحان غير موجود' });
    }
    const { request_id, official, exam_code, student_id } = rows[0];

    // 2) إذا مرتبط بطلب، احذف أولاً كل الدرجات المرتبطة ثم احذف الطلب نفسه
    if (request_id) {
      await client.query(
        `DELETE FROM exams
           WHERE request_id = $1`,
        [request_id]
      );
      await client.query(
        `DELETE FROM exam_requests
           WHERE id = $1`,
        [request_id]
      );
    } else {
      // خلاف ذلك احذف السجل المنفرد
      await client.query(
        `DELETE FROM exams
           WHERE id = $1`,
        [+req.params.id]
      );
    }

    // 3) لو الامتحان رسمي: أوقِف الخطة وأضِف الكود إلى قائمة الرسميات المطلوبة
    if (official) {
      const { rows: [pl] } = await client.query(`
        SELECT id, official_exams, current_part
          FROM plans
         WHERE student_id = $1 AND approved = TRUE
      ORDER BY created_at DESC
         LIMIT 1`, [student_id]);

      if (pl) {
        const pending = new Set(pl.official_exams || []);
        pending.add(exam_code); // الامتحان المحذوف يعود لقائمة النواقص

        const newCurrent = edgePartFromOfficialExam(exam_code) || pl.current_part;

        await client.query(`
          UPDATE plans SET
            paused_for_official = TRUE,
            official_exams      = $2,
            current_part        = $3
          WHERE id = $1
        `, [pl.id, Array.from(pending), newCurrent]);
      }
    }

    await client.query('COMMIT');
    return res.json({ message: 'تم حذف الامتحان وإلغاء الطلب بنجاح' });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('❌ Error deleting exam:', e);
    return res.status(500).json({ message: 'خطأ أثناء الحذف' });
  } finally {
    client.release();
  }
});






// ------------------------------
// POST /api/grade
// ------------------------------
app.post('/api/grade', auth, async (req, res) => {
  /* ❶ التحقق من صحة المدخلات */
  const { value: v, error } = Joi.object({
    request_id: Joi.number().integer().optional().allow(null),
    exam_id   : Joi.number().integer().optional().allow(null),
    score     : Joi.number().precision(2).min(0).max(100).required(),
    stage     : Joi.string().valid('part','trial','official')
  })
    .xor('request_id','exam_id')
    .with('request_id','stage')
    .without('stage','exam_id')
    .validate(req.body);

  if (error) return res.status(400).json({ message: error.message });
  const passed = v.score >= PASS_MARK;

  /* ═════════════════ الرصد عبر request_id ═════════════════ */
  if (v.request_id != null) {
    /* 1) جلب الطلب */
    const { rows: erRows } = await pool.query(
      'SELECT * FROM exam_requests WHERE id = $1 AND approved = TRUE',
      [v.request_id]
    );
    if (!erRows.length) {
      return res.status(404).json({ message: 'طلب غير موجود أو غير معتمد' });
    }
    const er       = erRows[0];
    const isRedo   = er.kind === 'part' && er.run_mode === 'redo';
    const isPart   = er.kind === 'part';
    const official = isPart || v.stage === 'official';
    const dateStr  = toDateStr(
      isPart ? er.date :
      v.stage === 'trial' ? er.trial_date :
                            er.official_date
    ) || todayStr();

    /* 2) إدراج/تحديث السجل فى exams */
    await pool.query(`
      INSERT INTO exams
        (student_id, exam_code, passed, official, score,
         request_id, created_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7::date)
      ON CONFLICT ON CONSTRAINT exams_unique_student_exam_official
      DO UPDATE SET
        passed     = EXCLUDED.passed,
        official   = EXCLUDED.official,
        score      = EXCLUDED.score,
        created_at = EXCLUDED.created_at,
        request_id = EXCLUDED.request_id
    `, [
      er.student_id,
      isPart ? 'J' + er.part.toString().padStart(2,'0') : er.exam_code,
      passed,
      official,
      v.score,
      v.request_id,
      dateStr
    ]);

    /* 3) إلغاء الطلب إذا كان إعادة */
    if (isRedo) {
      await pool.query(
        'UPDATE exam_requests SET approved = FALSE WHERE id = $1',
        [v.request_id]
      );
    }

    /* 4-أ) نجاح جزء J (وليس إعادة) */
    if (passed && isPart && !isRedo) {
      await advancePlanAfterPartSuccess(pool, er.student_id, er.part);
    }

    /* 4-ب) نجاح رسمى */
    if (passed && v.stage === 'official') {          // أى امتحان رسمى (trial أو official)
      await clearOfficialPause(pool, er.student_id, er.exam_code);
      await promoteIfQualified(er.student_id);
    }

    /* 5) معالجة الرسوب */
    if (!passed) {
      if (isPart) {
        await pool.query(
          'UPDATE exam_requests SET approved = FALSE WHERE id = $1',
          [v.request_id]
        );
      } else if (official) {
        await pool.query(`
          UPDATE exam_requests
             SET approved               = FALSE,
                 supervisor_official_id = NULL,
                 official_date          = NULL
           WHERE id = $1
        `, [v.request_id]);
      }
    }

    return res.json({ message: 'تم رصد/تعديل العلامة' });
  }

  /* ═════════════════ الرصد المباشر عبر exam_id ═════════════════ */
  const { rows: updRows } = await pool.query(`
    UPDATE exams
       SET score  = $1,
           passed = $2
     WHERE id     = $3
    RETURNING request_id,
           official,
           student_id,
           exam_code
  `, [v.score, passed, v.exam_id]);

  if (!updRows.length) {
    return res.status(404).json({ message: 'الامتحان غير موجود' });
  }

  if (updRows[0].official && passed) {
    await clearOfficialPause(
      pool,
      updRows[0].student_id,
      updRows[0].exam_code
    );
    await promoteIfQualified(updRows[0].student_id);
  }

  return res.json({ message: 'تم رصد/تعديل العلامة' });
});





// 1) حذف الدرجة وإلغاء الطلب المرتبط حتى يمكن تقديم طلب جديد
app.delete('/api/grade/:requestId', auth, async (req, res) => {
  const requestId = +req.params.requestId;

  // ١) تأكّد من وجود الطلب أولاً
  const { rows: rq } = await pool.query(
    'SELECT id FROM exam_requests WHERE id = $1',
    [requestId]
  );
  if (!rq.length) {
    return res.status(404).json({ message: 'الطلب غير موجود' });
  }

  // ٢) احذف جميع السجلات في جدول exams المرتبطة بهذا الطلب
  const del = await pool.query(
    'DELETE FROM exams WHERE request_id = $1 RETURNING *',
    [requestId]
  );
  if (!del.rowCount) {
    return res.status(404).json({ message: 'لا توجد درجات للحذف' });
  }

  // ٣) احذف صفّ الطلب نفسه ليصبح بالإمكان تقديم طلب جديد
  await pool.query(
    'DELETE FROM exam_requests WHERE id = $1',
    [requestId]
  );

  // ٤) أرسل الاستجابة
  res.json({
    message: 'تم حذف العلامات وإلغاء الطلب، يمكنك التقديم مرة أخرى',
    deletedExams: del.rowCount
  });
});




/* تقارير رسمية */
app.get('/api/exams/official', auth, async (req,res)=>{
  const { start, end } = req.query;
  let gender = req.query.gender;
  const params=[];
  let where = `e.official = TRUE AND e.exam_code NOT LIKE 'J%'`;

  if (!gender) {
    if (req.user.role === 'admin_dash_f') gender = 'female';
    else if (req.user.role === 'admin_dashboard') gender = 'male';
    else {
      const FEMALE_COLLEGES = ['NewCampus','OldCampus','Agriculture'];
      if (FEMALE_COLLEGES.includes(req.user.college)) gender = 'female';
    }
  }

  if (start){ params.push(start); where += ` AND e.created_at::date >= $${params.length}`; }
  if (end){   params.push(end);   where += ` AND e.created_at::date <= $${params.length}`; }
  if (gender){ params.push(gender); where += ` AND s.gender = $${params.length}`; }

  const { rows } = await pool.query(`
    SELECT e.id AS exam_id, e.request_id,
           s.reg_number, s.name AS student_name, s.email,
           e.exam_code, e.score::float AS score,
           e.created_at::date AS created_at
      FROM exams e
      JOIN students s ON s.id = e.student_id
     WHERE ${where}
  ORDER BY e.created_at DESC`, params);

  res.json(rows);
});



/* تقارير أجزاء */
app.get('/api/exams/parts-report', auth, async (req,res)=>{
  try{
    const { college, start, end } = req.query;
    if(!college) return res.status(400).json({message:'college مطلوب'});

    const params=[college];
    let where = `
      s.college = $1
      AND e.exam_code LIKE 'J%'`;
    if(start){ params.push(start); where += ` AND e.created_at::date >= $${params.length}`; }
    if(end)  { params.push(end);   where += ` AND e.created_at::date <= $${params.length}`; }

    const { rows } = await pool.query(`
      SELECT
        e.id AS exam_id,
        s.reg_number,
        s.name AS student_name,
        s.email,
        e.exam_code,
        e.score::float AS score,
        e.passed,
        e.official,
        e.created_at::date AS created_at
      FROM exams e
      JOIN students s ON s.id = e.student_id
      WHERE ${where}
      ORDER BY e.created_at DESC`, params);

    res.json(rows);
  }catch(err){
    console.error('parts-report error',err);
    res.status(500).json({message:'خطأ في الخادم'});
  }
});

/* ======================== GET /api/exams/:studentId ======================= */
app.get('/api/exams/:studentId', auth, async (req, res) => {
  try {
    const sid = req.params.studentId === 'me'
                  ? req.user.id
                  : parseInt(req.params.studentId, 10);

    const isAdmin = ADMIN_ROLES.includes(req.user.role);
    if (!Number.isInteger(sid)) {
      return res.status(400).json({ message: 'studentId غير صالح' });
    }
    if (!isAdmin && sid !== req.user.id) {
      return res.status(403).json({ message: 'غير مخوَّل' });
    }

    const where = ['e.student_id = $1'];
    const params = [sid];

    if (req.query.official === '1') where.push('e.official = TRUE');
    if (req.query.official === '0') where.push('e.official = FALSE');
    if (req.query.passed === '1')   where.push('e.passed   = TRUE');
    if (req.query.passed === '0')   where.push('e.passed   = FALSE');

    const { rows } = await pool.query(
      `SELECT
         e.id, e.student_id, e.exam_code,
         CASE e.exam_code
           WHEN 'Q'  THEN 'القرآن كامل'
           WHEN 'H1' THEN 'خمسة عشر الأولى'
           WHEN 'H2' THEN 'خمسة عشر الثانية'
           WHEN 'F1' THEN 'خمسة أجزاء الأولى'
           WHEN 'F2' THEN 'خمسة أجزاء الثانية'
           WHEN 'F3' THEN 'خمسة أجزاء الثالثة'
           WHEN 'F4' THEN 'خمسة أجزاء الرابعة'
           WHEN 'F5' THEN 'خمسة أجزاء الخامسة'
           WHEN 'F6' THEN 'خمسة أجزاء السادسة'
           WHEN 'T1' THEN 'عشرة أجزاء الأولى'
           WHEN 'T2' THEN 'عشرة أجزاء الثانية'
           WHEN 'T3' THEN 'عشرة أجزاء الثالثة'
           ELSE e.exam_code
         END AS arabic_name,
         e.passed, e.official, e.score::float AS score,
         to_char(e.created_at::date,'YYYY-MM-DD') AS created_at,
         e.request_id
       FROM exams e
       WHERE ${where.join(' AND ')}
       ORDER BY e.created_at DESC`,
      params
    );

    res.json(rows);
  } catch (err) {
    console.error('❌ /api/exams/:studentId', err);
    res.status(500).json({ message: 'خطأ في الخادم' });
  }
});

/* ======================================================================== */


/* ════════════ PDF Certificate Endpoint ════════════ */
app.get('/api/certificates/:examId', auth, async (req, res, next) => {
  const examId = +req.params.examId;

  const { rows } = await pool.query(
    `
    SELECT e.score, e.created_at::date AS d,
           s.id AS stu_id, s.name, s.gender,   -- ← أضفنا gender
           e.exam_code,
           CASE e.exam_code
             WHEN 'Q'  THEN 'القرآن كامل'
             WHEN 'H1' THEN 'خمسة عشر الأولى'
             WHEN 'H2' THEN 'خمسة عشر الثانية'
             WHEN 'F1' THEN 'خمسة أجزاء الأولى'
             WHEN 'F2' THEN 'خمسة أجزاء الثانية'
             WHEN 'F3' THEN 'خمسة أجزاء الثالثة'
             WHEN 'F4' THEN 'خمسة أجزاء الرابعة'
             WHEN 'F5' THEN 'خمسة أجزاء الخامسة'
             WHEN 'F6' THEN 'خمسة أجزاء السادسة'
             WHEN 'T1' THEN 'عشرة أجزاء الأولى'
             WHEN 'T2' THEN 'عشرة أجزاء الثانية'
             WHEN 'T3' THEN 'عشرة أجزاء الثالثة'
           END AS arabic_name
      FROM exams e
      JOIN students s ON s.id = e.student_id
     WHERE e.id = $1
       AND e.official = TRUE
       AND e.passed   = TRUE
       AND e.exam_code NOT LIKE 'J%'`,
    [examId]
  );

  if (!rows.length) {
    return res.status(404).json({ message: 'لا يوجد شهادة' });
  }

  const exam = rows[0];
  const isAdmin = ['admin_dashboard','admin_dash_f','CollegeAdmin','EngAdmin','MedicalAdmin','shariaAdmin'].includes(req.user.role);
  const isOwner = req.user.id === exam.stu_id;
  if (!(isAdmin || isOwner)) {
    return res.status(403).json({ message: 'ممنوع' });
  }

  return sendCertificate(
    req,
    res,
    { student: { name: exam.name, gender: exam.gender }, exam, dateStr: exam.d },
    next
  );
});


// ADD: Admin create plan
app.post('/api/admin/plans', auth, async (req, res) => {
  const adminRoles = ['EngAdmin','MedicalAdmin','shariaAdmin','admin_dashboard','CollegeAdmin'];
  if (!adminRoles.includes(req.user.role)) {
    return res.status(403).json({ message: 'غير مخوَّل' });
  }

  const { value:v, error } = Joi.object({
    student_id        : Joi.number().integer().required(),
    /* حضور سابق */
    official_attended : Joi.boolean().default(false),
    official_exams    : Joi.array().items(Joi.string().valid('F1','F2','F3','F4','F5','F6','T1','T2','T3','H1','H2','Q')).default([]),
    parts_attended    : Joi.boolean().default(false),
    parts_range_start : Joi.number().integer().min(1).max(30).allow(null),
    parts_range_end   : Joi.number().integer().min(1).max(30).allow(null),

    continuation_mode : Joi.string().valid('from_start','from_end','specific').default('from_start'),
    specific_part     : Joi.number().integer().min(1).max(30).allow(null),
    current_part      : Joi.number().integer().min(1).max(30).allow(null),

    duration_type     : Joi.string().valid('week','day').required(),
    duration_value    : Joi.number().integer().min(1).required(),

    approved          : Joi.boolean().default(true)
  }).validate(req.body);
  if (error) return res.status(400).json({ message: error.message });

  try {
    /* تقييد الكلية للمشرفين الفرعيين */
    if (req.user.role !== 'admin_dashboard') {
      const { rows:stRows } = await pool.query(
        'SELECT college FROM students WHERE id=$1',[v.student_id]
      );
      if (!stRows.length) return res.status(404).json({ message: 'الطالب غير موجود' });
      if (stRows[0].college !== req.user.college) {
        return res.status(403).json({ message: 'طالب من كلية أخرى' });
      }
    }

    /* نوع الطالب */
    const { rows:[stu] } = await pool.query(
      'SELECT student_type FROM students WHERE id=$1',[v.student_id]
    );
    if (!stu) return res.status(404).json({ message: 'الطالب غير موجود' });
    const studentType = stu.student_type;

    /* حساب current_part المبدئي */
    const computedCurrent =
      v.current_part ??
      (v.continuation_mode === 'specific'
        ? v.specific_part
        : v.parts_attended
          ? v.parts_range_end
          : v.parts_range_start || 1);

    if (!computedCurrent) {
      return res.status(400).json({ message: 'تعذّر حساب current_part' });
    }

    /* تسجيل ما سمعه/الرسمى السابق (نفس منطق /api/plans) */
    if (v.parts_attended && v.parts_range_start != null && v.parts_range_end != null) {
      for (let p = v.parts_range_start; p <= v.parts_range_end; p++) {
        const code = 'J' + String(p).padStart(2,'0');
        await pool.query(`
          INSERT INTO exams (student_id, exam_code, passed, official, created_at)
          VALUES ($1,$2,TRUE,FALSE,now()::date)
          ON CONFLICT (student_id, exam_code, official) DO NOTHING
        `, [v.student_id, code]);
      }
    }
    if (v.official_attended && Array.isArray(v.official_exams)) {
      for (const code of v.official_exams) {
        await pool.query(`
          INSERT INTO exams (student_id, exam_code, passed, official, created_at)
          VALUES ($1,$2,TRUE,TRUE,now()::date)
          ON CONFLICT (student_id, exam_code, official) DO NOTHING
        `, [v.student_id, code]);
      }
    }

    /* إنشاء الخطة */
    const plan = await createPlan(
      v.student_id,
      v.official_attended,
      v.official_exams,
      v.parts_attended,
      v.parts_range_start,
      v.parts_range_end,
      v.continuation_mode,
      v.specific_part,
      computedCurrent,
      v.duration_type,
      v.duration_value,
      studentType
    );

    /* اعتماد فورى إن طُلب */
    if (v.approved) {
      await pool.query(`
        UPDATE plans
           SET approved = TRUE,
               approver_id = $2,
               approved_at = CURRENT_DATE
         WHERE id = $1
      `, [plan.id, req.user.id]);
      plan.approved = true;
    }

    return res.status(201).json(plan);
  } catch (e) {
    console.error('POST /api/admin/plans', e);
    return res.status(500).json({ message: 'خطأ في الخادم' });
  }
});

// ADD: Admin delete plan
app.delete('/api/admin/plans/:id', auth, async (req, res) => {
  const adminRoles = ['EngAdmin','MedicalAdmin','shariaAdmin','admin_dashboard','CollegeAdmin'];
  if (!adminRoles.includes(req.user.role)) {
    return res.status(403).json({ message: 'غير مخوَّل' });
  }

  const planId = +req.params.id;

  try {
    /* تأكيد الانتماء للكلية إن لم يكن مشرفًا عامًا */
    if (req.user.role !== 'admin_dashboard') {
      const { rows } = await pool.query(`
        SELECT s.college
          FROM plans p
          JOIN students s ON s.id = p.student_id
         WHERE p.id = $1
      `, [planId]);
      if (!rows.length) return res.status(404).json({ message: 'الخطة غير موجودة' });
      if (rows[0].college !== req.user.college) {
        return res.status(403).json({ message: 'الخطة تخص كلية أخرى' });
      }
    }

    const { rowCount } = await pool.query('DELETE FROM plans WHERE id=$1', [planId]);
    if (!rowCount) return res.status(404).json({ message: 'الخطة غير موجودة' });

    return res.json({ message: 'تم حذف الخطة' });
  } catch (e) {
    console.error('DELETE /api/admin/plans/:id', e);
    return res.status(500).json({ message: 'خطأ في الخادم' });
  }
});


// POST /api/plans – إنشاء خطة جديدة مع تسجيل “ما سمعه” الطالب في جدول exams
app.post('/api/plans', auth, async (req, res) => {
  try {
    /* ───────── 1) تفكيك الـ body والتحقّق من البيانات الأساسيّة ───────── */
    let {
      official_attended = false,
      official_exams    = [],
      parts_attended    = false,
      parts_range_start = null,
      parts_range_end   = null,
      continuation_mode = 'from_start',
      specific_part     = null,
      duration_type,
      duration_value,
      current_part      = null,
    } = req.body;

    if (!duration_type || duration_value == null) {
      return res
        .status(400)
        .json({ message: 'duration_type و duration_value مطلوبان' });
    }

    /* ───────── 2) حساب current_part المبدئي ───────── */
    const computedCurrent =
      current_part ??
      (continuation_mode === 'specific'
        ? specific_part
        : parts_attended
        ? parts_range_end
        : parts_range_start || 1);

    if (!computedCurrent) {
      return res
        .status(400)
        .json({ message: 'تعذّر حساب current_part' });
    }

    /* ───────── 3) نوع الطالب (regular / intensive) ───────── */
    const studentId = req.user.id;
    const {
      rows: [{ student_type: studentType }],
    } = await pool.query(
      'SELECT student_type FROM students WHERE id = $1',
      [studentId]
    );

    /* ───────── 4) تسجيل ما “سمعه” الطالب *قبل* إنشاء الخطة ───────── */
    if (
      parts_attended &&
      parts_range_start != null &&
      parts_range_end != null
    ) {
      for (let p = parts_range_start; p <= parts_range_end; p++) {
        const code = 'J' + String(p).padStart(2, '0');
        await pool.query(
          `
          INSERT INTO exams
            (student_id, exam_code, passed, official, created_at)
          VALUES ($1, $2, TRUE, FALSE, now()::date)
          ON CONFLICT (student_id, exam_code, official) DO NOTHING
        `,
          [studentId, code]
        );
      }
    }

    if (official_attended && Array.isArray(official_exams)) {
      for (const code of official_exams) {
        await pool.query(
          `
          INSERT INTO exams
            (student_id, exam_code, passed, official, created_at)
          VALUES ($1, $2, TRUE, TRUE, now()::date)
          ON CONFLICT (student_id, exam_code, official) DO NOTHING
        `,
          [studentId, code]
        );
      }
    }

    /* ───────── 5) إنشاء الخطة بعد أن أصبحت الامتحانات مسجّلة ───────── */
    const plan = await createPlan(
      studentId,
      official_attended,
      official_exams,
      parts_attended,
      parts_range_start,
      parts_range_end,
      continuation_mode,
      specific_part,
      computedCurrent,
      duration_type,
      duration_value,
      studentType
    );

    /* ───────── 6) إرجاع الخطة المنشأة ───────── */
    return res.status(201).json(plan);
  } catch (err) {
    console.error('Error in POST /api/plans:', err);
    return res.status(500).json({ message: 'خطأ في الخادم' });
  }
});



// Always returns at most one plan: the latest one the student submitted
// (approved = null || true || false). UI will only allow exam‑registration
// once { approved: true }.
// ── GET /api/plans/me ──
// GET /api/plans/me
app.get('/api/plans/me', auth, async (req, res) => {
  // ❶ try to load the last plan
  const { rows } = await pool.query(`
    SELECT
      p.id,
      p.approved,
      p.official_attended,
      p.official_exams,
      p.parts_attended,
      p.parts_range_start,
      p.parts_range_end,
      p.continuation_mode,
      p.specific_part,
      p.current_part,
      p.paused_for_official,
      p.duration_type,
      p.duration_value,
      s.student_type,
      to_char(p.start_date, 'YYYY-MM-DD') AS start,
      to_char(p.due_date,   'YYYY-MM-DD') AS due,
      (
        now()::date > p.due_date + 2
        AND NOT EXISTS (
          SELECT 1
            FROM exam_requests er
           WHERE er.student_id = p.student_id
             AND er.kind       = 'part'
             AND er.part       = p.current_part
        )
      ) AS is_overdue
    FROM plans p
    JOIN students s ON s.id = p.student_id
    WHERE p.student_id = $1
    ORDER BY p.created_at DESC
    LIMIT 1
  `, [req.user.id]);

  const plan = rows[0];
  if (plan) {
    return res.json(plan);
  }

  // ❷ NO PLAN YET → compute what J-parts the student *already* passed
  const { rows: passedParts } = await pool.query(`
    SELECT DISTINCT
           CAST(SUBSTRING(exam_code FROM 2)::int AS int) AS part
      FROM exams
     WHERE student_id = $1
       AND passed     = TRUE
       AND official   = FALSE
       AND exam_code LIKE 'J%'
    ORDER BY part
  `, [req.user.id]);

  const parts = passedParts.map(r => r.part);
  // find the longest contiguous run from 1…N
  let maxContiguous = 0;
  for (const p of parts) {
    if (p === maxContiguous + 1) {
      maxContiguous = p;
    } else {
      break;
    }
  }
  // next part to pick up
  const nextPart = Math.min(maxContiguous + 1, 30);

  // ❸ return a “virtual” plan that pre-loads the listened range
  return res.json({
    id                 : null,
    approved           : null,
    official_attended  : false,
    official_exams     : [],
    parts_attended     : parts.length > 0,
    parts_range_start  : parts.length > 0 ? 1 : null,
    parts_range_end    : parts.length > 0 ? maxContiguous : null,
    // if they’ve heard some, jump by default into “specific” mode at nextPart
    continuation_mode  : parts.length > 0 ? 'specific' : 'from_start',
    specific_part      : parts.length > 0 ? nextPart : null,
    current_part       : nextPart,
    paused_for_official: false,
    duration_type      : 'week',
    duration_value     : 1,
    student_type       : (await pool.query(
      `SELECT student_type FROM students WHERE id = $1`,
      [req.user.id]
    )).rows[0].student_type,
    start              : null,
    due                : null,
    is_overdue         : false
  });
});


// GET /api/plans/min
app.get('/api/plans/min', auth, async (req, res) => {
  const { rows } = await pool.query(`
    SELECT id, current_part, paused_for_official
      FROM plans
     WHERE student_id=$1 AND approved=TRUE
   ORDER BY created_at DESC LIMIT 1
  `, [req.user.id]);
  res.json(rows[0] || {});
});


app.patch('/api/plans/:id', auth, async (req, res) => {
  const planId = +req.params.id;
  const { approved } = req.body; // true أو false

  // 1) صلاحيات
  const adminRoles = ['EngAdmin','MedicalAdmin','shariaAdmin','admin_dashboard','CollegeAdmin'];
  if (!adminRoles.includes(req.user.role)) {
    return res.status(403).json({ message: 'غير مخوَّل' });
  }

  // 2) تأكد من وجود الخطة
  const { rows } = await pool.query(`
    SELECT p.*, s.college
      FROM plans p
      JOIN students s ON s.id = p.student_id
     WHERE p.id = $1
  `, [planId]);
  if (!rows.length) {
    return res.status(404).json({ message: 'الخطة غير موجودة' });
  }
  if (req.user.role === 'CollegeAdmin' && rows[0].college !== req.user.college) {
    return res.status(403).json({ message: 'الخطة تخص كلية أخرى' });
  }
  // 3) حدث حالة الموافقة
  await pool.query(
    `UPDATE plans
       SET approved     = $1,
           approver_id  = $2,
           approved_at  = CURRENT_DATE
     WHERE id = $3`,
    [approved, req.user.id, planId]
  );

  return res.json({ message: 'تم' });
});


// DELETE /api/plans/:id
app.delete('/api/plans/:id', auth, async (req, res) => {
  const planId    = +req.params.id;
  const studentId = req.user.id;
  // نحذف فقط لو الخطة تخص الطالب نفسه
  const { rowCount } = await pool.query(
    `DELETE FROM plans
      WHERE id = $1
        AND student_id = $2`,
    [planId, studentId]
  );
  if (!rowCount) {
    return res.status(404).json({ message: 'الخطة غير موجودة أو غير مخوَّل' });
  }
  res.json({ message: 'تم حذف الخطة بنجاح' });
});


// GET /api/college-plans  → جلب كل الخطط في كلية المسؤول
app.get('/api/college-plans', auth, async (req, res) => {
  if (!requireAdmin(req,res)) return;
  const plans = await getPlansByCollege(req.user.college);
  res.json(plans);
});

/* GET /api/exams/me/passed-parts
   يعيد مصفوفة أرقام الأجزاء (int[]) التى اجتازها الطالب رسمياً ونجح فيها */
app.get('/api/exams/me/passed-parts', auth, async (req, res) => {
  const { rows } = await pool.query(`
    SELECT DISTINCT
           CAST(SUBSTRING(exam_code FROM 2)::int AS int) AS part
      FROM exams
     WHERE student_id = $1
       AND official   = TRUE
       AND passed     = TRUE
       AND exam_code LIKE 'J%'
  `, [req.user.id]);
  res.json(rows.map(r => r.part));
});


/* ═════════════════════ 4) الحفاظ ═════════════════════ */

app.get('/api/hafadh', auth, async (req, res) => {
  const params = [];
  let where = 's.is_hafidh = TRUE';

  if (req.user.role === 'admin_dash_f') {
    params.push('female'); where += ` AND s.gender = $${params.length}`;
  } else if (req.user.role === 'admin_dashboard') {
    // يسمح بطلب gender صراحةً، وإلا افتراضي male
    const g = req.query.gender;
    params.push((g === 'male' || g === 'female') ? g : 'male');
    where += ` AND s.gender = $${params.length}`;
  } else if (req.user.college) {
    const FEMALE_COLLEGES = ['NewCampus','OldCampus','Agriculture'];
    params.push(FEMALE_COLLEGES.includes(req.user.college) ? 'female' : 'male');
    where += ` AND s.gender = $${params.length}`;
  }

  const { rows } = await pool.query(`
    SELECT s.id, s.reg_number, s.name, s.college, s.gender,
           COALESCE(h.hafidh_date, s.hafidh_date)::date AS hafidh_date
      FROM students s
 LEFT JOIN hafadh   h ON h.student_id = s.id
     WHERE ${where}
  ORDER BY COALESCE(h.hafidh_date, s.hafidh_date) DESC`, params);

  res.json(rows);
});




app.post('/api/hafadh', auth, async (req,res)=>{
  if(!['admin_dashboard','admin_dash_f'].includes(req.user.role))
    return res.status(403).json({message:'غير مخوَّل'});

  const { value:v, error } = Joi.object({
    student_id : Joi.number().integer().required(),
    hafidh_date: Joi.date().optional()
  }).validate(req.body);
  if(error) return res.status(400).json({message:error.message});

  const d = toDateStr(v.hafidh_date) || todayStr();

  await pool.query(`
     UPDATE students
        SET is_hafidh   = TRUE,
            hafidh_date = $2::date
      WHERE id = $1`, [v.student_id, d]);

  await pool.query(`
    INSERT INTO hafadh (student_id, hafidh_date)
    VALUES ($1,$2::date)
    ON CONFLICT (student_id) DO UPDATE
      SET hafidh_date = EXCLUDED.hafidh_date`,
    [v.student_id, d]);

  const { rows: stuRows } = await pool.query(
    'SELECT student_type FROM students WHERE id=$1',[v.student_id]);
  if(stuRows.length){
    const required = (stuRows[0].student_type === 'regular')
      ? ['F1','F2','F3','F4','F5','F6']
      : ['T1','T2','T3','H1','H2','Q'];

    for(const code of required){
      await pool.query(`
        INSERT INTO exams
          (student_id, exam_code, passed, official, created_at)
        VALUES ($1,$2,TRUE,TRUE,$3::date)
        ON CONFLICT (student_id, exam_code, official) DO NOTHING`,
        [v.student_id, code, d]
      );
    }
  }

  res.status(201).json({message:'تمت إضافة الحافظ/الحافظة'});
});


app.patch('/api/students/:id/hafidh', auth, async (req,res)=>{
  if(req.user.role!=='admin_dashboard')
    return res.status(403).json({message:'غير مخوَّل'});
  const d = toDateStr(req.body.date) || todayStr();
  await pool.query(`
     UPDATE students
        SET is_hafidh = TRUE,
            hafidh_date = $1::date
      WHERE id=$2`, [d, +req.params.id]);
  res.json({message:'ok'});
});


/* ═════════════════════ 5) exam‑requests ═════════════════════ */

// POST /api/exam-requests – إضافة فحص منع إعادة ما اجتازه الطالب مسبقًا
app.post('/api/exam-requests', auth, async (req, res) => {
  try {
    const uid   = req.user.id;
    const today = todayStr();                       // YYYY-MM-DD

    /* ❶ التحقق من المدخلات */
    const { value: e, error } = Joi.object({
      kind   : Joi.string().valid('part','official').required(),

      /* حقول “جزء” */
      part   : Joi.number().integer().min(1).max(30)
                     .when('kind',{ is:'part', then: Joi.required() }),
      date   : Joi.date()
                     .when('kind',{ is:'part', then: Joi.required() }),
      run_mode: Joi.string().valid('normal','redo').default('normal')
                     .when('kind',{ is:'part', otherwise: Joi.forbidden() }),

      /* حقول “رسمي” */
      exam_code    : Joi.string().valid(...VALID_CODES)
                         .when('kind',{ is:'official', then: Joi.required() }),
      trial_date   : Joi.date()
                         .when('kind',{ is:'official', then: Joi.required() }),
      official_date: Joi.date().min(Joi.ref('trial_date')).allow(null)
    }).validate(req.body);
    if (error) return res.status(400).json({ message: error.message });
        // يجب أن يكون الرسمي بعد التجريبي بيوم على الأقل إن تم تمريره
    if (e.kind === 'official' && e.official_date) {
      const tr = new Date(e.trial_date);
      const of = new Date(e.official_date);
      if (!(of > tr)) {
        return res.status(400).json({ message: 'تاريخ الرسمي يجب أن يكون بعد التجريبي بيوم على الأقل' });
      }
    }

    const isPartReq = e.kind === 'part';
    const runMode   = e.run_mode;

    /* ❷ جلب أحدث خطة معتمدة */
    const { rows:[plan] } = await pool.query(`
      SELECT p.*,
             s.student_type
        FROM plans p
        JOIN students s ON s.id = p.student_id
       WHERE p.student_id = $1
    ORDER BY p.created_at DESC
       LIMIT 1`, [uid]);

    if (!plan || plan.approved !== true)
      return res.status(403).json({ message: 'يجب اعتماد خطة أولاً' });

    if (today < plan.start_date || today > plan.due_date)
      return res.status(403).json({ message: 'الخطة خارج الفترة المحددة' });

    /* ❸ منع تكرار ما اجتازه */
    if (isPartReq && runMode === 'normal' &&
        plan.parts_attended &&
        e.part >= plan.parts_range_start &&
        e.part <= plan.parts_range_end) {

      return res.status(409).json({ message: 'لقد سمعت هذا الجزء مسبقاً – اختر وضع إعادة' });
    }

    if (!isPartReq) {
      const { rowCount } = await pool.query(`
        SELECT 1 FROM exams
         WHERE student_id = $1
           AND exam_code  = $2
           AND passed     = TRUE
           AND official   = TRUE
         LIMIT 1`,
        [uid, e.exam_code]);
      if (rowCount)
        return res.status(409).json({ message: 'لقد أجتزت هذا الامتحان رسمياً مسبقاً' });
    }

    /* ───────── منطق طلب الأجزاء ───────── */
    if (isPartReq) {
      if (plan.paused_for_official && runMode === 'normal')
        return res.status(403).json({ message: 'الخطة موقوفة لامتحان رسمي، يمكنك إعادة الأجزاء فقط' });

      /* تحقق من إغلاق التسجيل */
      const regPart = await getPartRegistration(req.user.college);
      if (regPart.disabled_from &&
          today >= regPart.disabled_from &&
          (!regPart.disabled_until || today <= regPart.disabled_until)) {
        return res.status(403).json({ message: 'تسجيل الأجزاء مغلق حالياً' });
      }

      /* إذا run_mode = redo ألغِ أي طلب سابق نشط لنفس الجزء */
      if (runMode === 'redo') {
        await pool.query(`
          UPDATE exam_requests
             SET approved = FALSE
           WHERE student_id = $1
             AND kind       = 'part'
             AND part       = $2
             AND approved   = TRUE`,
        [uid, e.part]);
      }

      /* منع وجود طلب نشط لنفس الجزء */
      const { rowCount: dup } = await pool.query(`
        SELECT 1
          FROM exam_requests er
     LEFT JOIN exams ex ON ex.request_id = er.id
         WHERE er.student_id = $1
           AND er.kind       = 'part'
           AND er.part       = $2
           AND (er.approved IS NULL OR er.approved = TRUE)
           AND ex.id IS NULL`,
        [uid, e.part]);
      if (dup)
        return res.status(409).json({ message: 'طلب سابق لهذا الجزء ما زال نشطاً' });
    }

    /* ───────── منطق طلب رسمي ───────── */
    else {
      const scope = req.user?.gender === 'female' ? 'female' : 'both';
      const regBoth   = await getOfficialRegistration('both');
      const regFemale = scope === 'female' ? await getOfficialRegistration('female') : null;

      const isClosed = (row) =>
        row?.disabled_from &&
        today >= toDateStr(row.disabled_from) &&
        (!row.disabled_until || today <= toDateStr(row.disabled_until));

      if (isClosed(regBoth) || isClosed(regFemale)) {
        return res.status(403).json({ message: 'التسجيل الرسمي مغلق حالياً' });
      }

      if (!plan.paused_for_official)
        return res.status(403).json({ message: 'الخطة ليست موقوفة لامتحان رسمي' });

      /* الأكواد المسموح بها حسب نوع الطالب */
      const allowedInt = ['T1','T2','T3','H1','H2','Q'];
      const allowedReg = ['F1','F2','F3','F4','F5','F6'];
      const { rows:[stu] } = await pool.query(
        'SELECT student_type FROM students WHERE id = $1',
        [uid]
      );
      const studentType = stu.student_type;
      const allowed     = studentType === 'regular' ? allowedReg : allowedInt;

      if (!allowed.includes(e.exam_code))
        return res.status(403).json({ message: 'رمز الامتحان الرسمي غير صالح' });

      /* تأكّد أن الكود مطلوب فعلاً الآن */
      if (!plan.official_exams.includes(e.exam_code)) {
        return res.status(403).json({
          message: 'هذا الامتحان غير مطلوب الآن للخطة الحالية'
        });
      }

      /* تحقق من إغلاق التسجيل الرسمي */
      const regOff = await getOfficialRegistration();
      if (regOff.disabled_from &&
          today >= regOff.disabled_from &&
          (!regOff.disabled_until || today <= regOff.disabled_until)) {
        return res.status(403).json({ message: 'التسجيل الرسمي مغلق حالياً' });
      }

      /* منع طلب نشط لنفس الامتحان */
      const { rowCount: dup } = await pool.query(`
        SELECT 1
          FROM exam_requests er
     LEFT JOIN exams ex ON ex.request_id = er.id AND ex.official = TRUE
         WHERE er.student_id = $1
           AND er.kind       = 'official'
           AND er.exam_code  = $2
           AND (er.approved IS NULL OR er.approved = TRUE)
           AND ex.id IS NULL`,
        [uid, e.exam_code]);
      if (dup)
        return res.status(409).json({ message: 'طلب رسمي سابق لنفس الامتحان ما زال نشطاً' });
    }

    /* ❹ إدراج الطلب */
    await pool.query(`
      INSERT INTO exam_requests (
        student_id, kind, part, "date",
        exam_code, trial_date, official_date,
        college, run_mode
      ) VALUES (
        $1,$2,$3,$4::date,
        $5,$6::date,$7::date,
        $8,$9
      )`,
    [
      uid,
      e.kind,
      isPartReq ? e.part         : null,
      isPartReq ? toDateStr(e.date) : null,
      isPartReq ? null           : e.exam_code,
      isPartReq ? null           : toDateStr(e.trial_date),
      isPartReq ? null           : toDateStr(e.official_date),
      req.user.college,
      isPartReq ? runMode        : null
    ]);

    return res.status(201).json({ message: 'تم تقديم طلب الامتحان بنجاح' });

  } catch (err) {
    console.error('POST /api/exam-requests Error:', err);
    return res.status(500).json({ message: 'خطأ في الخادم' });
  }
});










app.get('/api/my-exam-requests', auth, async (req,res)=>{
  const { rows } = await pool.query(`
    SELECT er.id,
           er.kind,
           CASE
             WHEN kind='part'                     THEN 'جزء '||part
             WHEN exam_code::text LIKE 'F%'       THEN 'خمسة أجزاء '||substr(exam_code::text,2,1)
             WHEN exam_code::text LIKE 'T%'       THEN 'عشرة أجزاء '||substr(exam_code::text,2,1)
             WHEN exam_code::text = 'H1'          THEN 'خمسة عشر الأولى'
             WHEN exam_code::text = 'H2'          THEN 'خمسة عشر الثانية'
             WHEN exam_code::text = 'Q'           THEN 'القرآن كامل'
           END AS display,
           to_char(COALESCE(date, trial_date, official_date),'YYYY-MM-DD') AS exam_date,
           er.approved,
           sp.name       AS supervisor_name,
           st_trial.name AS trial_supervisor,
           st_doc.name   AS doctor_supervisor
      FROM exam_requests er
      JOIN students     st        ON st.id  = er.student_id
 LEFT JOIN supervisors sp        ON sp.id  = st.supervisor_id
 LEFT JOIN supervisors st_trial  ON st_trial.id = er.supervisor_trial_id
 LEFT JOIN supervisors st_doc    ON st_doc.id   = er.supervisor_official_id
     WHERE er.student_id = $1
  ORDER BY er.id DESC`, [req.user.id]);
  res.json(rows);
});


app.get('/api/exam-requests', auth, async (req,res)=>{
  if (!requireAdmin(req,res)) return;
  const role = req.user.role;
  const params = [];
  let where = 'er.approved IS NULL';

  const isGirlsGlobal = (role === 'admin_dash_f');

  if (role === 'admin_dashboard' || isGirlsGlobal) {
    // المسؤول العام/مسؤولة البنات: يشوفون الرسمي فقط
    where += ` AND er.kind='official'`;
  } else {
    // مسؤولو الكليات: الأجزاء فقط من كليته
    const college = req.user.college ||
      (role==='EngAdmin'?'Engineering':
       role==='MedicalAdmin'?'Medical':'Sharia');
    params.push(college);
    where += ` AND er.college=$${params.length} AND er.kind='part'`;
  }

  // فلتر الجنس
  const qg = req.query.gender;
  if (qg === 'male' || qg === 'female') {
    params.push(qg);
    where += ` AND st.gender = $${params.length}`;
  } else if (isGirlsGlobal) {
    // admin_dash_f → افتراضيًا إناث
    params.push('female');
    where += ` AND st.gender = $${params.length}`;
  } else if (role === 'admin_dashboard') {
    // المسؤول العام (ذكور) → افتراضيًا ذكور
    params.push('male');
    where += ` AND st.gender = $${params.length}`;
  } else {
    // مسؤولة مجمّع بنات (لو كانت كليتها نسائية) → إجبار إناث
    const FEMALE_COLLEGES = ['NewCampus','OldCampus','Agriculture'];
    if (FEMALE_COLLEGES.includes(req.user.college)) {
      params.push('female');
      where += ` AND st.gender = $${params.length}`;
    }
  }

  const { rows } = await pool.query(`
    SELECT
      er.id, er.kind, er.part,
      to_char(er."date",'YYYY-MM-DD')        AS date,
      er.exam_code,
      to_char(er.trial_date,'YYYY-MM-DD')    AS trial_date,
      to_char(er.official_date,'YYYY-MM-DD') AS official_date,
      er.approved, er.college,
      st.name AS student_name,
      sp.name AS orig_supervisor,
      ex.name AS examiner_name,
      er.supervisor_trial_id,
      er.supervisor_official_id
    FROM exam_requests er
    JOIN students st ON st.id = er.student_id
    LEFT JOIN supervisors sp ON sp.id = st.supervisor_id
    LEFT JOIN supervisors ex ON ex.id = er.supervisor_trial_id
    WHERE ${where}
    ORDER BY er.id DESC
  `, params);

  res.json(rows);
});







app.patch('/api/exam-requests/:id', auth, async (req,res)=>{
  const { value:v, error } = Joi.object({
    approved               : Joi.boolean().required(),
    supervisor_trial_id    : Joi.number().integer().allow(null),
    supervisor_official_id : Joi.number().integer().allow(null),
    official_date          : Joi.date().allow(null)
  }).validate(req.body);
  if(error) return res.status(400).json({message:error.message});

  const id = +req.params.id;
  const { rows: cur } = await pool.query(
    'SELECT kind, trial_date FROM exam_requests WHERE id=$1',[id]);
  if(!cur.length) return res.status(404).json({message:'الطلب غير موجود'});

  const kind = cur[0].kind;
  const tr   = cur[0].trial_date;

  if(v.approved===true && kind==='official'){
    if(!v.supervisor_trial_id || !v.supervisor_official_id)
      return res.status(400).json({message:'اختر مشرف التجريبي ومشرف الرسمي قبل القبول'});
  }

  if (kind === 'official' && tr && v.official_date) {
    if (!(new Date(v.official_date) > new Date(tr))) {
      return res.status(400).json({ message: 'تاريخ الرسمي يجب أن يكون بعد التجريبي بيوم على الأقل' });
    }
  }
  


  await pool.query(`
    UPDATE exam_requests SET
      approved               = $1,
      approver_id            = $2,
      supervisor_trial_id    = $3,
      supervisor_official_id = $4,
      official_date          = COALESCE($5::date, official_date)
    WHERE id=$6`,
    [
      v.approved,
      req.user.id,
      v.supervisor_trial_id,
      v.supervisor_official_id,
      v.official_date,
      id
    ]
  );

  res.json({message:'done'});
});


app.delete('/api/exam-requests/:id', auth, async (req, res) => {
  const id   = +req.params.id;
  const role = req.user.role;
  const col  = req.user.college;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1) التحقق من وجود الطلب والصلاحيات
    const { rows } = await client.query(
      'SELECT college FROM exam_requests WHERE id = $1',
      [id]
    );
    if (!rows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'غير موجود' });
    }
    if (role !== 'admin_dashboard' && rows[0].college !== col) {
      await client.query('ROLLBACK');
      return res.status(403).json({ message: 'غير مخوَّل' });
    }

    // 2) احذف أولاً كل الدرجات المرتبطة بهذا الطلب
    await client.query(
      'DELETE FROM exams WHERE request_id = $1',
      [id]
    );

    // 3) بعدين احذف الطلب نفسه
    await client.query(
      'DELETE FROM exam_requests WHERE id = $1',
      [id]
    );

    await client.query('COMMIT');
    return res.json({ message: 'تم الحذف' });

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return res.status(500).json({ message: 'خطأ أثناء الحذف' });
  } finally {
    client.release();
  }
});




// GET /api/pending-scores
// GET /api/pending-scores
app.get('/api/pending-scores', auth, async (req, res) => {
  const { role, college } = req.user;

  // أداة صغيرة لضبط الجنس المطلوب
  const normalizeGender = g => (g === 'male' || g === 'female') ? g : null;

  /* ───────────────── مسؤولو العموم (ذكور/إناث): الرسمي فقط (trial → official) ───────────────── */
  if (role === 'admin_dashboard' || role === 'admin_dash_f') {
    const params = [];
    // إن لم يُرسل بالـ query، نفرضه حسب الدور
    const forcedGender =
      normalizeGender(req.query.gender) ||
      (role === 'admin_dash_f' ? 'female' : 'male');

    let gWhere = '';
    if (forcedGender) {
      params.push(forcedGender);
      gWhere = ` AND st.gender = $${params.length}`;
    }

    const { rows } = await pool.query(`
      SELECT
        t.req_id,
        t.kind,
        t.stage,
        t.exam_code,
        t.exam_date,
        t.student_name,
        t.college
      FROM (
        /* المرحلة التجريبية */
        SELECT
          er.id                                AS req_id,
          er.kind                              AS kind,
          'trial'                              AS stage,
          er.exam_code                         AS exam_code,
          TO_CHAR(er.trial_date,'YYYY-MM-DD')  AS exam_date,
          st.name                              AS student_name,
          er.college                           AS college,
          1                                    AS stage_order
        FROM exam_requests er
        JOIN students st ON st.id = er.student_id
       WHERE er.kind     = 'official'
         AND er.approved = TRUE
         AND NOT EXISTS (
               SELECT 1 FROM exams e
                WHERE e.request_id = er.id
                  AND e.official   = FALSE
             )
         ${gWhere}

        UNION ALL

        /* المرحلة الرسمية بعد نجاح التجريبي */
        SELECT
          er.id                                                  AS req_id,
          er.kind                                                AS kind,
          'official'                                             AS stage,
          er.exam_code                                           AS exam_code,
          TO_CHAR(COALESCE(er.official_date, er.trial_date),'YYYY-MM-DD') AS exam_date,
          st.name                                                AS student_name,
          er.college                                             AS college,
          2                                                      AS stage_order
        FROM exam_requests er
        JOIN students st ON st.id = er.student_id
       WHERE er.kind     = 'official'
         AND er.approved = TRUE
         AND EXISTS (
               SELECT 1 FROM exams e
                WHERE e.request_id = er.id
                  AND e.official   = FALSE
                  AND e.passed     = TRUE
             )
         AND NOT EXISTS (
               SELECT 1 FROM exams e
                WHERE e.request_id = er.id
                  AND e.official   = TRUE
             )
         ${gWhere}
      ) AS t
      ORDER BY t.exam_date NULLS LAST, t.stage_order, t.req_id
    `, params);

    return res.json(rows);
  }

  /* ───────────────── بقية الأدوار (مسؤولو كليات): الأجزاء فقط لنفس الكلية ───────────────── */
  {
    // نبني params جديدة لهذا الفرع فقط
    const params = [college];

    // إذا كانت كلية بنات أو تم تمرير gender نضيف فلتر بعد الـ JOIN
    const femaleColleges = ['NewCampus','OldCampus','Agriculture'];
    const forcedGender =
      normalizeGender(req.query.gender) ||
      (femaleColleges.includes(college) ? 'female' : null);

    let afterJoinWhere = '';
    if (forcedGender) {
      params.push(forcedGender);              // سيكون $2
      afterJoinWhere = ` WHERE st.gender = $2`;
    }

    const { rows } = await pool.query(`
      WITH latest AS (
        SELECT DISTINCT ON (er.student_id, er.part)
               er.*
          FROM exam_requests er
         WHERE er.kind     = 'part'
           AND er.approved = TRUE
           AND er.college  = $1
           AND NOT EXISTS (
                 SELECT 1 FROM exams e
                  WHERE e.request_id = er.id
               )
         ORDER BY er.student_id, er.part, er.id DESC
      )
      SELECT
        latest.id                            AS req_id,
        latest.kind                          AS kind,
        'part'                               AS stage,
        'J' || LPAD(latest.part::text,2,'0') AS exam_code,
        TO_CHAR(latest.date, 'YYYY-MM-DD')   AS exam_date,
        st.name                              AS student_name,
        latest.college                       AS college
      FROM latest
      JOIN students st ON st.id = latest.student_id
      ${afterJoinWhere}
      ORDER BY exam_date NULLS LAST, latest.id
    `, params);

    return res.json(rows);
  }
});












/* ═════════════════════ 6) تسجيل + المستخدمون ═════════════════════ */

app.post('/api/register', async (req,res)=>{
  try{
    const { role='student', name, reg_number, email, phone, college, password, student_type, gender } = req.body || {};
    if(!['student','supervisor'].includes(role)) return res.status(400).json({message:'role غير صالح'});
    if(!name || !reg_number || !college || !password) return res.status(400).json({message:'حقول ناقصة'});
    if(!VALID_COLLEGES.includes(college)) return res.status(400).json({message:'كلية غير صالحة'});

    const g = (gender === 'female' || gender === 'male') ? gender : collegeToGender(college);
    // منع تكرار reg/email عبر كل النظام
    const dupStu = await pool.query(`SELECT 1 FROM students WHERE reg_number=$1 OR email=$2`, [reg_number, email||null]);
    const dupSup = await pool.query(`SELECT 1 FROM supervisors WHERE reg_number=$1 OR email=$2`, [reg_number, email||null]);
    const dupReq = await pool.query(`SELECT 1 FROM registration_requests WHERE (reg_number=$1 OR (email IS NOT NULL AND email=$2)) AND status='pending'`, [reg_number, email||null]);
    if(dupStu.rowCount || dupSup.rowCount || dupReq.rowCount) return res.status(409).json({message:'رقم/بريد مستخدم مسبقًا'});

    await pool.query(`
      INSERT INTO registration_requests
        (role, name, reg_number, email, phone, college, password, student_type, gender, status, created_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'pending', now())
    `, [role, name, reg_number, email||null, phone||null, college, password, role==='student'? (student_type||'regular') : null, g]);

    res.status(201).json({message:'تم استلام الطلب'});
  }catch(e){
    console.error('register error', e);
    res.status(500).json({message:'خطأ في الخادم'});
  }
});




app.get('/api/requests/count', auth, async (req,res)=>{
  if(!isAdminAny(req.user)) return res.status(403).json({message:'غير مخوَّل'});
  const params = [];
  const where  = [`status='pending'`];

  if(isGirlsRole(req.user)){ params.push('female'); where.push(`gender=$${params.length}`); }
  else if(isBoysRole(req.user)){ params.push('male'); where.push(`gender=$${params.length}`); }

  if(req.user.role==='CollegeAdmin' && req.user.college){
    params.push(req.user.college); where.push(`college=$${params.length}`);
  }

  const { rows:[r] } = await pool.query(`SELECT COUNT(*)::int AS pending FROM registration_requests WHERE ${where.join(' AND ')}`, params);
  res.json({ pending: r?.pending || 0 });
});





app.get('/api/requests', auth, async (req,res)=>{
  try{
    if(!isAdminAny(req.user)) return res.status(403).json({message:'غير مخوَّل'});

    const params = [];
    const where  = [`status='pending'`];

    // فصل حسب الدور (ذكور/إناث)
    if(isGirlsRole(req.user)){
      params.push('female'); where.push(`gender = $${params.length}`);
    } else if(isBoysRole(req.user)){
      params.push('male');   where.push(`gender = $${params.length}`);
    }

    // حصر الكلية لمسؤول كلية
    if(req.user.role === 'CollegeAdmin' && req.user.college){
      params.push(req.user.college);
      where.push(`college = $${params.length}`);
    }

    const { rows } = await pool.query(`
      SELECT id, role, name, reg_number, email, phone, college, gender, student_type,
             to_char(created_at,'YYYY-MM-DD HH24:MI') AS created_at_str
        FROM registration_requests
       WHERE ${where.join(' AND ')}
       ORDER BY created_at ASC
    `, params);

    res.json(rows);
  }catch(e){
    console.error('GET /requests', e);
    res.status(500).json({message:'خطأ في الخادم'});
  }
});




/* اعتماد الطلب (وتعيين المشرف/المشرفة عند الاعتماد) */
app.post('/api/requests/:id/approve', auth, async (req,res)=>{
  const id = +req.params.id;
  if(!isAdminAny(req.user)) return res.status(403).json({message:'غير مخوَّل'});

  const client = await pool.connect();
  try{
    await client.query('BEGIN');

    const { rows } = await client.query(`SELECT * FROM registration_requests WHERE id=$1 FOR UPDATE`, [id]);
    if(!rows.length) { await client.query('ROLLBACK'); return res.status(404).json({message:'الطلب غير موجود'}); }
    const r = rows[0];
    if(r.status !== 'pending') { await client.query('ROLLBACK'); return res.status(409).json({message:'تمت معالجة الطلب مسبقًا'}); }

    // فصل صارم حسب جهة المسؤول
    if(isGirlsRole(req.user) && r.gender !== 'female') { await client.query('ROLLBACK'); return res.status(403).json({message:'طلب لا يخص جهة الإناث'}); }
    if(isBoysRole(req.user)  && r.gender !== 'male')   { await client.query('ROLLBACK'); return res.status(403).json({message:'طلب لا يخص جهة الذكور'}); }
    if(req.user.role==='CollegeAdmin' && req.user.college !== r.college){
      await client.query('ROLLBACK'); return res.status(403).json({message:'طلب يخص كلية أخرى'});
    }

    if(r.role === 'student'){
      const supId = req.body?.supervisor_id;
      if(!supId){ await client.query('ROLLBACK'); return res.status(400).json({message:'supervisor_id مطلوب'}); }

      // تحقق: مشرف/مشرفة من نفس الكلية وبنفس الجنس المطلوب
      const { rows: srows } = await client.query(`SELECT id, gender, college FROM supervisors WHERE id=$1`, [supId]);
      if(!srows.length || srows[0].college !== r.college || srows[0].gender !== r.gender){
        await client.query('ROLLBACK'); return res.status(400).json({message:'مشرف/مشرفة غير صالح(ة) للكلية/الجهة'});
      }

      // إدراج الطالب
      const raw = r.password && r.password.length >= 4 ? r.password : '123456';
      const hash = await bcrypt.hash(raw, 10);
      await client.query(`
        INSERT INTO students (reg_number, name, password, phone, email, college, supervisor_id, student_type, gender, is_hafidh)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,FALSE)
      `, [r.reg_number, r.name, hash, r.phone, r.email, r.college, supId, r.student_type || 'regular', r.gender]);

    } else { // supervisor
      // إدراج مشرف/مشرفة — الجنس يُؤخذ من الطلب
      const reg = crypto.randomUUID();
      await client.query(`
        INSERT INTO supervisors (reg_number, name, phone, email, college, is_regular, is_trial, is_doctor, is_examiner, gender)
        VALUES ($1,$2,$3,$4,$5, TRUE, FALSE, FALSE, FALSE, $6)
      `, [reg, r.name, r.phone, r.email, r.college, r.gender]);
    }

    await client.query(`UPDATE registration_requests SET status='approved', processed_at=now(), processed_by=$2 WHERE id=$1`, [id, req.user.id]);
    await client.query('COMMIT');
    res.json({message:'تم الاعتماد'});
  }catch(e){
    await client.query('ROLLBACK');
    console.error('approve error', e);
    res.status(500).json({message:'خطأ في الخادم'});
  }finally{
    client.release();
  }
});




app.post('/api/requests/:id/reject', auth, async (req,res)=>{
  const id = +req.params.id;
  if(!isAdminAny(req.user)) return res.status(403).json({message:'غير مخوَّل'});
  const { rowCount } = await pool.query(`UPDATE registration_requests SET status='rejected', processed_at=now(), processed_by=$2 WHERE id=$1 AND status='pending'`, [id, req.user.id]);
  if(!rowCount) return res.status(404).json({message:'غير موجود أو غير معلق'});
  res.json({message:'تم الرفض'});
});




app.post('/api/requests/:id/approve-with-supervisor', auth, async (req, res) => {
  const allowedRoles = ['admin_dashboard','CollegeAdmin','EngAdmin','MedicalAdmin','shariaAdmin','admin_dash_f'];
  if (!allowedRoles.includes(req.user.role))
    return res.status(403).json({ message: 'غير مخوَّل' });

  const { supervisor_id } = req.body;
  if (!supervisor_id) return res.status(400).json({ message: 'supervisor_id مطلوب' });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // ✅ الطلب pending
    const { rows: rqRows } = await client.query(`
      SELECT * FROM registration_requests
       WHERE id = $1 AND status = 'pending'
      FOR UPDATE`, [+req.params.id]);
    if (!rqRows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'الطلب غير موجود أو مُعالَج' });
    }
    const rq = rqRows[0];

    // صلاحيات الرؤية حسب الدور (تماماً مثل /approve)
    if (req.user.role === 'admin_dashboard' && !MALE_COLLEGES.includes(rq.college)) {
      await client.query('ROLLBACK');
      return res.status(403).json({ message: 'طلبات هذه الكلية لا تظهر للمسؤول العام' });
    }
    if (req.user.role === 'admin_dash_f' && !FEMALE_COLLEGES.includes(rq.college)) {
      await client.query('ROLLBACK');
      return res.status(403).json({ message: 'طلب من كلية الذكور' });
    }
    if (req.user.role === 'CollegeAdmin' && req.user.college !== rq.college) {
      await client.query('ROLLBACK');
      return res.status(403).json({ message: 'كلية مختلفة' });
    }

    if ((rq.role || 'student') !== 'student') {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'هذا الطلب ليس لطالبة/طالب' });
    }

    // المشرفة المختارة
    const { rows: supRows } = await client.query(
      `SELECT id, college, gender FROM supervisors WHERE id = $1`, [supervisor_id]
    );
    if (!supRows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'مشرفة غير موجودة' });
    }
    const sup = supRows[0];

    // إلزام أنثى + نفس الكلية
    if (sup.gender !== 'female') {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'لا يمكن تعيين مشرف ذكر لطالبة' });
    }
    if (sup.college !== rq.college) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'المشرفة من كلية مختلفة' });
    }

    // منع التكرار
    const emailNorm = rq.email?.trim() || null;
    const dup = await client.query(
      `SELECT 1 FROM students WHERE reg_number = $1 OR (email IS NOT NULL AND email = $2)`,
      [rq.reg_number, emailNorm]
    );
    if (dup.rowCount) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'رقم أو بريد مكرر' });
    }

    // كلمة السر
    const rawPass = rq.password && rq.password.length >= 4 ? rq.password : '123456';
    const hash = await bcrypt.hash(rawPass, 10);

    // تحديد الجنس تلقائياً إن لم يُرسل
    const femaleColleges = new Set(FEMALE_COLLEGES);
    const gender = (rq.gender && GENDERS.includes(rq.gender))
      ? rq.gender
      : (femaleColleges.has(rq.college) ? 'female' : 'male');

    // إدراج الطالبة/الطالب وتعيين المشرفة
    await client.query(`
      INSERT INTO students
        (reg_number, name, password, phone, email, college, supervisor_id, student_type, gender)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [rq.reg_number, rq.name, hash, rq.phone || null, emailNorm, rq.college, supervisor_id, rq.student_type || 'regular', gender]
    );

    // تحديث حالة الطلب
    await client.query(
      `UPDATE registration_requests
          SET status='approved',
              processed_at = now(),
              processed_by = $2
        WHERE id = $1`,
      [rq.id, req.user.id]
    );


    await client.query('COMMIT');
    res.json({ message: 'تم القبول وتعيين المشرفة' });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('approve-with-supervisor', e);
    res.status(500).json({ message: 'خطأ في الخادم' });
  } finally {
    client.release();
  }
});



/* ═════════════════════ 7) تسجيل الدخول و Reset ═════════════════════ */

app.post('/api/login', async (req, res) => {
  const { reg_number, password } = req.body;
  if (!reg_number || !password)
    return res.status(400).json({ message: 'رقم التسجيل وكلمة السر مطلوبة' });

  const { rows } = await pool.query(
    'SELECT * FROM users WHERE reg_number = $1',
    [reg_number]
  );
  if (!rows.length) return res.status(400).json({ message: 'بيانات خاطئة' });

  const user = rows[0];
  const ok = await bcrypt.compare(password, user.password);
  if (!ok) return res.status(400).json({ message: 'بيانات خاطئة' });

  // fallback للكلية عند بعض أدوار المشرفين العامّين
  const fallback = {
    EngAdmin: 'Engineering',
    MedicalAdmin: 'Medical',
    shariaAdmin: 'Sharia',
  };

  // تحويل أدوار البنات القديمة إلى الدور الموحّد CollegeAdmin
  const FEMALE_LEGACY = {
    NewCampusAdminF: 'NewCampus',
    OldCampusAdminF: 'OldCampus',
    AgricultureAdminF: 'Agriculture',
  };

  const token = jwt.sign(
    {
      id: user.id,
      reg_number: user.reg_number,
      // لو الدور قديم من أدوار البنات نوقّعه كـ CollegeAdmin
      role: FEMALE_LEGACY[user.role] ? 'CollegeAdmin' : user.role,
      // نضمن وجود الكلية في التوكن (من الحقل أو من fallback أو من خريطة البنات)
      college:
        user.college ||
        fallback[user.role] ||
        FEMALE_LEGACY[user.role] ||
        null,
    },
    process.env.JWT_SECRET,
    { expiresIn: '2h' }
  );

  res.json({ message: 'تم', token, user });
});




app.post('/api/student-login', async (req,res)=>{
  const { reg_number, password } = req.body;
  if(!reg_number || !password)
    return res.status(400).json({message:'رقم التسجيل وكلمة السر مطلوبة'});

  const { rows } = await pool.query('SELECT * FROM students WHERE reg_number=$1',[reg_number]);
  if(!rows.length) return res.status(400).json({message:'بيانات خاطئة'});

  const stu = rows[0];
  const ok  = await bcrypt.compare(password, stu.password);
  if(!ok)   return res.status(400).json({message:'بيانات خاطئة'});

  const token = jwt.sign({
    id: stu.id,
    reg_number: stu.reg_number,
    college: stu.college,
    gender: stu.gender,      // مهم
    role: 'student'          // مفيد للتمييز
  }, process.env.JWT_SECRET, { expiresIn: '2h' });


  res.json({message:'تم', token, student: stu});
});


app.post('/api/forgot-password', async (req,res)=>{
  const { value:v, error } = Joi.object({
    email: Joi.string().email().required()
  }).validate(req.body);
  if(error) return res.status(400).json({message:error.message});

  const { rows } = await pool.query(`
    SELECT email FROM users       WHERE email=$1
    UNION
    SELECT email FROM students    WHERE email=$1
    UNION
    SELECT email FROM supervisors WHERE email=$1`, [v.email]);
  if(!rows.length) return res.status(404).json({message:'البريد غير مسجَّل'});

  const code = crypto.randomInt(100000,999999).toString();
  const expire = new Date(Date.now()+15*60*1000);

  await pool.query(`
    INSERT INTO password_resets (email,code,expires_at)
    VALUES ($1,$2,$3)`, [v.email, code, expire]);

  await mailer.sendMail({
    from   : `"Quran App" <${process.env.SMTP_USER}>`,
    to     : v.email,
    subject: 'كود إعادة تعيين كلمة السر',
    text   : `رمز التحقق الخاص بك هو: ${code} (صالح لـ15 دقيقة)`
  });

  res.json({message:'تم إرسال الكود'});
});

app.post('/api/reset-password', async (req,res)=>{
  const { value:v, error } = Joi.object({
    email       : Joi.string().email().required(),
    code        : Joi.string().length(6).required(),
    new_password: Joi.string().min(4).max(50).required()
  }).validate(req.body);
  if(error) return res.status(400).json({message:error.message});

  const { rows } = await pool.query(`
    SELECT * FROM password_resets
     WHERE email=$1 AND code=$2 AND expires_at>NOW()
  ORDER BY id DESC LIMIT 1`, [v.email, v.code]);
  if(!rows.length) return res.status(400).json({message:'كود غير صالح'});

  const hash = await bcrypt.hash(v.new_password,10);
  const tables=['users','students','supervisors'];
  let updated=false;
  for(const t of tables){
    const r = await pool.query(`UPDATE ${t} SET password=$1 WHERE email=$2`,[hash, v.email]);
    if(r.rowCount){updated=true;break;}
  }
  if(!updated) return res.status(500).json({message:'الحساب غير موجود'});

  await pool.query('DELETE FROM password_resets WHERE email=$1',[v.email]);
  res.json({message:'تم تحديث كلمة السر'});
});


/* ═════════════════════ 8) المستخدمون (إدمن) ═════════════════════ */

app.get('/api/users', auth, async (_req,res)=>{
  const { rows } = await pool.query(`
    SELECT id,reg_number,role,college,name,phone,email
      FROM users
  ORDER BY role`);
  res.json(rows);
});

app.put('/api/users/:id', auth, async (req,res)=>{
  const allowedRoles = ['admin_dashboard','admin_dash_f'];
  if (!allowedRoles.includes(req.user.role))
    return res.status(403).json({ message: 'غير مخوَّل' });

  const { value:v, error } = Joi.object({
    name      : Joi.string().min(3).max(100).required(),
    reg_number: Joi.string().max(50).required(),
    phone     : Joi.string().max(20).allow('',null),
    email     : Joi.string().email().allow('',null)
  }).validate(req.body);
  if(error) return res.status(400).json({message:error.message});

  const id = +req.params.id;
  const emailNorm = v.email?.trim() || null;

  const dup = await pool.query(`
    SELECT id FROM users
     WHERE (reg_number=$1 OR (email=$2 AND $2 IS NOT NULL)) AND id<>$3`,
    [v.reg_number, emailNorm, id]);
  if(dup.rowCount) return res.status(400).json({message:'رقم أو بريد مكرَّر'});

  const { rowCount } = await pool.query(`
    UPDATE users SET
      name=$1, reg_number=$2, phone=$3, email=$4
    WHERE id=$5`,
    [v.name, v.reg_number, v.phone, emailNorm, id]);
  if(!rowCount) return res.status(404).json({message:'المستخدم غير موجود'});

  res.json({message:'تم التحديث'});
});

app.delete('/api/users/:id', auth, async (req,res)=>{
  if(req.user.role!=='admin_dashboard')
    return res.status(403).json({message:'غير مخوَّل'});
  const { rowCount } = await pool.query('DELETE FROM users WHERE id=$1',[+req.params.id]);
  if(!rowCount) return res.status(404).json({message:'المستخدم غير موجود'});
  res.json({message:'تم الحذف'});
});


/* ═════════════════════ 9) إحصاءات سريعة ═════════════════════ */

app.get('/api/students/count', auth, async (req, res) => {
  const gender = req.query.gender;
  const params = [];
  const where = [];

  if (gender) { params.push(gender); where.push(`s.gender = $${params.length}`); }

  if (req.user.role !== 'admin_dashboard' && req.user.college) {
    params.push(req.user.college);
    where.push(`s.college = $${params.length}`);
  }

  const FEMALE_COLLEGES = ['NewCampus','OldCampus','Agriculture'];
  if (FEMALE_COLLEGES.includes(req.user.college)) {
    params.push('female'); where.push(`s.gender = $${params.length}`);
  }

  const { rows:[r] } = await pool.query(`
    SELECT COUNT(*)::int AS count
      FROM students s
     ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
  `, params);
  res.json({ count: r.count });
});


// server.js
app.get('/api/students/me', auth, async (req, res) => {
  const { rows } = await pool.query(
    `SELECT id, name, college, student_type
       FROM students
      WHERE id = $1`,
    [req.user.id]
  );
  res.json(rows[0]);
});


// مشرفون
app.get('/api/supervisors/count', auth, async (req, res) => {
  const gender = req.query.gender;
  const params = [];
  const where = ['1=1'];

  if (gender) { params.push(gender); where.push(`gender = $${params.length}`); }
  if (req.user.role !== 'admin_dashboard' && req.user.college) {
    params.push(req.user.college);
    where.push(`college = $${params.length}`);
  }
  const FEMALE_COLLEGES = ['NewCampus','OldCampus','Agriculture'];
  if (FEMALE_COLLEGES.includes(req.user.college)) {
    params.push('female'); where.push(`gender = $${params.length}`);
  }

  const { rows:[r] } = await pool.query(`
    SELECT COUNT(*)::int AS count
      FROM supervisors
     WHERE ${where.join(' AND ')}
  `, params);
  res.json({ count: r.count });
});


app.get('/api/exam-requests/count', auth, async (req,res)=>{
  const ps = [];
  let where = `er.approved IS NULL AND er.kind='official'`;

  // تقييد كلية لغير المشرف العام
  if (req.user.role !== 'admin_dashboard' && req.user.college) {
    ps.push(req.user.college);
    where += ` AND er.college = $${ps.length}`;
  }

  // فلتر الجنس
  if (req.query.gender === 'male' || req.query.gender === 'female') {
    ps.push(req.query.gender);
    where += ` AND st.gender = $${ps.length}`;
  } else if (req.user.role === 'admin_dash_f') {
    ps.push('female');
    where += ` AND st.gender = $${ps.length}`;
  } else if (req.user.role === 'admin_dashboard') {
    ps.push('male');
    where += ` AND st.gender = $${ps.length}`;
  } else {
    const FEMALE_COLLEGES = ['NewCampus','OldCampus','Agriculture'];
    if (FEMALE_COLLEGES.includes(req.user.college)) {
      ps.push('female');
      where += ` AND st.gender = $${ps.length}`;
    }
  }


  const { rows } = await pool.query(`
    SELECT COUNT(*)::int AS c
      FROM exam_requests er
      JOIN students st ON st.id = er.student_id
     WHERE ${where}
  `, ps);
  res.json({ pending: rows[0].c });
});


app.get('/api/scores/pending-count', auth, async (req,res)=>{
  const ps = [];
  let gWhere = '';

  if (req.query.gender === 'male' || req.query.gender === 'female') {
    ps.push(req.query.gender);
    gWhere = ` AND st.gender = $${ps.length}`;
  } else if (req.user.role === 'admin_dash_f') {
    ps.push('female'); gWhere = ` AND st.gender = $${ps.length}`;
  } else if (req.user.role === 'admin_dashboard') {
    ps.push('male');   gWhere = ` AND st.gender = $${ps.length}`;
  } else {
    const FEMALE_COLLEGES = ['NewCampus','OldCampus','Agriculture'];
    if (FEMALE_COLLEGES.includes(req.user.college)) {
      ps.push('female'); gWhere = ` AND st.gender = $${ps.length}`;
    }
  }


  const { rows } = await pool.query(`
    SELECT COUNT(*)::int AS c
      FROM (
        /* 1) trial pending */
        SELECT er.id
          FROM exam_requests er
          JOIN students st ON st.id = er.student_id
          LEFT JOIN exams e
            ON e.request_id = er.id
           AND e.official   = FALSE
         WHERE er.kind     = 'official'
           AND er.approved = TRUE
           AND e.id        IS NULL
           ${gWhere}

        UNION ALL

        /* 2) official pending after trial pass */
        SELECT er.id
          FROM exam_requests er
          JOIN students st ON st.id = er.student_id
          JOIN exams et
            ON et.request_id = er.id
           AND et.official   = FALSE
           AND et.passed     = TRUE
          LEFT JOIN exams eo
            ON eo.request_id = er.id
           AND eo.official   = TRUE
         WHERE er.kind     = 'official'
           AND er.approved = TRUE
           AND eo.id       IS NULL
           ${gWhere}
      ) t
  `, ps);
  res.json({ pending: rows[0].c });
});


// server.js
app.get('/api/hafadh/count', auth, async (req, res) => {
  const params = [];
  let where = 's.is_hafidh = TRUE';

  // 1) لو تم تمرير gender صراحةً → احترمه للجميع
  if (req.query.gender === 'male' || req.query.gender === 'female') {
    params.push(req.query.gender);
    where += ` AND s.gender = $${params.length}`;
  } else if (req.user.role === 'admin_dash_f') {
    // 2) مسؤولة البنات → افتراضيًا بنات فقط
    params.push('female');
    where += ` AND s.gender = $${params.length}`;
  } else if (req.user.role === 'admin_dashboard') {
    // 3) المسؤول العام (ذكور) → افتراضيًا ذكور فقط
    params.push('male');
    where += ` AND s.gender = $${params.length}`;
  } else if (req.user.college) {
    // 4) مسؤول/ـة كلية واحدة → استنتج الجنس من الكلية
    const FEMALE_COLLEGES = ['NewCampus','OldCampus','Agriculture'];
    params.push(FEMALE_COLLEGES.includes(req.user.college) ? 'female' : 'male');
    where += ` AND s.gender = $${params.length}`;
  }

  const { rows: [r] } = await pool.query(`
    SELECT COUNT(*)::int AS count
      FROM students s
     WHERE ${where}
  `, params);

  res.json({ count: r.count });
});



// server.js - في قسم نقاط النهاية (يفضل بعد نقاط نهاية CRUD)
/* ═════════════════════ 10) إحصائيات الكلية السريعة ═════════════════════ */
// server.js - تعديل نقطة نهاية الإحصائيات
app.get('/api/college-stats/:college',auth, async (req, res) => {

  const college = req.params.college;
  if (!ADMIN_ROLES.includes(req.user.role) && req.user.college !== college) {
    return res.status(403).json({ message: 'غير مخوَّل' });
  }
  
  try {
    // التحقق من صحة اسم الكلية
    if (!VALID_COLLEGES.includes(college)) {
      return res.status(400).json({ message: 'كلية غير صالحة' });
    }

    const stats = await pool.query(`
      SELECT 
        (SELECT COUNT(*) FROM students WHERE college=$1) AS students,
        (SELECT COUNT(*) FROM students WHERE college=$1 AND is_hafidh=true) AS hafidh,
        (SELECT COUNT(*) FROM exam_requests WHERE college=$1 AND approved IS NULL) AS pending_requests,
        (SELECT COUNT(*) FROM (
          SELECT er.id
          FROM exam_requests er
          LEFT JOIN exams e ON e.request_id = er.id
          WHERE er.college=$1 
            AND er.kind='part' 
            AND er.approved=TRUE 
            AND e.id IS NULL
        ) AS t) AS pending_scores,
        (SELECT COUNT(*) FROM supervisors WHERE college=$1) AS supervisors
    `, [college]);

    if (stats.rows.length === 0) {
      return res.status(404).json({ message: 'لا توجد بيانات' });
    }

    res.json(stats.rows[0]);
  } catch (err) {
    console.error('❌ college-stats error:', err);
    res.status(500).json({ message: 'خطأ في الخادم' });
  }
});

/* ═════════════════════ 10) تقارير Excel ═════════════════════ */

app.get('/api/reports/excel', auth, async (req,res)=>{
  try{
    const studentType = req.query.student_type;
    const weeks = req.query.weeks
      ? req.query.weeks.split(',').map(w=>parseInt(w,10)).filter(n=>!Number.isNaN(n))
      : [];

    // فلترة الجنس: مفروضة تلقائياً حسب الدور/الكلية
    const gender = resolveGenderForUser(req, req.query.gender);

    const params=[studentType];
    let where='s.student_type = $1';

    if (gender) {
      params.push(gender);
      where += ` AND s.gender = $${params.length}`;
    }

    if(weeks.length){
      params.push(weeks);
      where += ` AND EXTRACT(WEEK FROM e.created_at)::int = ANY($${params.length})`;
    }

    const { rows } = await pool.query(`
      SELECT
        s.reg_number  AS reg_number,
        s.name        AS student_name,
        s.email       AS email,
        s.phone       AS phone,
        s.college     AS college,
        CASE e.exam_code
          WHEN 'F1' THEN 'خمسة أجزاء الأولى'
          WHEN 'F2' THEN 'خمسة أجزاء الثانية'
          WHEN 'F3' THEN 'خمسة أجزاء الثالثة'
          WHEN 'F4' THEN 'خمسة أجزاء الرابعة'
          WHEN 'F5' THEN 'خمسة أجزاء الخامسة'
          WHEN 'F6' THEN 'خمسة أجزاء السادسة'
          WHEN 'T1' THEN 'عشرة أجزاء الأولى'
          WHEN 'T2' THEN 'عشرة أجزاء الثانية'
          WHEN 'T3' THEN 'عشرة أجزاء الثالثة'
          WHEN 'H1' THEN 'خمسة عشر الأولى'
          WHEN 'H2' THEN 'خمسة عشر الثانية'
          WHEN 'Q'  THEN 'القرآن كامل'
          ELSE e.exam_code
        END          AS exam_name,
        e.score       AS score,
        e.created_at::date  AS created_at
      FROM exams e
      JOIN students s ON s.id = e.student_id
      WHERE ${where}
        AND e.official = TRUE
        AND e.exam_code NOT LIKE 'J%'
      ORDER BY e.exam_code, e.created_at`, params);

    const wb = new ExcelJS.Workbook();
    const ws = wb.addWorksheet('Report');
    ws.columns = [
      { header:'رقم الطالب',        key:'reg_number',   width:15 },
      { header:'اسم الطالب',        key:'student_name', width:25 },
      { header:'البريد الإلكتروني', key:'email',        width:30 },
      { header:'الهاتف',            key:'phone',        width:20 },
      { header:'الكلية',            key:'college',      width:20 },
      { header:'اسم الامتحان',      key:'exam_name',    width:25 },
      { header:'العلامة',           key:'score',        width:10 },
      { header:'التاريخ',           key:'date',         width:15 }
    ];

    const toDateStr = (x) => {
      if (!x) return null;
      if (typeof x === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(x)) return x;
      const d = x instanceof Date ? x : new Date(x);
      return isNaN(d.getTime()) ? null : d.toISOString().split('T')[0];
    };

    rows.forEach(r=>{
      const d = toDateStr(r.created_at) || new Date().toISOString().split('T')[0];
      ws.addRow({
        reg_number   : r.reg_number,
        student_name : r.student_name,
        email        : r.email,
        phone        : r.phone,
        college      : r.college,
        exam_name    : r.exam_name,
        score        : r.score,
        date         : d
      });
    });

    // اسم ملف يوضح الجنس (اختياري)
    const suffix = gender ? (gender === 'female' ? '_female' : '_male') : '';
    res.setHeader('Content-Disposition',`attachment; filename="report${suffix}.xlsx"`);
    res.setHeader('Content-Type','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    await wb.xlsx.write(res);
    res.end();
  }catch(e){
    console.error('reports/excel error', e);
    res.status(500).json({message:'خطأ في الخادم'});
  }
});


app.get('/api/reports/parts-excel', auth, async (req,res)=>{
  const college = req.query.college;
  if(!college) return res.status(400).json({message:'college مطلوب'});

  const weeks = req.query.weeks
    ? req.query.weeks.split(',').map(w=>parseInt(w,10))
    : [];

  const params=[college];
  let where = `
    s.college = $1
    AND e.official = TRUE
    AND e.exam_code LIKE 'J%'`;
  if(weeks.length){
    params.push(weeks);
    where += ` AND EXTRACT(WEEK FROM e.created_at)::int = ANY($${params.length})`;
  }

  try{
    const { rows } = await pool.query(`
      SELECT
        s.reg_number,
        s.name  AS student_name,
        s.email,
        s.phone,
        s.college,
        e.exam_code,
        e.score,
        e.created_at::date AS created_at
      FROM exams e
      JOIN students s ON s.id = e.student_id
      WHERE ${where}
      ORDER BY e.exam_code, e.created_at`, params);

    const toArabicName = code => code.startsWith('J') ? `جزء ${parseInt(code.slice(1),10)}` : code;

    const wb = new ExcelJS.Workbook();
    const ws = wb.addWorksheet('Parts Report');
    ws.columns = [
      { header:'رقم الطالب',        key:'reg_number',   width:15 },
      { header:'اسم الطالب',        key:'student_name', width:25 },
      { header:'البريد الإلكتروني', key:'email',        width:30 },
      { header:'الهاتف',            key:'phone',        width:20 },
      { header:'الكلية',            key:'college',      width:20 },
      { header:'الجزء',             key:'exam_name',    width:15 },
      { header:'العلامة',           key:'score',        width:10 },
      { header:'التاريخ',           key:'date',         width:15 }
    ];

    rows.forEach(r=>{
      const d = toDateStr(r.created_at) || todayStr();
      ws.addRow({
        reg_number  : r.reg_number,
        student_name: r.student_name,
        email       : r.email,
        phone       : r.phone,
        college     : r.college,
        exam_name   : toArabicName(r.exam_code),
        score       : r.score,
        date        : d
      });
    });

    res.setHeader('Content-Disposition','attachment; filename="parts_report.xlsx"');
    res.setHeader('Content-Type','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    await wb.xlsx.write(res);
    res.end();
  }catch(e){
    console.error('parts-excel error', e);
    res.status(500).json({message:'خطأ في الخادم'});
  }
});
// توليد ملف ZIP يحوي جميع الشهادات الرسمية ضمن الفترة التى يختارها المستخدم
app.get('/api/reports/bulk-certificates', auth, async (req, res, next) => {
  try {
    const { start, end } = req.query;

    // فلترة الجنس: مفروضة تلقائياً حسب الدور/الكلية
    const gender = resolveGenderForUser(req, req.query.gender);

    const params = [];
    let where =
      `e.official = TRUE AND e.passed = TRUE AND e.exam_code NOT LIKE 'J%'`;

    if (gender) {
      params.push(gender);
      where += ` AND s.gender = $${params.length}`;
    }
    if (start) { params.push(start); where += ` AND e.created_at::date >= $${params.length}`; }
    if (end)   { params.push(end);   where += ` AND e.created_at::date <= $${params.length}`; }

    const { rows } = await pool.query(`
      SELECT e.id, e.score,
             e.created_at::date         AS d,
             s.name,
             e.exam_code,
             CASE e.exam_code
               WHEN 'Q'  THEN 'القرآن كامل'
               WHEN 'H1' THEN 'خمسة عشر الأولى'
               WHEN 'H2' THEN 'خمسة عشر الثانية'
               WHEN 'F1' THEN 'خمسة أجزاء الأولى'
               WHEN 'F2' THEN 'خمسة أجزاء الثانية'
               WHEN 'F3' THEN 'خمسة أجزاء الثالثة'
               WHEN 'F4' THEN 'خمسة أجزاء الرابعة'
               WHEN 'F5' THEN 'خمسة أجزاء الخامسة'
               WHEN 'F6' THEN 'خمسة أجزاء السادسة'
               WHEN 'T1' THEN 'عشرة أجزاء الأولى'
               WHEN 'T2' THEN 'عشرة أجزاء الثانية'
               WHEN 'T3' THEN 'عشرة أجزاء الثالثة'
               ELSE e.exam_code
             END AS arabic_name
        FROM exams e
        JOIN students s ON s.id = e.student_id
       WHERE ${where}`, params);

    if (!rows.length) return res.status(404).json({ message: 'لا نتائج' });

    const suffix = gender ? (gender === 'female' ? '_female' : '_male') : '';
    res.setHeader('Content-Disposition', `attachment; filename="certificates${suffix}.zip"`);
    res.setHeader('Content-Type',        'application/zip');

    const archive = archiver('zip');
    archive.on('error', err => {
      console.error('❌ ZIP error:', err);
      if (!res.headersSent) return next(err);
      res.end();
    });
    archive.pipe(res);

    const tasks = rows.map(r => new Promise((resolve, reject) => {
      const pdf = new PDFDocument({ size: 'A4', margin: 50 });
      const chunks = [];

      pdf.on('data', chunk => chunks.push(chunk));
      pdf.on('end', () => {
        // اسم ملف الشهادة داخل الـ ZIP
        const safeName = `${r.name}-${r.arabic_name}`.replace(/[\\/:*?"<>|]+/g,'-');
        archive.append(Buffer.concat(chunks), { name: `${safeName}.pdf` });
        resolve();
      });
      pdf.on('error', reject);

      drawCertificate(pdf, {
        student : { name: r.name },
        exam    : r,
        dateStr : r.d
      });
      pdf.end();
    }));

    await Promise.all(tasks);
    archive.finalize();

  } catch (err) {
    next(err);
  }
});








app.use((err, _req, res, _next) => {
  console.error('‼️', err);          // سجّل الخطأ فى الكونسول
  if (res.headersSent) return;       // لو الهيدر أُرسل اكتفِ بالصمت
  res.status(500).json({ message: 'Internal error' });
});

// كلّ يوم عند منتصف الليل: تذكير بالجزء المتأخر (عندما الخطة غير موقوفة)
cron.schedule('0 0 * * *', async () => {
  /* ❶ جلب الطلاب الذين تجاوزوا due_date + 2 أيام
        ولم يجروا بعد الامتحان الرسمي للجزء الحالي */
  const { rows } = await pool.query(`
    SELECT 
      p.student_id,
      p.current_part,
      s.name,
      s.email,
      p.due_date
    FROM plans p
    JOIN students s ON s.id = p.student_id
    WHERE p.approved             = TRUE
      AND p.paused_for_official  = FALSE         -- الخطة غير متوقّفة
      AND now()::date > p.due_date + 2           -- متأخر يومين فأكثر
      AND NOT EXISTS (                           -- لا يوجد امتحان رسمى مُسجَّل
            SELECT 1
              FROM exams e
             WHERE e.student_id = p.student_id
               AND e.exam_code  = 'J' || LPAD(p.current_part::text, 2, '0')
               AND e.official   = TRUE
          )
  `);

  /* ❷ إرسال البريد لكل طالب */
  for (const r of rows) {
    try {
      await mailer.sendMail({
        from   : `"Quran App" <${process.env.SMTP_USER}>`,
        to     : r.email,
        subject: `⚠️ تأخر في تسجيل امتحان الجزء ${r.current_part}`,
        text   :
`السلام عليكم ${r.name},

لقد انتهت مدة خطتك للجزء ${r.current_part} بتاريخ ${r.due_date}، ولم تسجل الامتحان الرسمي لهذا الجزء بعد.
يرجى التوجه إلى المنصة لتسجيل الامتحان وإجرائه في أقرب وقت.

مع تحيات
إدارة ملتقى القرآن الكريم`
      });
    } catch (e) {
      console.error('❌ خطأ في إرسال إيميل التذكير بالجزء:', e);
    }
  }
});


// كلّ يوم عند منتصف الليل: تذكير بالامتحانات الرسمية التي لم يُسجِّلها الطالب
cron.schedule('0 0 * * *', async () => {
  const { rows } = await pool.query(`
    SELECT p.student_id, p.official_exams, s.name, s.email, p.due_date
      FROM plans p
      JOIN students s ON s.id = p.student_id
     WHERE p.approved = TRUE
       AND p.official_attended = TRUE
       AND now()::date > p.due_date + 2
       AND NOT EXISTS (
         SELECT 1 FROM exam_requests er
          WHERE er.student_id = p.student_id
            AND er.kind = 'official'
            AND er.exam_code = ANY(p.official_exams)
       )
  `);

  for (const r of rows) {
    for (const code of r.official_exams) {
      try {
        await mailer.sendMail({
          from:    `"Quran App" <${process.env.SMTP_USER}>`,
          to:      r.email,
          subject: `⚠️ تأخر في تسجيل الامتحان الرسمي: ${code}`,
          text: `السلام عليكم ${r.name},

لقد انتهت خطة الامتحان الرسمي (${code}) بتاريخ ${r.due_date}، ولم تسجل طلب الامتحان بعد.
يرجى التوجه للتسجيل في أقرب وقت.
`
        });
      } catch (e) {
        console.error('❌ خطأ في إرسال إيميل التذكير الرسمي:', e);
      }
    }
  }
});


/* ───────── تشغيل الخادم ───────── */
const PORT = process.env.PORT || 5000;
app.listen(PORT, ()=> console.log(`✅ Server running on port ${PORT}`));
