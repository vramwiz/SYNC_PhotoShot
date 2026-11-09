unit SYNC_PhotoShot_FilterPlugin;

// 標準パラメータ、現在フレームの取得、カメラ演出の描画を接続する。
// 写真は明示的な事前準備で採取した入力だけを使用し、任意シークの順に依存しない。
interface

uses
  AviUtl2FilterTypes;

// 入力なし。DLL 所有のテーブルを返す。初回のみ項目を登録し、呼出側は解放しない。
function GetPhotoShotFilterTable: PFILTER_PLUGIN_TABLE;

// コピー元と同じ DLL 境界から呼ぶ起動・終了処理。資源は本体側で所有する。
function StartPhotoShotGraphics: Boolean;
procedure SetPhotoShotHostVersion(Version: Cardinal);
procedure StopPhotoShotGraphics;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.SyncObjs, Winapi.Windows, Winapi.GDIPAPI,
  Winapi.GDIPOBJ, PluginFilterTable, SYNC_PhotoShot_Parameters,
  SYNC_PhotoShot_Timeline, SYNC_PhotoShot_Capture, SYNC_PhotoShot_Renderer,
  SYNC_PhotoShot_Audio, SYNC_PhotoShot_Preparation;

type
  TPhotoShotSession = class
  private
    FLock: TCriticalSection;
    FRenderer: TPhotoShotRenderer;
    FOutput: TArray<TPIXEL_RGBA>;
    procedure WriteImage(Video: PFILTER_PROC_VIDEO; Image: TGPBitmap);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Render(Video: PFILTER_PROC_VIDEO);
  end;

var
  PluginTableInitialized: Boolean;

// 初期化失敗の原因をユーザー用のローカルログへ残す。ログ失敗でホストを止めない。
procedure TraceInitialization(const Text: string);
var Path: string;
begin
  try
    Path := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) + 'SYNC_PhotoShot';
    ForceDirectories(Path);
    TFile.AppendAllText(Path + '\initialize.log',
      FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' ' + Text + sLineBreak,
      TEncoding.UTF8);
  except
    // 診断ログはプラグイン登録の成否へ影響させない。
  end;
end;
// 初期化失敗時の後始末はコピー元と同じく DLL 境界の except から行う。
function StartPhotoShotGraphics: Boolean;
begin
  TraceInitialization('Start');
  try
    InitializePhotoShotPreparation;
    TraceInitialization('Preparation initialized');
    InitializePhotoShotAudio;
    TraceInitialization('Audio initialized');
    Result := True;
  except
    on E: Exception do
    begin
      TraceInitialization('FAILED: ' + E.ClassName + ': ' + E.Message);
      raise;
    end;
  end;
end;

// userdata を使うため、旧本体にはテーブルを渡さない。
procedure SetPhotoShotHostVersion(Version: Cardinal);
begin
  TraceInitialization('HostVersion=' + UIntToStr(Version) + ' Minimum=2011500');
  if Version < 2011500 then
  begin
    TraceInitialization('FAILED: host version is below required API version');
    raise Exception.Create('AviUtl2 2.1.15 以降が必要です。');
  end;
end;

procedure StopPhotoShotGraphics;
begin
  FinalizePhotoShotPreparation;
  ReleasePhotoShotAudio;
end;

constructor TPhotoShotSession.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FRenderer := TPhotoShotRenderer.Create;
end;

destructor TPhotoShotSession.Destroy;
begin
  FRenderer.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TPhotoShotSession.WriteImage(Video: PFILTER_PROC_VIDEO; Image: TGPBitmap);
var
  Data: TBitmapData;
  X, Y, W, H: Integer;
  Source: PByte;
  Target: PPIXEL_RGBA;
begin
  if (Image = nil) or not Assigned(Video^.SetImageData) then Exit;
  W := Image.GetWidth;
  H := Image.GetHeight;
  if (W < 1) or (H < 1) or (Int64(W) * H > 33554432) then Exit;
  Data := Default(TBitmapData);
  // ARGB でロックして GDI+ に PARGB の解除を任せ、ホストの RGBA 順へ戻す。
  if Image.LockBits(MakeRect(0, 0, W, H), ImageLockModeRead,
    PixelFormat32bppARGB, Data) <> Ok then
    raise Exception.Create('Unable to read PhotoShot output bitmap');
  try
    SetLength(FOutput, NativeInt(W) * H);
    for Y := 0 to H - 1 do
    begin
      Source := PByte(NativeInt(Data.Scan0) + NativeInt(Y) * Data.Stride);
      Target := @FOutput[NativeInt(Y) * W];
      for X := 0 to W - 1 do
      begin
        Target^.R := Source[2];
        Target^.G := Source[1];
        Target^.B := Source[0];
        Target^.A := Source[3];
        Inc(Source, 4);
        Inc(Target);
      end;
    end;
  finally
    Image.UnlockBits(Data);
  end;
  Video^.SetImageData(@FOutput[0], W, H);
end;

procedure TPhotoShotSession.Render(Video: PFILTER_PROC_VIDEO);
var
  Current, Snapshot, Output: TGPBitmap;
  Settings, CapturedSettings: TPhotoShotSettings;
  State: TPhotoShotState;
begin
  if Video^.Scene = nil then Exit;
  Settings := ReadPhotoShotParameters(Video^.Scene^.Rate, Video^.Scene^.Scale);
  Current := CapturePhotoShotInput(Video);
  if Current = nil then Exit;
  Snapshot := nil;
  try
    // 明示要求と一致する通常描画入力だけ採取し、そのまま同フレームの演出を続ける。
    if InterceptPhotoShotInput(Video,Current,Settings) then Exit;
    State := EvaluatePhotoShot(Settings,Video^.Object_^.Frame,Current.GetWidth,Current.GetHeight);
    Snapshot := CopyPreparedPhotoShot(Video,State.ShutterFrame,CapturedSettings);
    Output := FRenderer.Render(Current,Snapshot,Settings,Video^.Object_^.Frame,@CapturedSettings);
    WriteImage(Video,Output);
  finally
    Snapshot.Free;
    Current.Free;
  end;
end;

function PhotoShotProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  Session: TPhotoShotSession;
begin
  Result := 1;
  try
    if (Video = nil) or (Video^.Object_ = nil) or (Video^.UserData = nil) or
      not Assigned(Video^.GetImageData) or not Assigned(Video^.SetImageData) then Exit;
    Session := TPhotoShotSession(Video^.UserData);
    Session.FLock.Acquire;
    try
      Session.Render(Video);
    finally
      Session.FLock.Release;
    end;
  except
    on E: Exception do
      // 失敗時はホストの入力映像を保ち、例外を C ABI の境界へ出さない。
      OutputDebugString(PChar('SYNC_PhotoShot: ' + E.Message));
  end;
end;

function PhotoShotCreate(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TPhotoShotSession.Create;
  except
    on E: Exception do OutputDebugString(PChar('SYNC_PhotoShot create: ' + E.Message));
  end;
end;

procedure PhotoShotDestroy(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    RemovePreparedPhotoShot(EffectID);
    TPhotoShotSession(UserData).Free;
  except
    on E: Exception do OutputDebugString(PChar('SYNC_PhotoShot destroy: ' + E.Message));
  end;
end;

function GetPhotoShotFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not PluginTableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or 2 or FILTER_FLAG_FILTER or FILTER_FLAG_USERDATA,
      '写真撮影', 'SYNC', '写真を準備して撮影演出を再現（編集後は再準備）',
      PhotoShotProcVideo, PhotoShotProcAudio);
    RegisterPhotoShotParameters;
    RegisterPhotoShotPreparationButtons;
    GetPluginTable^.Func_Create := PhotoShotCreate;
    GetPluginTable^.Func_Destroy := PhotoShotDestroy;
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
  TraceInitialization('Filter table ready');
end;

end.
