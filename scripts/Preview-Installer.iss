; Presentation fixture: contains no component files or install actions.
[Setup]
AppName=معاينة مثبتات منظومة باء
AppVersion=0.6.0
DefaultDirName={tmp}\EcoInstallerPreview
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=lowest
DisableWelcomePage=no
DisableDirPage=yes
DisableProgramGroupPage=yes
WizardStyle=modern
WizardSizePercent=110,110
WizardImageFile=..\installer\wizard-sidebar.png
WizardSmallImageFile=..\installer\wizard-mark.png
OutputDir=..\dist\preview
OutputBaseFilename=installer-preview
SetupLogging=yes
CompressionThreads=1

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
[LangOptions]
DialogFontName=Segoe UI
DialogFontSize=10
[Messages]
arabic.WelcomeLabel1=معاينة التصميم والسجل
arabic.WelcomeLabel2=معاينة مرئية فقط. لن تثبت هذه الأداة أي برنامج.%n%nاضغط التالي لعرض نموذج سجل التثبيت.
english.WelcomeLabel1=Installer design preview
english.WelcomeLabel2=Visual preview only. This tool installs no programs.%n%nChoose Next to inspect a sample installation log.
[Code]
#include "..\installer\windows_wizard.iss"
var
  PreviewPage: TWizardPage;
procedure InitializeWizard;
begin
  PreviewPage := CreateCustomPage(wpWelcome,
    EcoText('سجل التثبيت — معاينة', 'Installation log — preview'),
    EcoText('بيانات تجريبية لعرض التصميم فقط', 'Sample data for visual inspection only'));
  EcoLogHeading.Parent := PreviewPage.Surface;
  EcoLogHeading.SetBounds(0, 0, PreviewPage.SurfaceWidth, ScaleY(22));
  EcoLogMemo.Parent := PreviewPage.Surface;
  EcoLogMemo.SetBounds(0, ScaleY(30), PreviewPage.SurfaceWidth,
    PreviewPage.SurfaceHeight - ScaleY(36));
  EcoWizardLog('info', EcoText('تم التحقق من سلامة الحزمة.', 'Package integrity verified.'));
  EcoWizardLog('info', EcoText('تثبيت نظم (1/4)', 'Installing Nazm (1/4)'));
  EcoWizardLog('success', EcoText('اكتمل تثبيت نظم.', 'Nazm installation complete.'));
  EcoWizardLog('info', EcoText('تثبيت باء (2/4)', 'Installing Baa (2/4)'));
  EcoWizardLog('error', EcoText('مثال على رسالة خطأ واضحة. افتح السجل للتفاصيل.',
    'Example of a clear error message. Open the log for details.'));
end;
procedure CurPageChanged(CurPageID: Integer);
begin
  EcoOpenLogButton.Visible := CurPageID = PreviewPage.ID;
  WizardForm.NextButton.Visible := CurPageID <> PreviewPage.ID;
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  Cancel := True;
  Confirm := False;
end;
