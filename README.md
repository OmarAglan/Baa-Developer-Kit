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

## إنشاء بيان إصدار

بعد بناء المثبتات الأربعة:

```powershell
.\scripts\New-EcoInstallerManifest.ps1 `
  -NazmInstaller ..\Nazm\dist\installer\nazm-setup-0.4.0-x64.exe `
  -BaaInstaller ..\Baa\dist\installer\baa-setup-0.6.0-x64.exe `
  -TakweenInstaller ..\Takween\dist\installer\takween-setup-0.1.0-x64.exe `
  -QalamInstaller ..\Qalam-IDE\dist\installer\qalam-setup-3.3.0-x64.exe
```

ينتج الأمر `dist/eco-installer-manifest-v1.json`. لا يقبل بناء المثبت الشامل
ملفًا مفقودًا أو هضمًا صفريًا أو اسم مثبت غير مطابق.
