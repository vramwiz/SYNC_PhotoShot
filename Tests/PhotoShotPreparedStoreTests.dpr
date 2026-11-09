program PhotoShotPreparedStoreTests;

{$APPTYPE CONSOLE}
{$RANGECHECKS ON}
{$OVERFLOWCHECKS ON}

uses
  System.SysUtils, System.Classes, System.SyncObjs, Winapi.Windows,
  Winapi.GDIPAPI, Winapi.GDIPOBJ,
  SYNC_PhotoShot_Timeline in '..\Source\Common\SYNC_PhotoShot_Timeline.pas',
  SYNC_PhotoShot_PreparedStore in '..\Source\Common\SYNC_PhotoShot_PreparedStore.pas';

type
  TStressThread = class(TThread)
  private
    FStore: TPhotoShotPreparedStore;
    FRole: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(Store: TPhotoShotPreparedStore; Role: Integer);
  end;
var
  Checks: Integer;

procedure Check(Value: Boolean; const Msg: string);
begin
  TInterlocked.Increment(Checks);
  if not Value then raise Exception.Create(Msg);
end;

function Bitmap: TGPBitmap;
begin
  Result := TGPBitmap.Create(16, 8, PixelFormat32bppARGB);
  Check(Result.GetLastStatus = Ok, 'create bitmap');
  Result.SetPixel(0, 0, $FF123456);
end;

procedure Empty(Store: TPhotoShotPreparedStore; Scene: Integer;
  Obj, Effect: Int64; Frame: Integer);
var
  Image: TGPBitmap;
  S: TPhotoShotSettings;
begin
  Image := Store.CopyPrepared(Scene, Obj, Effect, Frame, S);
  try
    Check(Image = nil, 'no ready photo');
  finally
    Image.Free;
  end;
end;

procedure BasicTests;
var
  Store: TPhotoShotPreparedStore;
  Input, Copy1, Copy2: TGPBitmap;
  S, Saved: TPhotoShotSettings;
  A, B: NativeUInt;
  Color: ARGB;
begin
  Store := TPhotoShotPreparedStore.Create;
  Input := Bitmap;
  try
    S := DefaultPhotoShotSettings;
    S.InnerX := 17;
    S.CameraKind := 2;
    Check(Store.PendingToken = 0, 'initial no pending');
    Check(Store.GetStatus <> '', 'initial status');
    Check(Store.BeginRequest(1, 2, 3, -1, 45) = 0, 'invalid absolute frame');
    Check(Store.BeginRequest(1, 2, 3, 55, -1) = 0, 'invalid relative frame');
    A := Store.BeginRequest(1, 2, 3, 55, 45);
    Check(A <> 0, 'request token');
    Check(Store.PendingToken = A, 'pending token');
    Check(Store.BeginRequest(1, 99, 98, 55, 45) = 0, 'single pending');
    Check(not Store.Capture(A + 1, 1, 2, 3, 55, 45, Input, S), 'wrong token');
    Check(not Store.Capture(A, 9, 2, 3, 55, 45, Input, S), 'wrong scene');
    Check(not Store.Capture(A, 1, 9, 3, 55, 45, Input, S), 'wrong object');
    Check(not Store.Capture(A, 1, 2, 9, 55, 45, Input, S), 'wrong effect');
    Check(not Store.Capture(A, 1, 2, 3, 54, 45, Input, S), 'wrong absolute frame');
    Check(not Store.Capture(A, 1, 2, 3, 55, 44, Input, S), 'wrong relative frame');
    Check(not Store.Capture(A, 1, 2, 3, 55, 45, nil, S), 'nil image');
    S.WaitFrames := 31;
    Check(not Store.Capture(A, 1, 2, 3, 55, 45, Input, S), 'wrong setting time');
    S.WaitFrames := 30;
    Check(Store.Capture(A, 1, 2, 3, 55, 45, Input, S), 'capture');
    Check(not Store.Capture(A, 1, 2, 3, 55, 45, Input, S), 'duplicate capture');
    Empty(Store, 1, 2, 3, 45);
    Input.SetPixel(0, 0, $FFABCDEF);
    S.InnerX := 99;
    Check(Store.CompleteRequest(A, True), 'commit');
    Check(Store.PendingToken = 0, 'pending consumed');
    Check(not Store.CompleteRequest(A, True), 'repeated completion');
    Empty(Store, 2, 2, 3, 45);
    Empty(Store, 1, 9, 3, 45);
    Empty(Store, 1, 2, 9, 45);
    Empty(Store, 1, 2, 3, 46);
    Copy1 := Store.CopyPrepared(1, 2, 3, 45, Saved);
    try
      Check(Copy1 <> nil, 'prepared available');
      Check((Saved.InnerX = 17) and (Saved.CameraKind = 2), 'immutable captured settings');
      Copy1.GetPixel(0, 0, Color);
      Check(Color = $FF123456, 'input clone independent');
      Copy1.SetPixel(0, 0, $FF000000);
      Copy2 := Store.CopyPrepared(1, 2, 3, 45, Saved);
      try
        Check((Copy2 <> nil) and (Copy2 <> Copy1), 'caller owned fresh clone');
        Copy2.GetPixel(0, 0, Color);
        Check(Color = $FF123456, 'returned clone independent');
      finally
        Copy2.Free;
      end;
    finally
      Copy1.Free;
    end;
    B := Store.BeginRequest(1, 8, 9, 65, 45);
    Check(Store.Capture(B, 1, 8, 9, 65, 45, Input, S), 'second object capture');
    Check(Store.CompleteRequest(B, True), 'second object ready');
    Copy1 := Store.CopyPrepared(1, 2, 3, 45, Saved);
    try Check(Copy1 <> nil, 'first object retained'); finally Copy1.Free; end;
    Store.RemoveEffect(3);
    Empty(Store, 1, 2, 3, 45);
    Copy1 := Store.CopyPrepared(1, 8, 9, 45, Saved);
    try Check(Copy1 <> nil, 'unrelated effect retained'); finally Copy1.Free; end;
    Store.InvalidateAll;
    Empty(Store, 1, 8, 9, 45);
    Check(not Store.CompleteRequest(B, True), 'old committed token rejected');
  finally
    Input.Free;
    Store.Free;
  end;
end;

procedure InvalidationsAndFailureTests;
var
  Store: TPhotoShotPreparedStore;
  Input: TGPBitmap;
  S: TPhotoShotSettings;
  A, B: NativeUInt;
begin
  Store := TPhotoShotPreparedStore.Create;
  Input := Bitmap;
  try
    S := DefaultPhotoShotSettings;
    A := Store.BeginRequest(1, 2, 3, 55, 45);
    Check(not Store.CompleteRequest(A, True), 'host success without capture fails');
    Check(Store.PendingToken = 0, 'failed request consumed');
    A := Store.BeginRequest(1, 2, 3, 55, 45);
    Check(Store.Capture(A, 1, 2, 3, 55, 45, Input, S), 'capture before host failure');
    Check(not Store.CompleteRequest(A, False), 'host failure rejects captured image');
    Empty(Store, 1, 2, 3, 45);
    A := Store.BeginRequest(1, 2, 3, 55, 45);
    Check(Store.Capture(A, 1, 2, 3, 55, 45, Input, S), 'capture before edit');
    Store.InvalidateAll;
    B := Store.BeginRequest(1, 2, 3, 55, 45);
    Check((B <> 0) and (B <> A), 'new token after invalidation');
    Check(not Store.Capture(A, 1, 2, 3, 55, 45, Input, S), 'old same-target callback rejected');
    Check(not Store.CompleteRequest(A, True), 'old completion leaves new pending intact');
    Check(Store.PendingToken = B, 'new pending intact');
    Check(Store.Capture(B, 1, 2, 3, 55, 45, Input, S), 'new capture');
    Store.RemoveEffect(3);
    Check(not Store.CompleteRequest(B, True), 'destroyed effect late result rejected');
    Empty(Store, 1, 2, 3, 45);
    A := Store.BeginRequest(1, 2, 3, 55, 45);
    Store.RemoveEffect(99);
    Check(Store.PendingToken = A, 'unrelated destroy preserves pending');
    Check(Store.Capture(A, 1, 2, 3, 55, 45, Input, S), 'capture after unrelated destroy');
    Check(Store.CompleteRequest(A, True), 'commit after unrelated destroy');
    B := Store.BeginRequest(1, 2, 3, 55, 45);
    Empty(Store, 1, 2, 3, 45);
    Check(not Store.CompleteRequest(B, False), 'replacement failure does not restore stale image');
    Empty(Store, 1, 2, 3, 45);
  finally
    Input.Free;
    Store.Free;
  end;
end;

constructor TStressThread.Create(Store: TPhotoShotPreparedStore; Role: Integer);
begin
  inherited Create(True);
  FStore := Store;
  FRole := Role;
  FreeOnTerminate := False;
end;

procedure TStressThread.Execute;
var
  I: Integer;
  Token: NativeUInt;
  S, Saved: TPhotoShotSettings;
  Input, Copy: TGPBitmap;
  Color: ARGB;
begin
  Input := Bitmap;
  try
    S := DefaultPhotoShotSettings;
    S.InnerX := 17;
    for I := 1 to 500 do
      case FRole of
        0:
          begin
            Token := FStore.BeginRequest(1, 2, 3, 55, 45);
            if Token <> 0 then
            begin
              FStore.Capture(Token, 1, 2, 3, 55, 45, Input, S);
              FStore.CompleteRequest(Token, True);
            end;
          end;
        1:
          begin
            Copy := FStore.CopyPrepared(1, 2, 3, 45, Saved);
            try
              if Copy <> nil then
              begin
                Copy.GetPixel(0, 0, Color);
                Check(Color = $FF123456, 'concurrent clone valid');
                Check(Saved.InnerX = 17, 'concurrent settings valid');
              end;
            finally
              Copy.Free;
            end;
            Check(FStore.GetStatus <> '', 'concurrent status');
            FStore.PendingToken;
          end;
        2: FStore.InvalidateAll;
        3: FStore.RemoveEffect(3);
      end;
  finally
    Input.Free;
  end;
end;

procedure ConcurrentTests;
var
  Store: TPhotoShotPreparedStore;
  Workers: array[0..3] of TStressThread;
  I: Integer;
begin
  Store := TPhotoShotPreparedStore.Create;
  try
    for I := 0 to 3 do Workers[I] := TStressThread.Create(Store, I);
    try
      for I := 0 to 3 do Workers[I].Start;
      for I := 0 to 3 do Workers[I].WaitFor;
      for I := 0 to 3 do
        Check(Workers[I].FatalException = nil, 'worker has no exception');
      Store.InvalidateAll;
      Check(Store.PendingToken = 0, 'final edit clears pending');
      Empty(Store, 1, 2, 3, 45);
    finally
      for I := 0 to 3 do Workers[I].Free;
    end;
  finally
    // 実行中 thread をすべて join してからストア自体を破棄する。
    Store.Free;
  end;
end;

var
  Token: ULONG_PTR;
  Startup: TGdiplusStartupInput;
begin
  try
    Startup := Default(TGdiplusStartupInput);
    Startup.GdiplusVersion := 1;
    Check(GdiplusStartup(Token, @Startup, nil) = Ok, 'GDI+ startup');
    try
      BasicTests;
      InvalidationsAndFailureTests;
      ConcurrentTests;
    finally
      GdiplusShutdown(Token);
    end;
    Writeln('PASS: ', Checks, ' prepared-store assertions; immutable clones,');
    Writeln('tokens, invalidation, late callbacks, independent objects and 4-thread stress.');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
