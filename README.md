# عدة تطوير باء

هذا المستودع يملك المثبت الشامل غير المتصل بالإنترنت لمنظومة باء على Windows.
لا ينسخ المثبت الشامل ملفات الأدوات ولا يخلط ملكيتها؛ بل يتحقق من المثبتات
المستقلة ثم يشغلها بصمت بالترتيب التالي:

1. نظم
2. باء
3. تكوين
4. قلم

يبقى لكل مكوّن مثبت وإصدار وإزالة مستقلة. يضيف نظم وباء وتكوين أوامرها العامة
فقط إلى `PATH`، بينما لا يضيف قلم أو Baa-LSP أي مسار عام.

## العقد

- [`eco-installer-manifest-v1`](contracts/eco-installer-manifest-v1.schema.json)
  يثبت هوية كل مثبت وإصداره وهضم SHA-256 وترتيب التثبيت وفحص الصحة.
- [عقد مثبتات Windows](docs/WINDOWS_INSTALLER_CONTRACT.md) يثبت قواعد الصلاحيات
  و`PATH` والترقية والإزالة والتشغيل الصامت.
- [`windows_environment.iss`](installer/windows_environment.iss) هو المرجع
  المشترك لإدارة `PATH` ومتغيرات البيئة المملوكة بأمان.

## البناء

بعد بناء المثبتات الأربعة في مستودعاتها المجاورة، ينشئ الأمر التالي البيان
والمثبت الشامل غير المتصل وملف SHA-256:

```powershell
.\scripts\Build-DeveloperKitInstaller.ps1
```

الناتج هو:

- `dist/installer/baa-developer-kit-setup-0.1.0-x64.exe`
- `dist/installer/baa-developer-kit-setup-0.1.0-x64.exe.sha256`
- `dist/eco-installer-manifest-v1.json`

لا يقبل البناء ملفًا مفقودًا أو اسمًا غير مطابق أو ملف SHA-256 غير صالح. ويمكن
توقيع المثبت عند توافر شهادة إصدار بتمرير اسمي أداة التوقيع وأمرها كما يعرفهما
Inno Setup:

```powershell
.\scripts\Build-DeveloperKitInstaller.ps1 `
  -SignToolName releasesign `
  -SignToolCommand '<signtool command using $f>'
```

## التحقق المحلي

يتطلب اختبار دورة الحياة صلاحيات تثبيت البرامج لأنه يشغل المثبتات الحقيقية،
ثم يعيد تشغيلها للإصلاح ويزيلها:

```powershell
.\scripts\Test-DeveloperKitInstaller.ps1
```

يستخدم الاختبار مجلدًا مؤقتًا طويلًا يحوي العربية والمسافات، ويتحقق من أوامر
نظم وباء وتكوين، ويبني ويشغل برنامج باء، ويبدأ قلم وBaa-LSP، ثم يتحقق من
السجلات والبيان ومن استعادة البيئة بعد الإزالة.

## التشغيل الصامت

```powershell
.\baa-developer-kit-setup-0.1.0-x64.exe `
  /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS
```

يستخدم `/CURRENTUSER` بدل `/ALLUSERS` للتثبيت الخاص بالمستخدم. يحتفظ المثبت
بالسجلات في `BaaEcosystem/InstallerLogs` تحت `ProgramData` أو `LocalAppData`
بحسب النطاق.

راجع [قائمة تحقق الإصدار](docs/RELEASE_CHECKLIST.md) قبل نشر أي بناء عام.
