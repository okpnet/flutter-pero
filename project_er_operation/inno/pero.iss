; PERO インストーラー
; GitHub の release に置いた zip をダウンロードして展開する(ダウンロード型)。
; ビルド: inno\build_installer.ps1(ISCC /DAppVersion=x.y.z で版を渡す)

#ifndef AppVersion
  #define AppVersion "0.4.1"
#endif
#define AppName "PERO"
#define AppExe "project_er_operation.exe"
#define GitHubRepo "okpnet/flutter-pero"
#define ZipName "PERO-v" + AppVersion + "-windows-x64.zip"
#define ZipUrl "https://github.com/" + GitHubRepo + "/releases/download/v" + AppVersion + "/" + ZipName
#define LatestApiUrl "https://api.github.com/repos/" + GitHubRepo + "/releases/latest"
#define ReleasePageUrl "https://github.com/" + GitHubRepo + "/releases/latest"

[Setup]
; 同じ AppId のインストール済みアプリは上書き更新(アップデート)になる
AppId={{6B0E3C54-7A1D-4F52-9C1E-5E2A4D9B7A10}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=okpnet
AppPublisherURL=https://github.com/{#GitHubRepo}
AppSupportURL=https://github.com/{#GitHubRepo}/issues
AppUpdatesURL={#ReleasePageUrl}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; 管理者権限は要求しない(settings.json を実行ファイル直下に書けるようにするため)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ArchiveExtraction=auto
OutputDir=..\build\windows\setup
OutputBaseFilename=pero_{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
; アンインストール(アプリと機能)のアイコンをアプリアイコンにする
UninstallDisplayIcon={app}\{#AppExe}
WizardStyle=modern
WizardImageFile=..\assets\icons\pero.png
WizardSmallImageFile=..\assets\icons\pero.png
Compression=lzma2
SolidCompression=yes

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Tasks]
Name: "desktopicon"; Description: "デスクトップにアイコンを作成する(&D)"; Flags: unchecked

[Files]
; ダウンロードした zip を展開してインストールする
Source: "{tmp}\{#ZipName}"; DestDir: "{app}"; Flags: external extractarchive recursesubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{#AppName} を起動する"; Flags: nowait postinstall skipifsilent

[Code]
var
  DownloadPage: TDownloadWizardPage;

function NextVersionPart(var S: String): Integer;
var
  P: Integer;
begin
  P := Pos('.', S);
  if P = 0 then P := Length(S) + 1;
  Result := StrToIntDef(Copy(S, 1, P - 1), 0);
  Delete(S, 1, P);
end;

{ "v1.2.3" または "1.2.3" を比較する。a > b なら 1、a < b なら -1、同じなら 0 }
function CompareVersion(A, B: String): Integer;
var
  PartA, PartB: Integer;
begin
  Result := 0;
  if (Length(A) > 0) and (A[1] = 'v') then Delete(A, 1, 1);
  if (Length(B) > 0) and (B[1] = 'v') then Delete(B, 1, 1);
  while (A <> '') or (B <> '') do
  begin
    PartA := NextVersionPart(A);
    PartB := NextVersionPart(B);
    if PartA > PartB then begin Result := 1; Exit; end;
    if PartA < PartB then begin Result := -1; Exit; end;
  end;
end;

{ 最新リリースを検索し、このインストーラーより新しい版があれば知らせる。失敗しても何もしない }
procedure CheckForUpdate;
var
  Json, Tag: String;
  Raw: AnsiString;
  P, Q: Integer;
begin
  try
    DownloadTemporaryFile('{#LatestApiUrl}', 'latest.json', '', nil);
    if not LoadStringFromFile(ExpandConstant('{tmp}\latest.json'), Raw) then Exit;
    Json := String(Raw);
    P := Pos('"tag_name"', Json);
    if P = 0 then Exit;
    Delete(Json, 1, P + Length('"tag_name"') - 1);
    P := Pos('"', Json);
    if P = 0 then Exit;
    Delete(Json, 1, P);
    Q := Pos('"', Json);
    if Q = 0 then Exit;
    Tag := Copy(Json, 1, Q - 1);
    if CompareVersion(Tag, '{#AppVersion}') > 0 then
      SuppressibleMsgBox(
        '新しいバージョン(' + Tag + ')が公開されています。' + #13#10 +
        'このインストーラーは {#AppVersion} です。' + #13#10 +
        '最新のインストーラーを次のページから入手できます。' + #13#10 +
        '{#ReleasePageUrl}',
        mbInformation, MB_OK, IDOK);
  except
    Log('アップデートの検索に失敗: ' + GetExceptionMessage);
  end;
end;

function InitializeSetup: Boolean;
begin
  Result := True;
  if not WizardSilent then CheckForUpdate;
end;

procedure InitializeWizard;
begin
  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing), SetupMessage(msgPreparingDesc), nil);
  DownloadPage.ShowBaseNameInsteadOfUrl := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpReady then
  begin
    DownloadPage.Clear;
    DownloadPage.Add('{#ZipUrl}', '{#ZipName}', '');
    DownloadPage.Show;
    try
      try
        DownloadPage.Download;
      except
        if not DownloadPage.AbortedByUser then
          SuppressibleMsgBox(AddPeriod(GetExceptionMessage), mbCriticalError, MB_OK, IDOK);
        Result := False;
      end;
    finally
      DownloadPage.Hide;
    end;
  end;
end;
