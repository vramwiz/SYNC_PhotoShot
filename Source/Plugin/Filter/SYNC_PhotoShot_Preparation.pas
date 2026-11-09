unit SYNC_PhotoShot_Preparation;

// 通常 auf2 のボタンで撮影時刻へ移動し、次の正規入力描画を明示的に採取する。
// HostApp / 追加プラグイン / 任意時刻レンダリング要求は使用しない。
// 自動編集通知がないため編集後は再準備が必要。準備前のシーク順に写真を依存させない。
interface

uses
  AviUtl2FilterTypes, Winapi.GDIPOBJ, SYNC_PhotoShot_Timeline;

procedure InitializePhotoShotPreparation;
procedure FinalizePhotoShotPreparation;
procedure RegisterPhotoShotPreparationButtons;
function InterceptPhotoShotInput(Video: PFILTER_PROC_VIDEO; Input: TGPBitmap;
  const Settings: TPhotoShotSettings): Boolean;
function CopyPreparedPhotoShot(Video: PFILTER_PROC_VIDEO; ShutterFrame: Integer;
  out CapturedSettings: TPhotoShotSettings): TGPBitmap;
procedure RemovePreparedPhotoShot(EffectID: Int64);
// 単体テスト用。DLL の追加 export は不要。
procedure PhotoShotSetPreparationSilent(Value: Byte); cdecl;
function PhotoShotPreparationState: Integer; cdecl;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Math,
  System.Generics.Collections, Winapi.Windows, Winapi.Messages, Winapi.GDIPAPI,
  PluginFilterTable, SYNC_PhotoShot_Parameters, SYNC_PhotoShot_PreparedStore,
  SYNC_PhotoShot_HostAPI;

const
  WM_NOTIFY = WM_APP + 443;
  PENDING_TIMEOUT_MS = 30000;
  // SDK v2.1.15 filter2.h: object.effect_layer=96, origin_frame=100。
  OBJECT_ORIGIN_FRAME_OFFSET = 100;

type
  TSetCursorLayerFrame = procedure(Layer, Frame: Integer); cdecl;
  TPhotoIdentity = record
    Scene, Layer, StartFrame, EndFrame, RelativeFrame, AbsoluteFrame: Integer;
    SceneWidth, SceneHeight, SourceWidth, SourceHeight: Integer;
    ObjectID, EffectID: Int64;
  end;

  TPreparation = class
  private
    FWindow: HWND;
    FStore: TPhotoShotPreparedStore;
    FLock: TCriticalSection;
    FReady: TDictionary<string,TPhotoIdentity>;
    FNotifications: TStringList;
    FGdiToken: ULONG_PTR;
    FActive: NativeUInt;
    FDeadline: UInt64;
    FPending: TPhotoIdentity;
    FSilent, FClosing: Boolean;
    FState: Integer;
    procedure WndProc(var Msg: TMessage);
    procedure Notify(const Text: string; Failed: Boolean);
    procedure CancelLocked;
    procedure ExpireLocked;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Queue(Edit: PPhotoShotEditSection; Obj: OBJECT_HANDLE; Effect: PWideChar);
    procedure Invalidate;
    procedure Remove(EffectID: Int64);
    procedure Capture(Video: PFILTER_PROC_VIDEO; Input: TGPBitmap;
      const Settings: TPhotoShotSettings);
    function CopyPhoto(Video: PFILTER_PROC_VIDEO; ShutterFrame: Integer;
      out Settings: TPhotoShotSettings): TGPBitmap;
    procedure Status(Edit: PPhotoShotEditSection; Obj: OBJECT_HANDLE; Effect: PWideChar);
  end;

var
  Preparation: TPreparation;
  PrepareButton, StatusButton, ClearButton: TFILTER_ITEM_BUTTON;
  PreparationGroup: TFILTER_ITEM_GROUP;

function IdentityKey(Scene: Integer; ObjectID,EffectID: Int64): string;
begin
  Result:=IntToStr(Scene)+':'+IntToStr(ObjectID)+':'+IntToStr(EffectID);
end;

constructor TPreparation.Create;
var Input: TGdiplusStartupInput;
begin
  inherited Create;
  FLock:=TCriticalSection.Create;
  FNotifications:=TStringList.Create;
  FReady:=TDictionary<string,TPhotoIdentity>.Create;
  Input:=Default(TGdiplusStartupInput); Input.GdiplusVersion:=1;
  if GdiplusStartup(FGdiToken,@Input,nil)<>Ok then
    raise Exception.Create('PhotoShot preparation GDI+ initialization failed');
  FStore:=TPhotoShotPreparedStore.Create;
  FWindow:=AllocateHWnd(WndProc);
  SetTimer(FWindow,1,1000,nil);
end;

destructor TPreparation.Destroy;
begin
  // ホストがフィルターcallbackを終了した後に UninitializePlugin から呼ぶ。
  // 本モジュールは独自の非同期ホストタスクを作らず、SDK 待機 API も呼ばない。
  FClosing:=True;
  if FWindow<>0 then begin KillTimer(FWindow,1); DeallocateHWnd(FWindow); end;
  FStore.Free; FReady.Free; FNotifications.Free;
  if FGdiToken<>0 then GdiplusShutdown(FGdiToken);
  FLock.Free;
  inherited Destroy;
end;

procedure TPreparation.Notify(const Text: string; Failed: Boolean);
begin
  OutputDebugString(PChar('PhotoShot: '+Text));
  FLock.Acquire;
  try
    if FSilent or FClosing then Exit;
    if FNotifications.Count<10 then FNotifications.Add(IntToStr(Ord(Failed))+Text);
  finally FLock.Release; end;
  PostMessage(FWindow,WM_NOTIFY,0,0);
end;

procedure TPreparation.CancelLocked;
begin
  // 呼出側が FLock を保持。常に同じ順序（Preparation→Store）でロックする。
  if FActive<>0 then FStore.CompleteRequest(FActive,False);
  FActive:=0; FDeadline:=0;
end;

procedure TPreparation.ExpireLocked;
begin
  if (FActive<>0) and (GetTickCount64>=FDeadline) then
  begin CancelLocked; FState:=3; end;
end;

procedure TPreparation.Invalidate;
begin
  FLock.Acquire;
  try
    CancelLocked; FStore.InvalidateAll; FReady.Clear; FState:=0;
  finally FLock.Release; end;
end;

procedure TPreparation.Remove(EffectID: Int64);
var Pair: TPair<string,TPhotoIdentity>; Keys: TList<string>; Key: string;
begin
  FLock.Acquire;
  try
    if (FActive<>0) and (FPending.EffectID=EffectID) then
    begin CancelLocked; FState:=0; end;
    FStore.RemoveEffect(EffectID);
    Keys:=TList<string>.Create;
    try
      for Pair in FReady do if Pair.Value.EffectID=EffectID then Keys.Add(Pair.Key);
      for Key in Keys do FReady.Remove(Key);
    finally Keys.Free; end;
  finally FLock.Release; end;
end;

procedure TPreparation.Queue(Edit: PPhotoShotEditSection; Obj: OBJECT_HANDLE; Effect: PWideChar);
var M: TPhotoIdentity; Range: TOBJECT_LAYER_FRAME; E: EFFECT_HANDLE;
  S: TPhotoShotSettings; Relative,Absolute: Int64; Token: NativeUInt;
begin
  // 再要求は旧 pending を必ず解除。識別できた対象の旧写真も採用しない。
  FLock.Acquire;
  try CancelLocked; FState:=0; finally FLock.Release; end;
  if (Edit=nil) or (Obj=nil) or (Effect=nil) or (Edit^.Base.Info=nil) or
    not Assigned(Edit^.FindEffect) or not Assigned(Edit^.GetObjectID) or
    not Assigned(Edit^.GetEffectID) or not Assigned(Edit^.Base.GetObjectLayerFrame) or
    (Edit^.Base.SetCursorLayerFrame=nil) then
    raise Exception.Create('写真準備に必要な編集 API を取得できません。');
  M:=Default(TPhotoIdentity);
  E:=Edit^.FindEffect(Obj,Effect);
  if E=nil then raise Exception.Create('写真撮影エフェクトを識別できません。');
  M.ObjectID:=Edit^.GetObjectID(Obj); M.EffectID:=Edit^.GetEffectID(E);
  M.Scene:=PEDIT_INFO(Edit^.Base.Info)^.SceneID;
  M.SceneWidth:=PEDIT_INFO(Edit^.Base.Info)^.Width;
  M.SceneHeight:=PEDIT_INFO(Edit^.Base.Info)^.Height;
  FLock.Acquire;
  try
    FStore.RemoveEffect(M.EffectID);
    FReady.Remove(IdentityKey(M.Scene,M.ObjectID,M.EffectID));
  finally FLock.Release; end;
  Range:=Edit^.Base.GetObjectLayerFrame(Obj);
  S:=ReadPhotoShotParameters;
  Relative:=Int64(Max(0,S.EnterFrames))+Max(0,S.WaitFrames);
  Absolute:=Int64(Range.StartFrame)+Relative;
  if (M.ObjectID=0) or (M.EffectID=0) or (Relative>High(Integer)) or
    (Absolute<0) or (Absolute<Range.StartFrame) or (Absolute>Range.EndFrame) or
    (Absolute>High(Integer)) then
    raise Exception.Create('撮影時刻が対象範囲外です。オブジェクトの長さ・時間設定を確認してください。');
  M.Layer:=Range.Layer; M.StartFrame:=Range.StartFrame; M.EndFrame:=Range.EndFrame;
  M.RelativeFrame:=Integer(Relative); M.AbsoluteFrame:=Integer(Absolute);
  FLock.Acquire;
  try
    Token:=FStore.BeginRequest(M.Scene,M.ObjectID,M.EffectID,M.AbsoluteFrame,M.RelativeFrame);
    if Token=0 then raise Exception.Create('写真準備要求を作成できません。');
    FPending:=M; FActive:=Token; FDeadline:=GetTickCount64+PENDING_TIMEOUT_MS; FState:=1;
  finally FLock.Release; end;
  try
    // 正規 EDIT_SECTION API。ロックを保持せず移動し、再描画の完了は待たない。
    TSetCursorLayerFrame(Edit^.Base.SetCursorLayerFrame)(M.Layer,M.AbsoluteFrame);
  except
    FLock.Acquire;
    try if FActive=Token then begin CancelLocked; FState:=3; end; finally FLock.Release; end;
    raise;
  end;
  // カーソル移動が同期描画を起こした場合は、確定済みの成功通知だけを残す。
  FLock.Acquire;
  try
    if (FActive=Token) and (FState=1) then
      Notify('撮影フレームへ移動しました。未完了の場合は撮影フレームへ移動／再描画して準備してください。'+
        #13#10+'30秒以内の通常入力描画で確定します。準備中は書き出さず、編集後は再準備してください。',False);
  finally FLock.Release; end;
end;

procedure TPreparation.Capture(Video: PFILTER_PROC_VIDEO; Input: TGPBitmap;
  const Settings: TPhotoShotSettings);
var Absolute: Int64; M: TPhotoIdentity; Success: Boolean; EditInfo: PEDIT_INFO;
begin
  if (Video=nil) or (Video^.Scene=nil) or (Video^.Object_=nil) or
    (Input=nil) or (Video^.Edit=nil) or (Video^.Edit^.Info=nil) then Exit;
  // シーン参照、モーションブラー等の補助描画を写真にしない。
  if ((Video^.Scene^.Flag and 1)<>0) or (Video^.Scene^.ID<>Video^.Scene^.OriginID) then Exit;
  Absolute:=Int64(Video^.Object_^.FrameS)+Video^.Object_^.Frame;
  if (Absolute<0) or (Absolute>High(Integer)) or
    (PInteger(NativeUInt(Video^.Object_)+OBJECT_ORIGIN_FRAME_OFFSET)^<>Absolute) then Exit;
  EditInfo:=PEDIT_INFO(Video^.Edit^.Info);
  FLock.Acquire;
  try
    ExpireLocked;
    if FActive=0 then Exit;
    M:=FPending;
    if (EditInfo^.SceneID<>M.Scene) or (EditInfo^.Frame<>M.AbsoluteFrame) then Exit;
    if (Video^.Scene^.ID<>M.Scene) or (Video^.Object_^.ID<>M.ObjectID) or
      (Video^.Object_^.EffectID<>M.EffectID) or (Absolute<>M.AbsoluteFrame) or
      (Video^.Object_^.Frame<>M.RelativeFrame) then Exit;
    if (Video^.Object_^.FrameS<>M.StartFrame) or (Video^.Object_^.FrameE<>M.EndFrame) or
      (Video^.Object_^.EffectLayer<>M.Layer) or (Video^.Scene^.Width<>M.SceneWidth) or
      (Video^.Scene^.Height<>M.SceneHeight) or
      (Integer(Input.GetWidth)<>Video^.Object_^.Width) or
      (Integer(Input.GetHeight)<>Video^.Object_^.Height) then
    begin CancelLocked; FState:=3; Exit; end;
    if not FStore.Capture(FActive,M.Scene,M.ObjectID,M.EffectID,
      M.AbsoluteFrame,M.RelativeFrame,Input,Settings) then
    begin CancelLocked; FState:=3; Exit; end;
    Success:=FStore.CompleteRequest(FActive,True);
    FActive:=0; FDeadline:=0;
    if Success then
    begin
      FNotifications.Clear;
      M.SourceWidth:=Input.GetWidth; M.SourceHeight:=Input.GetHeight;
      FReady.AddOrSetValue(IdentityKey(M.Scene,M.ObjectID,M.EffectID),M); FState:=2;
    end
    else FState:=3;
  finally FLock.Release; end;
  if Success then Notify('このエフェクトの写真を準備しました。編集後は再準備してください。',False);
end;

function TPreparation.CopyPhoto(Video: PFILTER_PROC_VIDEO; ShutterFrame: Integer;
  out Settings: TPhotoShotSettings): TGPBitmap;
var M:TPhotoIdentity; Key:string;
begin
  Result:=nil; Settings:=Default(TPhotoShotSettings);
  if (Video=nil) or (Video^.Scene=nil) or (Video^.Object_=nil) then Exit;
  Key:=IdentityKey(Video^.Scene^.ID,Video^.Object_^.ID,Video^.Object_^.EffectID);
  FLock.Acquire;
  try
    ExpireLocked;
    if not FReady.TryGetValue(Key,M) then Exit;
    if (ShutterFrame<>M.RelativeFrame) or (Video^.Object_^.FrameS<>M.StartFrame) or
      (Video^.Object_^.FrameE<>M.EndFrame) or (Video^.Object_^.EffectLayer<>M.Layer) or
      (Video^.Scene^.Width<>M.SceneWidth) or (Video^.Scene^.Height<>M.SceneHeight) or
      (Video^.Object_^.Width<>M.SourceWidth) or (Video^.Object_^.Height<>M.SourceHeight) then
    begin
      FReady.Remove(Key); FStore.RemoveEffect(M.EffectID); FState:=0; Exit;
    end;
    Result:=FStore.CopyPrepared(M.Scene,M.ObjectID,M.EffectID,ShutterFrame,Settings);
    if (Result<>nil) and ((Integer(Result.GetWidth)<>M.SourceWidth) or
      (Integer(Result.GetHeight)<>M.SourceHeight)) then
    begin FreeAndNil(Result); FReady.Remove(Key); FStore.RemoveEffect(M.EffectID); end;
  finally FLock.Release; end;
end;

procedure TPreparation.Status(Edit:PPhotoShotEditSection; Obj:OBJECT_HANDLE; Effect:PWideChar);
var E:EFFECT_HANDLE; Key,Text:string; M:TPhotoIdentity; Range:TOBJECT_LAYER_FRAME;
  S:TPhotoShotSettings; Relative:Int64; Info:PEDIT_INFO;
begin
  if (Edit=nil) or (Obj=nil) or (Effect=nil) or (Edit^.Base.Info=nil) or
    not Assigned(Edit^.FindEffect) or not Assigned(Edit^.GetObjectID) or
    not Assigned(Edit^.GetEffectID) or not Assigned(Edit^.Base.GetObjectLayerFrame) then Exit;
  E:=Edit^.FindEffect(Obj,Effect); if E=nil then Exit;
  Key:=IdentityKey(PEDIT_INFO(Edit^.Base.Info)^.SceneID,Edit^.GetObjectID(Obj),Edit^.GetEffectID(E));
  Range:=Edit^.Base.GetObjectLayerFrame(Obj);
  S:=ReadPhotoShotParameters; Relative:=Int64(Max(0,S.EnterFrames))+Max(0,S.WaitFrames);
  Info:=PEDIT_INFO(Edit^.Base.Info);
  FLock.Acquire;
  try
    ExpireLocked;
    if FReady.TryGetValue(Key,M) and (M.StartFrame=Range.StartFrame) and
      (M.EndFrame=Range.EndFrame) and (M.Layer=Range.Layer) and
      (Int64(M.RelativeFrame)=Relative) and (M.SceneWidth=Info^.Width) and
      (M.SceneHeight=Info^.Height) then
      Text:='このエフェクトは写真準備済みです。'
    else if (FActive<>0) and (FPending.EffectID=Edit^.GetEffectID(E)) then
      Text:='撮影フレームへ移動／再描画して準備してください。30秒で待機を解除します。'
    else Text:='このエフェクトは未準備です。「写真を準備」を押してください。';
  finally FLock.Release; end;
  Notify(Text+#13#10+'編集の自動検出はできません。元映像・設定の編集後は必ず再準備してください。'+
    #13#10+'準備が完了してからシーク・書き出しを行ってください。写真はプロジェクトへ保存されません。',False);
end;

procedure TPreparation.WndProc(var Msg:TMessage);
var Text:string; Flags:Cardinal;
begin
  try
    if Msg.Msg=WM_TIMER then
    begin FLock.Acquire; try ExpireLocked; finally FLock.Release; end; Exit; end;
    if Msg.Msg=WM_NOTIFY then
    begin
      Text:='';
      FLock.Acquire;
      try
        if FNotifications.Count>0 then begin Text:=FNotifications[0]; FNotifications.Delete(0); end;
      finally FLock.Release; end;
      if (Text<>'') and not FClosing and not FSilent then
      begin
        Flags:=MB_OK or MB_ICONINFORMATION;
        if Text[1]='1' then Flags:=MB_OK or MB_ICONWARNING;
        Delete(Text,1,1); MessageBox(0,PChar(Text),'写真撮影',Flags);
      end;
      Exit;
    end;
    Msg.Result:=DefWindowProc(FWindow,Msg.Msg,Msg.WParam,Msg.LParam);
  except
    on E:Exception do OutputDebugString(PChar('PhotoShot notification: '+E.Message));
  end;
end;

procedure PrepareClick(Edit:PPhotoShotEditSection; Obj:OBJECT_HANDLE; Effect,Item:PWideChar); cdecl;
begin
  try if Preparation<>nil then Preparation.Queue(Edit,Obj,Effect);
  except on E:Exception do if Preparation<>nil then
    begin
      Preparation.FLock.Acquire;
      try Preparation.CancelLocked; Preparation.FState:=3; finally Preparation.FLock.Release; end;
      Preparation.Notify(E.Message,True);
    end;
  end;
end;

procedure StatusClick(Edit:PPhotoShotEditSection; Obj:OBJECT_HANDLE; Effect,Item:PWideChar); cdecl;
begin
  try if Preparation<>nil then Preparation.Status(Edit,Obj,Effect);
  except on E:Exception do if Preparation<>nil then Preparation.Notify(E.Message,True); end;
end;

procedure ClearClick(Edit:PPhotoShotEditSection; Obj:OBJECT_HANDLE; Effect,Item:PWideChar); cdecl;
begin
  try if Preparation<>nil then
    begin Preparation.Invalidate; Preparation.Notify('全エフェクトの写真と準備待ちを破棄しました。',False); end;
  except on E:Exception do if Preparation<>nil then Preparation.Notify(E.Message,True); end;
end;

procedure InitializePhotoShotPreparation;
begin
  if Preparation=nil then Preparation:=TPreparation.Create;
end;

procedure FinalizePhotoShotPreparation;
begin
  FreeAndNil(Preparation);
end;

procedure RegisterPhotoShotPreparationButtons;
begin
  AddGroup(PreparationGroup,'写真準備',1);
  AddButton(PrepareButton,'写真を準備',nil); PrepareButton.Callback2:=@PrepareClick;
  AddButton(StatusButton,'準備状態',nil); StatusButton.Callback2:=@StatusClick;
  AddButton(ClearButton,'写真を破棄（全て）',nil); ClearButton.Callback2:=@ClearClick;
end;

function InterceptPhotoShotInput(Video:PFILTER_PROC_VIDEO; Input:TGPBitmap;
  const Settings:TPhotoShotSettings):Boolean;
begin
  // 採取成功後も通常のフィルター描画を続け、同フレームから準備済み写真を使用する。
  Result:=False;
  if Preparation<>nil then Preparation.Capture(Video,Input,Settings);
end;

function CopyPreparedPhotoShot(Video:PFILTER_PROC_VIDEO; ShutterFrame:Integer;
  out CapturedSettings:TPhotoShotSettings):TGPBitmap;
begin
  Result:=nil; CapturedSettings:=Default(TPhotoShotSettings);
  if Preparation<>nil then Result:=Preparation.CopyPhoto(Video,ShutterFrame,CapturedSettings);
end;

procedure RemovePreparedPhotoShot(EffectID:Int64);
begin
  if Preparation<>nil then Preparation.Remove(EffectID);
end;

procedure PhotoShotSetPreparationSilent(Value:Byte); cdecl;
begin
  if Preparation<>nil then
  begin Preparation.FLock.Acquire; try Preparation.FSilent:=Value<>0; finally Preparation.FLock.Release; end; end;
end;

function PhotoShotPreparationState:Integer; cdecl;
begin
  Result:=0;
  if Preparation<>nil then
  begin
    Preparation.FLock.Acquire;
    try Preparation.ExpireLocked; Result:=Preparation.FState; finally Preparation.FLock.Release; end;
  end;
end;

end.
