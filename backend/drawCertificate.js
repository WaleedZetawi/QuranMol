/****************************************************************
 *  drawCertificate.js – شهادة PDF عربية فاخرة (≈300 dpi)
 *  يتطلّب: pdfkit  +  @napi-rs/canvas ≥ 0.2  +  arabic-reshaper
 ****************************************************************/
const path           = require('path');
const PDFDocument    = require('pdfkit');
const ArabicReshaper = require('arabic-reshaper');
const { createCanvas, GlobalFonts } = require('@napi-rs/canvas');

/*── الخطوط ──*/
const AMIRI_TTF = path.join(__dirname, 'fonts', 'Amiri-Regular.ttf');
GlobalFonts.registerFromPath(AMIRI_TTF, 'Amiri');

/*── الصور ──*/
const ASSETS   = path.join(__dirname, '..', 'moltaqa_app', 'assets');
const LOGO_TOP = path.join(ASSETS, 'logo1.png');
const LOGO_WM  = path.join(ASSETS, 'logo2.jpg');

/*── ألوان وثوابت ──*/
const NAVY  = '#0C3C60';
const GOLD  = '#D4AF37';
const GREEN = '#16794F';
const PAPER = '#FFFEFC';

const INNER_MAX_W  = 450;
const CANVAS_SCALE = 3;
const TOP_START_Y  = 190;
const BOTTOM_PAD   = 90;
const SIGN_Y_OFF   = 100;

/* تحريك الكتلة مع تثبيت السطر الأخير */
const SHIFT_DOWN = 40;

/*════════════ أدوات مساعدة ════════════*/
const toArabicDigits = s =>
  String(s).replace(/\d/g, d => String.fromCharCode(0x0660 + +d));

const fmtDate = iso => {
  const d = new Date(iso);
  return isNaN(d)
    ? iso
    : toArabicDigits(
        d.toLocaleDateString('ar-EG', { day: 'numeric', month: 'numeric', year: 'numeric' })
      );
};

/* نصّ → PNG */
function textToPNG(txt, fz, color = '#000', maxW = null, scale = CANVAS_SCALE) {
  const shaped = ArabicReshaper.convertArabic(String(txt));
  const pad = 14;

  const ctxProbe = createCanvas(1, 1).getContext('2d');
  ctxProbe.font = `${fz}px "Amiri"`;
  const m    = ctxProbe.measureText(shaped);
  const asc  = m.actualBoundingBoxAscent  || fz * 0.8;
  const desc = m.actualBoundingBoxDescent || fz * 0.2;

  const W = maxW ? Math.min(m.width + pad * 2, maxW) : m.width + pad * 2;
  const H = asc + desc + pad * 2;

  const cnv = createCanvas(W * scale, H * scale);
  const ctx = cnv.getContext('2d');
  ctx.scale(scale, scale);
  ctx.font         = `${fz}px "Amiri"`;
  ctx.fillStyle    = color;
  ctx.direction    = 'rtl';
  ctx.textAlign    = 'right';
  ctx.textBaseline = 'alphabetic';
  ctx.fillText(shaped, W - pad, pad + asc);

  return { buf: cnv.toBuffer('image/png'), w: W, h: H };
}

/*════════════ إطار وفواصل ════════════*/
function drawFancyFrame(doc) {
  const { width: W, height: H } = doc.page;
  const M = 40;

  doc.rect(0, 0, W, H).fill(PAPER);

  doc.save()
     .lineWidth(9)
     .strokeColor(NAVY)
     .roundedRect(M, M, W - 2 * M, H - 2 * M, 24)
     .stroke()
     .restore();

  const inX = M + 12, inY = M + 12, inW = W - 2 * M - 24, inH = H - 2 * M - 24;
  doc.save()
     .lineWidth(4)
     .strokeColor(GOLD)
     .roundedRect(inX, inY, inW, inH, 18)
     .stroke()
     .restore();

  doc.save()
     .fillColor(GOLD)
     .opacity(0.15)
     .roundedRect(inX - 2, inY - 2, inW + 4, inH + 4, 20)
     .fill()
     .opacity(1)
     .restore();
}

const separator = (doc, y) =>
  doc.save()
     .lineWidth(2)
     .strokeColor(GOLD)
     .moveTo(120, y)
     .lineTo(doc.page.width - 120, y)
     .stroke()
     .restore();

/*════════════ الدالة الرئيسية ════════════*/
function drawCertificate(doc, { student, exam, dateStr }) {
  const gender = (student && student.gender) === 'female' ? 'female' : 'male';
  const isF = gender === 'female';

  drawFancyFrame(doc);

  doc.image(LOGO_TOP, (doc.page.width - 110) / 2, 60, { width: 110 });

  // ختم مائي
  const WM_W = 520;
  doc.opacity(0.08)
     .image(
       LOGO_WM,
       (doc.page.width - WM_W) / 2,
       (doc.page.height - WM_W) / 2,
       { width: WM_W }
     )
     .opacity(1);

  // لو الدرجة غير متوفرة، نستخدم صياغة "اجتياز" بدل "حصوله/حصولها على … درجة"
  const hasScore = typeof exam.score === 'number' && !Number.isNaN(exam.score);
  const scoreTxt = hasScore ? toArabicDigits(Number(exam.score).toFixed(2)) : null;

  const blocks = [
    { txt: 'شهادة شكر وتقدير', size: 36, clr: GREEN, gap: 30 },
    { txt: 'تتشرف إدارة ملتقى القرآن الكريم بمنح هذه الشهادة لـ', size: 18, clr: '#000', gap: 25 },
    { txt: student.name, size: 28, clr: GOLD, gap: 38 },
    { txt: `وذلك تقديرًا لتفوّق${isF ? 'ها' : 'ه'} في اجتياز « ${exam.arabic_name} »`, size: 18, clr: '#000', gap: 28 },
    hasScore
      ? { txt: `بعد حصول${isF ? 'ها' : 'ه'} على ${scoreTxt} درجة من ${toArabicDigits(100)} بتاريخ ${fmtDate(dateStr)}`, size: 18, clr: '#000', gap: 32 }
      : { txt: `وذلك بتاريخ ${fmtDate(dateStr)}`, size: 18, clr: '#000', gap: 32 },
    { txt: `نسأل الله ل${isF ? 'ها' : 'ه'} دوام التوفيق والسداد`, size: 16, clr: '#000', gap: 0 }
  ];

  const rendered = blocks.map(b => textToPNG(b.txt, b.size, b.clr, INNER_MAX_W));
  const totalH   = rendered.reduce((s, m, i) => s + m.h + blocks[i].gap, 0) + 20;

  let y = TOP_START_Y + SHIFT_DOWN;
  if (y + totalH + BOTTOM_PAD > doc.page.height - SIGN_Y_OFF) {
    y = doc.page.height - totalH - BOTTOM_PAD - SIGN_Y_OFF + SHIFT_DOWN;
  }

  const title = rendered[0];
  const grad  = doc.linearGradient(0, 0, title.w, 0).stop(0, GREEN).stop(1, GOLD);
  doc.save()
     .fill(grad)
     .image(title.buf, (doc.page.width - title.w) / 2, y, { width: title.w })
     .restore();

  y += title.h + 10;
  separator(doc, y);
  y += 20 + blocks[0].gap - 30;

  for (let i = 1; i < blocks.length; i++) {
    const yPos = (i === blocks.length - 1) ? y - SHIFT_DOWN : y;
    doc.image(
      rendered[i].buf,
      (doc.page.width - rendered[i].w) / 2,
      yPos,
      { width: rendered[i].w }
    );
    y = yPos + rendered[i].h + blocks[i].gap;

    if (i === 3) {
      separator(doc, y - 14);
      y += 24;
    }
  }

  const { buf: sigBuf, w: sigW } = textToPNG('إدارة ملتقى القرآن الكريم', 14);
  doc.image(sigBuf, (doc.page.width - sigW) / 2, doc.page.height - SIGN_Y_OFF, { width: sigW });
}

module.exports = drawCertificate;
