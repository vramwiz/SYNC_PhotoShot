unit SYNC_PhotoShot_Preparation;

// 標準ボタンから編集ロックを抜けた後に事前レンダリングを要求する。
// 完成シーン画像は採用せず、対象フィルター入口が採取した入力だけを確定する。
interface

uses
  AviUtl2FilterTypes, Winapi.GDIPOBJ, SYNC_PhotoShot_Timeline,
  SYNC_PhotoShot_HostAPI;

procedure InitializePhotoShotPreparation;
procedure FinalizePhotoShotPreparation;
procedure RegisterPhotoShotHost(Host: PPhotoShotHostAppTable);
procedure RegisterPhotoShotPreparationButtons;
function InterceptPhotoShotInput(Video: PFILTER_PROC_VIDEO; Input: TGPBitmap;
  const Settings: TPhotoShotSettings): Boolean;
function CopyPreparedPhotoShot(Video: PFILTER_PROC_VIDEO; ShutterFrame: Integer;
  out CapturedSettings: TPhotoShotSettings): TGPBitmap;
procedure RemovePreparedPhotoShot(EffectID: Int64);
// 自動検証時だけ通知ダイアログを抑止する。画像の成功条件は変えない。
procedure PhotoShotSetPreparationSilent(Value: Byte); cdecl;
// 0=未準備/無効、1=要求中、2=直近成功、3=失敗。実機検証で使用可能。
function PhotoShotPreparationState: Integer; cdecl;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Math,
  Winapi.Windows, Winapi.Messages, Winapi.GDIPAPI, PluginFilterTable,
  SYNC_PhotoShot_Parameters, SYNC_PhotoShot_PreparedStore;

const
  WM_PREPARE = WM_APP + 441;
  WM_FINISHED = WM_APP + 442;
  WM_NOTIFY = WM_APP + 443;

type
  TPreparation = class
  private
    FWindow: HWND;
    FHandle: PPhotoShotEditHandle;
    FStore: TPhotoShotPreparedStore;
    FLock: TCriticalSection;
    FNotifications: TStringList;
    FToken: ULONG_PTR;
    FActive: NativeUInt;
    FQueued, FSilent, FClosing: Boolean;
    FState: Integer;
    FGeneration, FSubmittedGeneration: Int64;
    FScene, FLayer, FStart, FEnd, FRelative, FAbsolute: Integer;
    FObject, FEffect: Int64;
    FEffectName: string;
    FValid: Boolean;
    procedure WndProc(var Msg: TMessage);
    procedure StartRequest;
    procedure Notify(const Text: string; Failed: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Queue(Edit: PPhotoShotEditSection; Obj: OBJECT_HANDLE;
      Effect: PWideChar);
    procedure Invalidate;
  end;

var
  Preparation: TPreparation;
  PrepareButton, StatusButton: TFILTER_ITEM_BUTTON;
  PreparationGroup: TFILTER_ITEM_GROUP;

procedure HostChanged(Param: Pointer); cdecl;
begin
  try
    if Preparation <> nil then Preparation.Invalidate;
  except
    // ホストイベントスレッドへ例外を伝播しない。
  end;
end;

procedure ProjectLoaded(Project: Pointer); cdecl;
begin
  HostChanged(nil);
end;

procedure CacheCleared(Edit: PPhotoShotEditSection); cdecl;
begin
  HostChanged(nil);
end;

procedure RenderFinished(Param: Pointer; Frame: Integer; Buffer: Pointer;
  Width, Height, Pitch: Integer); cdecl;
var
  P: TPreparation;
  Success: Boolean;
begin
  P := Preparation;
  if P = nil then Exit;
  try
    Success := P.FStore.CompleteRequest(NativeUInt(Param),
      (Buffer <> nil) and (Width > 0) and (Height > 0) and
      (Pitch >= Width * 4));
    // 完成画像の buffer は使わない。対象入力の Capture 成功が必須。
    PostMessage(P.FWindow,WM_FINISHED,WPARAM(Param),LPARAM(Ord(Success)));
  except
    PostMessage(P.FWindow,WM_FINISHED,WPARAM(Param),0);
  end;
end;

procedure ValidateTarget(Param: Pointer; Edit: PPhotoShotEditSection); cdecl;
var P: TPreparation; Obj, Effect: Pointer; Range: TOBJECT_LAYER_FRAME;
begin
  P := TPreparation(Param);
  P.FValid := False;
  if (Edit = nil) or not Assigned(Edit^.Base.FindObject) or
    not Assigned(Edit^.FindEffect) or not Assigned(Edit^.GetObjectID) or
    not Assigned(Edit^.GetEffectID) or not Assigned(Edit^.Base.GetObjectLayerFrame) then Exit;
  Obj := Edit^.Base.FindObject(P.FLayer,P.FStart);
  if (Obj = nil) or (Edit^.GetObjectID(Obj) <> P.FObject) then Exit;
  Range := Edit^.Base.GetObjectLayerFrame(Obj);
  if (Range.StartFrame <> P.FStart) or (Range.EndFrame <> P.FEnd) then Exit;
  Effect := Edit^.FindEffect(Obj,PWideChar(P.FEffectName));
  P.FValid := (Effect <> nil) and (Edit^.GetEffectID(Effect) = P.FEffect);
end;

constructor TPreparation.Create;
var Input: TGdiplusStartupInput;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FNotifications := TStringList.Create;
  Input := Default(TGdiplusStartupInput); Input.GdiplusVersion := 1;
  if GdiplusStartup(FToken,@Input,nil) <> Ok then raise Exception.Create('PhotoShot preparation GDI+ initialization failed');
  FStore := TPhotoShotPreparedStore.Create;
  FWindow := AllocateHWnd(WndProc);
end;

destructor TPreparation.Destroy;
begin
  FClosing := True;
  if FStore <> nil then FStore.InvalidateAll;
  // 終了処理のトップレベルのみ。編集/参照callbackや内部ロックを保持して待たない。
  if (FHandle <> nil) and Assigned(FHandle^.WaitRenderingTask) then
    FHandle^.WaitRenderingTask;
  if FWindow <> 0 then DeallocateHWnd(FWindow);
  FStore.Free;
  if FToken <> 0 then GdiplusShutdown(FToken);
  FNotifications.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TPreparation.Notify(const Text: string; Failed: Boolean);
begin
  OutputDebugString(PChar('SYNC_PhotoShot preparation: '+Text));
  if FSilent or FClosing then Exit;
  // 編集callback内でMessageBoxを開くとメッセージループが再入する。
  // 通知も必ず編集callback終了後へ送り、要求開始と同じくロック外で表示する。
  FLock.Acquire;
  try
    if FNotifications.Count < 10 then
      FNotifications.Add(IntToStr(Ord(Failed))+Text);
  finally FLock.Release; end;
  PostMessage(FWindow,WM_NOTIFY,0,0);
end;

procedure TPreparation.Invalidate;
begin
  FStore.InvalidateAll;
  FLock.Acquire;
  try
    Inc(FGeneration);
    if (FActive = 0) and not FQueued then FState := 0;
  finally FLock.Release; end;
end;

procedure TPreparation.Queue(Edit: PPhotoShotEditSection; Obj: OBJECT_HANDLE;
  Effect: PWideChar);
var Range: TOBJECT_LAYER_FRAME; E: EFFECT_HANDLE; S: TPhotoShotSettings; Total: Int64;
begin
  if (Edit = nil) or (Obj = nil) or (Effect = nil) or
    (Edit^.Base.Info = nil) or not Assigned(Edit^.FindEffect) or
    not Assigned(Edit^.GetObjectID) or not Assigned(Edit^.GetEffectID) or
    not Assigned(Edit^.Base.GetObjectLayerFrame) then
    raise Exception.Create('準備に必要な編集 API を取得できません。');
  if FHandle = nil then raise Exception.Create('.aux2 として読み込んでください。');
  FLock.Acquire;
  try
    if FQueued or (FActive <> 0) then raise Exception.Create('写真の準備中です。完了後に操作してください。');
    Range := Edit^.Base.GetObjectLayerFrame(Obj);
    E := Edit^.FindEffect(Obj,Effect);
    if E = nil then raise Exception.Create('対象の写真撮影エフェクトを識別できません。');
    S := ReadPhotoShotParameters;
    FRelative := Max(0,S.EnterFrames)+Max(0,S.WaitFrames);
    Total := Int64(Range.StartFrame)+FRelative;
    if (Total < Range.StartFrame) or (Total > Range.EndFrame) or (Total > High(Integer)) then
      raise Exception.Create('撮影時刻がオブジェクトの範囲外です。時間または長さを調整してください。');
    FScene := PEDIT_INFO(Edit^.Base.Info)^.SceneID;
    FLayer := Range.Layer; FStart := Range.StartFrame; FEnd := Range.EndFrame;
    FObject := Edit^.GetObjectID(Obj); FEffect := Edit^.GetEffectID(E);
    FEffectName := string(Effect); FAbsolute := Integer(Total);
    if (FObject = 0) or (FEffect = 0) then raise Exception.Create('対象の ID を取得できません。');
    FQueued := True; FState := 1;
    PostMessage(FWindow,WM_PREPARE,0,0);
  finally FLock.Release; end;
end;

procedure TPreparation.StartRequest;
var Info: TEDIT_INFO; Token: NativeUInt; Accepted: Boolean;
begin
  // 開始処理中も busy を維持し、SDK の内部メッセージポンプからの再入を拒否する。
  try
    if FClosing then Exit;
    if (FHandle = nil) or not Assigned(FHandle^.GetEditState) or
      not Assigned(FHandle^.GetEditInfo) or not Assigned(FHandle^.RenderingSceneVideo) or
      not Assigned(FHandle^.CallReadSectionParam) then raise Exception.Create('事前描画 API が利用できません。');
    if FHandle^.GetEditState() <> PHOTOSHOT_EDIT_STATE_EDIT then
      raise Exception.Create('再生・書き出し中は準備できません。停止後に再実行してください。');
    Info := Default(TEDIT_INFO); FHandle^.GetEditInfo(@Info,SizeOf(Info));
    if Info.SceneID <> FScene then raise Exception.Create('シーンが変わりました。もう一度準備してください。');
    FValid := False;
    if (FHandle^.CallReadSectionParam(Self,ValidateTarget) = 0) or not FValid then
      raise Exception.Create('対象が変更・削除されました。もう一度準備してください。');
    Token := FStore.BeginRequest(FScene,FObject,FEffect,FAbsolute,FRelative);
    if Token = 0 then raise Exception.Create('別の写真を準備中です。');
    FLock.Acquire;
    try FActive := Token; FQueued := False; FSubmittedGeneration := FGeneration; finally FLock.Release; end;
    // 参照callbackは既に終了。要求を追加するだけで待たない。
    Accepted := FHandle^.RenderingSceneVideo(FAbsolute,Pointer(Token),RenderFinished) <> 0;
    if not Accepted then
    begin
      FStore.CompleteRequest(Token,False);
      FLock.Acquire;
      try FActive := 0; finally FLock.Release; end;
      raise Exception.Create('ホストが事前描画を受け付けませんでした。書き出し終了後に再試行してください。');
    end;
  except
    on E: Exception do
    begin
      FLock.Acquire;
      try FQueued := False; FState := 3; finally FLock.Release; end;
      Notify(E.Message,True);
    end;
  end;
end;

procedure TPreparation.WndProc(var Msg: TMessage);
var Text: string; Flags: Cardinal;
begin
  try
    case Msg.Msg of
      WM_PREPARE: StartRequest;
      WM_NOTIFY:
        begin
          Text := '';
          FLock.Acquire;
          try
            if FNotifications.Count > 0 then
            begin Text := FNotifications[0]; FNotifications.Delete(0); end;
          finally FLock.Release; end;
          if (Text <> '') and not FClosing and not FSilent then
          begin
            Flags := MB_OK or MB_ICONINFORMATION;
            if Text[1] = '1' then Flags := MB_OK or MB_ICONWARNING;
            Delete(Text,1,1);
            MessageBox(0,PChar(Text),'写真撮影',Flags);
          end;
        end;
      WM_FINISHED:
        begin
          FLock.Acquire;
          try
            if NativeUInt(Msg.WParam) <> FActive then Exit;
            FActive := 0;
            if FSubmittedGeneration <> FGeneration then Msg.LParam := 0;
            if Msg.LParam <> 0 then FState := 2 else FState := 3;
          finally FLock.Release; end;
          if Msg.LParam <> 0 then
            Notify('写真を準備しました。シーク・書き出しに使用できます。編集後は再準備してください。',False)
          else
            Notify('対象の入力を取得できないか、準備中に編集されました。古い写真は採用しません。再準備してください。',True);
        end;
    else Msg.Result := DefWindowProc(FWindow,Msg.Msg,Msg.WParam,Msg.LParam);
    end;
  except
    on E: Exception do OutputDebugString(PChar('PhotoShot dispatcher: '+E.Message));
  end;
end;

procedure PrepareClick(Edit: PPhotoShotEditSection; Obj: OBJECT_HANDLE; Effect,Item: PWideChar); cdecl;
begin
  try
    if Preparation <> nil then Preparation.Queue(Edit,Obj,Effect);
  except
    on E: Exception do
      if Preparation <> nil then Preparation.Notify(E.Message,True);
  end;
end;

procedure StatusClick(Edit: PPhotoShotEditSection; Obj: OBJECT_HANDLE; Effect,Item: PWideChar); cdecl;
var E: EFFECT_HANDLE; S,Captured: TPhotoShotSettings; Image: TGPBitmap; StateText: string;
begin
  try
    if (Preparation = nil) or (Edit = nil) or (Edit^.Base.Info = nil) or
      not Assigned(Edit^.FindEffect) or not Assigned(Edit^.GetObjectID) or
      not Assigned(Edit^.GetEffectID) then Exit;
    E := Edit^.FindEffect(Obj,Effect);
    S := ReadPhotoShotParameters;
    Image := Preparation.FStore.CopyPrepared(PEDIT_INFO(Edit^.Base.Info)^.SceneID,
      Edit^.GetObjectID(Obj),Edit^.GetEffectID(E),S.EnterFrames+S.WaitFrames,Captured);
    try
      if Image <> nil then StateText := 'このエフェクトは写真を準備済みです。'
      else StateText := 'このエフェクトは未準備です。「写真を準備」を押してください。';
    finally Image.Free; end;
    Preparation.Notify(StateText+#13#10+Preparation.FStore.GetStatus,False);
  except
    on E: Exception do
      if Preparation <> nil then Preparation.Notify(E.Message,True);
  end;
end;

procedure InitializePhotoShotPreparation;
begin
  if Preparation = nil then Preparation := TPreparation.Create;
end;

procedure FinalizePhotoShotPreparation;
begin
  FreeAndNil(Preparation);
end;

procedure RegisterPhotoShotHost(Host: PPhotoShotHostAppTable);
type
  TProjectHandler = procedure(Callback: Pointer); cdecl;
  TClearHandler = procedure(Callback: Pointer); cdecl;
begin
  if (Preparation = nil) or (Host = nil) or not Assigned(Host^.CreateEditHandle) then Exit;
  Preparation.FHandle := Host^.CreateEditHandle;
  if Assigned(Host^.RegisterEventListener) then
  begin
    Host^.RegisterEventListener(PHOTOSHOT_EVENT_UPDATE_OBJECT,nil,HostChanged);
    Host^.RegisterEventListener(PHOTOSHOT_EVENT_CHANGE_EDIT_SCENE,nil,HostChanged);
  end;
  if Host^.RegisterProjectLoadHandler <> nil then
    TProjectHandler(Host^.RegisterProjectLoadHandler)(@ProjectLoaded);
  if Host^.RegisterClearCacheHandler <> nil then
    TClearHandler(Host^.RegisterClearCacheHandler)(@CacheCleared);
end;

procedure RegisterPhotoShotPreparationButtons;
begin
  AddGroup(PreparationGroup,'写真準備',1);
  PrepareButton.ItemType := 'button'; PrepareButton.Name := '写真を準備';
  PrepareButton.Callback := nil; PrepareButton.Callback2 := @PrepareClick;
  StatusButton.ItemType := 'button'; StatusButton.Name := '準備状態';
  StatusButton.Callback := nil; StatusButton.Callback2 := @StatusClick;
  // 登録ヘルパーは既存 AddButton を利用し、その後 callback2 を割り当てる。
  AddButton(PrepareButton,'写真を準備',nil); PrepareButton.Callback2 := @PrepareClick;
  AddButton(StatusButton,'準備状態',nil); StatusButton.Callback2 := @StatusClick;
end;

function InterceptPhotoShotInput(Video: PFILTER_PROC_VIDEO; Input: TGPBitmap;
  const Settings: TPhotoShotSettings): Boolean;
var Token: NativeUInt;
begin
  Result := False;
  if (Preparation = nil) or (Video = nil) or (Video^.Scene = nil) or (Video^.Object_ = nil) then Exit;
  Preparation.FLock.Acquire;
  try Token := Preparation.FActive; finally Preparation.FLock.Release; end;
  if Token = 0 then Exit;
  Result := Preparation.FStore.Capture(Token,Video^.Scene^.ID,
    Video^.Object_^.ID,Video^.Object_^.EffectID,
    Video^.Object_^.FrameS+Video^.Object_^.Frame,Video^.Object_^.Frame,Input,Settings);
end;

function CopyPreparedPhotoShot(Video: PFILTER_PROC_VIDEO; ShutterFrame: Integer;
  out CapturedSettings: TPhotoShotSettings): TGPBitmap;
begin
  Result := nil; CapturedSettings := Default(TPhotoShotSettings);
  if (Preparation = nil) or (Video = nil) or (Video^.Scene = nil) or (Video^.Object_ = nil) then Exit;
  Result := Preparation.FStore.CopyPrepared(Video^.Scene^.ID,Video^.Object_^.ID,
    Video^.Object_^.EffectID,ShutterFrame,CapturedSettings);
end;

procedure RemovePreparedPhotoShot(EffectID: Int64);
begin
  if Preparation <> nil then Preparation.FStore.RemoveEffect(EffectID);
end;

procedure PhotoShotSetPreparationSilent(Value: Byte); cdecl;
begin
  if Preparation <> nil then Preparation.FSilent := Value <> 0;
end;

function PhotoShotPreparationState: Integer; cdecl;
begin
  Result := 0;
  if Preparation <> nil then
  begin
    Preparation.FLock.Acquire;
    try Result := Preparation.FState; finally Preparation.FLock.Release; end;
  end;
end;

end.
