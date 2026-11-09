unit SYNC_PhotoShot_PreparedStore;

// 事前レンダリングで得た「撮影前入力」だけを保持するスレッドセーフな写真ストア。
// ホスト最終合成画像を使用せず、要求 token・時刻・対象・編集世代を照合して確定する。

interface

uses
  System.SyncObjs, System.Generics.Collections,
  Winapi.GDIPOBJ, SYNC_PhotoShot_Timeline;

type
  TPhotoShotPreparedStore = class
  private type
    TPreparedPhoto = class
    public
      SceneID, AbsoluteFrame, RelativeFrame: Integer;
      ObjectID, EffectID: Int64;
      Token: NativeUInt;
      Revision: UInt64;
      Image: TGPBitmap;
      Settings: TPhotoShotSettings;
      destructor Destroy; override;
    end;
  private
    FLock: TCriticalSection;
    FReady: TObjectList<TPreparedPhoto>;
    FPending: TPreparedPhoto;
    FNextToken: NativeUInt;
    FRevision: UInt64;
    FStatus: string;
    function FindReady(SceneID: Integer; ObjectID, EffectID: Int64): Integer;
  public
    // GDI+ は呼出側で開始済みであること。保存画像は本クラスが所有する。
    constructor Create;
    // 破棄前に呼出側で新規 API 呼出しと進行中 callback を停止・終了させること。
    // 任意のメソッド実行中に本オブジェクト自体を Free することはできない。
    destructor Destroy; override;
    // pending はストア内で一つ。使用中、不正時刻、token枯渇時は 0 を返す。
    // 成功時は対象の旧写真を無効化する。token はストアの生存中に再利用しない。
    function BeginRequest(SceneID: Integer; ObjectID, EffectID: Int64;
      AbsoluteFrame, RelativeFrame: Integer): NativeUInt;
    // 要求 token を host opaque parameter 経由で引き継ぐ。全識別子と両時刻を照合。
    // Input は借用し、この呼出し中に変更/破棄しないこと。成功時だけ clone を保持。
    // 同要求の2回目の Capture は拒否。設定は値コピーし、以後変更しない。
    function Capture(Token: NativeUInt; SceneID: Integer; ObjectID, EffectID: Int64;
      AbsoluteFrame, RelativeFrame: Integer; Input: TGPBitmap;
      const Settings: TPhotoShotSettings): Boolean;
    // host成功・capture済み・世代一致の場合だけ Ready へ移す。1回で要求を消費する。
    // 古い/不一致 token は現在の要求に影響しない。
    function CompleteRequest(Token: NativeUInt; HostSucceeded: Boolean): Boolean;
    // caller-owned clone または nil。成功時だけ撮影時の設定を返す。
    // 時間変更後の古い写真を返さないため RelativeShutter の一致を必須とする。
    function CopyPrepared(SceneID: Integer; ObjectID, EffectID: Int64;
      RelativeShutter: Integer; out CapturedSettings: TPhotoShotSettings): TGPBitmap;
    // 編集・scene/load/clear ごとに全写真と pending を破棄し、遅延結果を無効化。
    procedure InvalidateAll;
    // effect の破棄時に、その effect の全 scene/object の写真と pending を破棄。
    procedure RemoveEffect(EffectID: Int64);
    // 状態文字列と token はロック内で取得したスナップショット。
    function GetStatus: string;
    function PendingToken: NativeUInt;
  end;

implementation

uses
  System.SysUtils, System.Math, Winapi.GDIPAPI;

function CloneBitmap(Input: TGPBitmap): TGPBitmap;
var
  W, H: Integer;
begin
  Result := nil;
  if Input = nil then Exit;
  W := Input.GetWidth;
  H := Input.GetHeight;
  if (W <= 0) or (H <= 0) or (Int64(W) * H > 33554432) then Exit;
  Result := Input.Clone(0, 0, W, H, PixelFormat32bppARGB);
  if (Result <> nil) and (Result.GetLastStatus <> Ok) then FreeAndNil(Result);
end;

destructor TPhotoShotPreparedStore.TPreparedPhoto.Destroy;
begin
  Image.Free;
  inherited Destroy;
end;

constructor TPhotoShotPreparedStore.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FReady := TObjectList<TPreparedPhoto>.Create(True);
  FStatus := '写真未準備';
end;

destructor TPhotoShotPreparedStore.Destroy;
begin
  FPending.Free;
  FReady.Free;
  FLock.Free;
  inherited Destroy;
end;

function TPhotoShotPreparedStore.FindReady(SceneID: Integer;
  ObjectID, EffectID: Int64): Integer;
var
  I: Integer;
begin
  // 内部専用。呼出元は FLock を保持する。
  for I := 0 to FReady.Count - 1 do
    if (FReady[I].SceneID = SceneID) and (FReady[I].ObjectID = ObjectID) and
      (FReady[I].EffectID = EffectID) then Exit(I);
  Result := -1;
end;

function TPhotoShotPreparedStore.BeginRequest(SceneID: Integer;
  ObjectID, EffectID: Int64; AbsoluteFrame, RelativeFrame: Integer): NativeUInt;
var
  I: Integer;
begin
  Result := 0;
  if (AbsoluteFrame < 0) or (RelativeFrame < 0) then Exit;
  FLock.Acquire;
  try
    if (FPending <> nil) or (FNextToken = High(NativeUInt)) then Exit;
    Inc(FNextToken);
    FPending := TPreparedPhoto.Create;
    FPending.Token := FNextToken;
    FPending.Revision := FRevision;
    FPending.SceneID := SceneID;
    FPending.ObjectID := ObjectID;
    FPending.EffectID := EffectID;
    FPending.AbsoluteFrame := AbsoluteFrame;
    FPending.RelativeFrame := RelativeFrame;
    I := FindReady(SceneID, ObjectID, EffectID);
    if I >= 0 then FReady.Delete(I);
    FStatus := '写真準備中';
    Result := FPending.Token;
  finally
    FLock.Release;
  end;
end;

function TPhotoShotPreparedStore.Capture(Token: NativeUInt; SceneID: Integer;
  ObjectID, EffectID: Int64; AbsoluteFrame, RelativeFrame: Integer;
  Input: TGPBitmap; const Settings: TPhotoShotSettings): Boolean;
var
  Shutter: Int64;
begin
  Result := False;
  if (Token = 0) or (Input = nil) then Exit;
  Shutter := Int64(Max(0, Settings.EnterFrames)) + Max(0, Settings.WaitFrames);
  if Shutter <> RelativeFrame then Exit;
  FLock.Acquire;
  try
    if (FPending = nil) or (FPending.Token <> Token) or
      (FPending.Revision <> FRevision) or (FPending.Image <> nil) or
      (FPending.SceneID <> SceneID) or (FPending.ObjectID <> ObjectID) or
      (FPending.EffectID <> EffectID) or (FPending.AbsoluteFrame <> AbsoluteFrame) or
      (FPending.RelativeFrame <> RelativeFrame) then Exit;
    FPending.Image := CloneBitmap(Input);
    if FPending.Image = nil then Exit;
    FPending.Settings := Settings;
    Result := True;
  finally
    FLock.Release;
  end;
end;

function TPhotoShotPreparedStore.CompleteRequest(Token: NativeUInt;
  HostSucceeded: Boolean): Boolean;
var
  Photo: TPreparedPhoto;
begin
  Result := False;
  if Token = 0 then Exit;
  FLock.Acquire;
  try
    if (FPending = nil) or (FPending.Token <> Token) then Exit;
    Photo := FPending;
    FPending := nil;
    if HostSucceeded and (Photo.Revision = FRevision) and (Photo.Image <> nil) then
    begin
      FReady.Add(Photo);
      FStatus := '写真準備済み';
      Result := True;
    end
    else
    begin
      Photo.Free;
      FStatus := '写真準備失敗';
    end;
  finally
    FLock.Release;
  end;
end;

function TPhotoShotPreparedStore.CopyPrepared(SceneID: Integer;
  ObjectID, EffectID: Int64; RelativeShutter: Integer;
  out CapturedSettings: TPhotoShotSettings): TGPBitmap;
var
  I: Integer;
begin
  Result := nil;
  CapturedSettings := Default(TPhotoShotSettings);
  FLock.Acquire;
  try
    I := FindReady(SceneID, ObjectID, EffectID);
    if (I < 0) or (FReady[I].RelativeFrame <> RelativeShutter) or
      (FReady[I].Revision <> FRevision) then Exit;
    Result := CloneBitmap(FReady[I].Image);
    if Result <> nil then CapturedSettings := FReady[I].Settings;
  finally
    FLock.Release;
  end;
end;

procedure TPhotoShotPreparedStore.InvalidateAll;
begin
  FLock.Acquire;
  try
    // token は単調増加を維持するため、世代周回でも旧 callback は一致しない。
    if FRevision = High(UInt64) then FRevision := 0 else Inc(FRevision);
    FReady.Clear;
    FreeAndNil(FPending);
    FStatus := '編集により写真未準備';
  finally
    FLock.Release;
  end;
end;

procedure TPhotoShotPreparedStore.RemoveEffect(EffectID: Int64);
var
  I: Integer;
begin
  FLock.Acquire;
  try
    for I := FReady.Count - 1 downto 0 do
      if FReady[I].EffectID = EffectID then FReady.Delete(I);
    if (FPending <> nil) and (FPending.EffectID = EffectID) then
      FreeAndNil(FPending);
    FStatus := '対象を破棄';
  finally
    FLock.Release;
  end;
end;

function TPhotoShotPreparedStore.GetStatus: string;
begin
  FLock.Acquire;
  try
    Result := FStatus;
  finally
    FLock.Release;
  end;
end;

function TPhotoShotPreparedStore.PendingToken: NativeUInt;
begin
  FLock.Acquire;
  try
    if FPending = nil then Result := 0 else Result := FPending.Token;
  finally
    FLock.Release;
  end;
end;

end.
