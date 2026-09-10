// Rebuild the installer artwork from the existing, independently owned logos.
// Run from any directory with Node.js and sharp available in NODE_PATH.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const eco = path.resolve(__dirname, '../..');
const tools = [
  ['Baa', 'باء', 'لغة برمجة عربية', 'BAA', '#57a5ff', 'resources/Logo.png'],
  ['Nazm', 'نظم', 'مجمّع للأنظمة', 'NAZM', '#7fa7ff', 'resources/branding/nazm-512.png'],
  ['Takween', 'تكوين', 'من المشروع إلى البرنامج', 'TAKWEEN', '#32d5bd', 'resources/branding/takween-512.png'],
  ['Qalam-IDE', 'قلم', 'مساحة تطوير عربية', 'QALAM', '#58c7ea', 'qalam/resources/QalamLogo.png'],
  ['Baa-Developer-Kit', 'عدة تطوير باء', 'أدواتك في مكان واحد', 'DEVELOPER KIT', '#32d5bd', 'assets/branding/developer-kit-512.png'],
];

async function main() {
  sharp.concurrency(1);
  for (const [repo, title, subtitle, english, accent, logo] of tools) {
    const dir = path.join(eco, repo, 'installer');
    fs.mkdirSync(dir, { recursive: true });
    const mark = await sharp(path.join(eco, repo, logo)).trim()
      .resize(320, 320, { fit: 'contain', background: '#00000000' }).png().toBuffer();
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="656" height="1256" viewBox="0 0 656 1256">
      <defs><linearGradient id="bg" x2="1" y2="1"><stop stop-color="#091329"/><stop offset="1" stop-color="#132c49"/></linearGradient>
      <radialGradient id="glow"><stop stop-color="${accent}" stop-opacity=".16"/><stop offset="1" stop-color="${accent}" stop-opacity="0"/></radialGradient></defs>
      <rect width="656" height="1256" fill="url(#bg)"/>
      <circle cx="328" cy="350" r="390" fill="url(#glow)"/>
      <path d="M48 72H608" stroke="${accent}" stroke-width="4"/>
      <text x="328" y="135" text-anchor="middle" fill="#a9bed6" font-family="Segoe UI" font-size="27">منظومة باء</text>
      <image href="data:image/png;base64,${mark.toString('base64')}" x="168" y="224" width="320" height="320"/>
      <text x="328" y="663" text-anchor="middle" fill="#f4f8ff" font-family="Segoe UI" font-size="${repo === 'Baa-Developer-Kit' ? 60 : 76}" font-weight="600">${title}</text>
      <text x="328" y="720" text-anchor="middle" fill="${accent}" font-family="Segoe UI" font-size="25" letter-spacing="3">${english}</text>
      <text x="328" y="810" text-anchor="middle" fill="#b5c8de" font-family="Segoe UI" font-size="30">${subtitle}</text>
      <g fill="none" stroke="${accent}" stroke-width="2" opacity=".16"><path d="M-60 1050L180 910H450L710 1060M-60 1110L180 970H450L710 1120M-60 1170L180 1030H450L710 1180"/><path d="M180 910V1150M450 910V1150"/></g>
      <circle cx="76" cy="1170" r="5" fill="${accent}"/>
      <text x="580" y="1180" text-anchor="end" fill="#99afc8" font-family="Segoe UI" font-size="24">اكتب. ابنِ. انطلق.</text>
    </svg>`;
    fs.writeFileSync(path.join(dir, 'wizard-sidebar.svg'), svg);
    await sharp(Buffer.from(svg)).png().toFile(path.join(dir, 'wizard-sidebar.png'));
    await sharp(mark).resize(128, 128).png().toFile(path.join(dir, 'wizard-mark.png'));
    if (repo !== 'Baa-Developer-Kit') fs.copyFileSync(
      path.join(eco, 'Baa-Developer-Kit/installer/windows_wizard.iss'),
      path.join(dir, 'windows_wizard.iss'));
    process.stdout.write(`${repo}: installer artwork and shared presentation ready\n`);
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
