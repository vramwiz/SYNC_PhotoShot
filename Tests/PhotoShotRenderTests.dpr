program PhotoShotRenderTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Math, Winapi.Windows, Winapi.GDIPAPI, Winapi.GDIPOBJ,
  SYNC_PhotoShot_Timeline, SYNC_PhotoShot_Renderer;
function Hash(B:TGPBitmap):UInt64;
var D:TBitmapData; X,Y:Integer; P:PByte;
begin
  Result:=0;
  if B.LockBits(MakeRect(0,0,Integer(B.GetWidth),Integer(B.GetHeight)),
    ImageLockModeRead,PixelFormat32bppPARGB,D)<>Ok then raise Exception.Create('LockBits');
  try
    for Y:=0 to Integer(B.GetHeight)-1 do begin
      P:=PByte(NativeInt(D.Scan0)+NativeInt(Y)*D.Stride);
      for X:=0 to Integer(B.GetWidth)*4-1 do Result:=Result*31+P[X];
    end;
  finally B.UnlockBits(D); end;
end;
var R:TPhotoShotRenderer; Src,Snap,Image:TGPBitmap; G:TGPGraphics;
 B:TGPSolidBrush; S,Captured:TPhotoShotSettings; I,J,K,Tests:Integer;
 A,C:UInt64; Png:TGUID;
begin
  R:=TPhotoShotRenderer.Create; Src:=nil; Snap:=nil; Tests:=0;
  try
    Src:=TGPBitmap.Create(640,360,PixelFormat32bppPARGB);
    Snap:=TGPBitmap.Create(640,360,PixelFormat32bppPARGB);
    G:=TGPGraphics.Create(Src);
    try
      G.Clear($FF194558);
      B:=TGPSolidBrush.Create($FFF1C761);
      try G.FillRectangle(B,40,20,240,280); finally B.Free; end;
      B:=TGPSolidBrush.Create($FFCE6175);
      try G.FillEllipse(B,310,40,260,260); finally B.Free; end;
    finally G.Free; end;
    G:=TGPGraphics.Create(Snap);
    try G.Clear($FF315637); G.DrawImage(Src,50,20,540,320); finally G.Free; end;
    Png:=StringToGUID('{557CF406-1A04-11D3-9A73-0000F81EF32E}');
    for I:=0 to 3 do for J:=0 to 1 do
    begin
      S:=DefaultPhotoShotSettings; S.CameraKind:=I; S.Orientation:=J;
      S.Scale:=35; S.InnerZoom:=125; S.BackgroundBlur:=10; S.BackgroundDark:=25;
      Image:=R.Render(Src,Snap,S,S.EnterFrames);
      Image.Save(PWideChar(ExtractFilePath(ParamStr(0))+'camera'+IntToStr(I)+'_'+IntToStr(J)+'.png'),Png);
      for K:=0 to 10 do begin
        S.ShutterEffect:=K;
        Image:=R.Render(Src,Snap,S,S.EnterFrames+S.WaitFrames+Max(1,S.ShutterFrames div 2));
        A:=Hash(Image);
        R.Render(Src,Snap,S,200);
        C:=Hash(R.Render(Src,Snap,S,S.EnterFrames+S.WaitFrames+Max(1,S.ShutterFrames div 2)));
        if A<>C then raise Exception.Create('Non-deterministic rendering');
        Inc(Tests);
      end;
      for K:=0 to 2 do begin
        S.PreviewStyle:=K; S.PreviewRotation:=-7;
        Image:=R.Render(Src,Snap,S,500);
        Image.Save(PWideChar(ExtractFilePath(ParamStr(0))+'photo'+IntToStr(I)+'_'+IntToStr(J)+'_'+IntToStr(K)+'.png'),Png);
        Inc(Tests);
      end;
      R.Render(Src,nil,S,500); Inc(Tests);
    end;
    // 境界値でも借用入力を変更せず、描画範囲外・透明・倍率ゼロを安全に扱う。
    A:=Hash(Src);
    S:=DefaultPhotoShotSettings; S.X:=32768; S.Y:=-32768; S.Scale:=0;
    S.Opacity:=0; S.BackgroundBlur:=100; S.BackgroundDark:=100;
    S.InnerZoom:=1; S.InnerX:=32768; S.InnerY:=-32768; S.InnerBlur:=100;
    R.Render(Src,nil,S,S.EnterFrames); Inc(Tests);
    if Hash(Src)<>A then raise Exception.Create('Input bitmap changed');
    S:=DefaultPhotoShotSettings;
    S.EnterFrames:=0; S.WaitFrames:=0; S.ShutterFrames:=0;
    S.ExitFrames:=0; S.PreviewFrames:=0; S.HoldFrames:=0;
    // 写真が取得不能なら、現在フレームを偽の静止写真にしない。
    A:=Hash(R.Render(Src,nil,S,0));
    if A<>Hash(Src) then raise Exception.Create('Nil snapshot changed unprocessed background');
    C:=Hash(R.Render(Src,nil,S,900));
    if A<>C then raise Exception.Create('Nil snapshot is history-dependent');
    Inc(Tests,2);
    // 1 フレームのシャッターはピークを表示し、選択「なし」と異なる。
    S:=DefaultPhotoShotSettings; S.CameraEnter:=0; S.EnterFrames:=0;
    S.WaitFrames:=0; S.ShutterFrames:=1; S.Scale:=35;
    S.ShutterEffect:=0; A:=Hash(R.Render(Src,Snap,S,0));
    for K:=1 to 10 do begin
      S.ShutterEffect:=K;
      if Hash(R.Render(Src,Snap,S,0))=A then
        raise Exception.Create('One-frame shutter is invisible: '+IntToStr(K));
      Inc(Tests);
    end;
    // effect10 は閉鎖前はライブ像、閉鎖後は Snapshot。effect5 と区別される。
    S.ShutterFrames:=9; S.ShutterEffect:=5;
    A:=Hash(R.Render(Src,Snap,S,1));
    S.ShutterEffect:=10; C:=Hash(R.Render(Src,Snap,S,1));
    if A=C then raise Exception.Create('Still switch duplicates iris effect');
    // 閉じてから開く後半では、絞り効果と同じ確定静止画を表示する。
    C:=Hash(R.Render(Src,Snap,S,7));
    S.ShutterEffect:=5; A:=Hash(R.Render(Src,Snap,S,7));
    if A<>C then raise Exception.Create('Still switch failed after iris closure');
    // Snapshot がなければ、どちらの効果もライブ像のまま。
    A:=Hash(R.Render(Src,nil,S,1)); S.ShutterEffect:=10;
    if Hash(R.Render(Src,nil,S,1))<>A then
      raise Exception.Create('Still switch fabricated missing snapshot');
    Inc(Tests,3);
    // 撮影時設定を固定しても、現在のプレビュー姿勢・枠・背景は編集できる。
    Captured:=DefaultPhotoShotSettings; Captured.InnerZoom:=130;
    Captured.InnerX:=12; Captured.InnerY:=-6; Captured.InnerBlur:=3;
    S:=Captured; S.PreviewEnter:=0; S.PreviewScale:=65;
    A:=Hash(R.Render(Src,Snap,S,500,@Captured));
    S.InnerX:=200; S.InnerY:=-150; S.InnerZoom:=250; S.InnerBlur:=90;
    S.CameraKind:=3; S.Orientation:=1;
    if Hash(R.Render(Src,Snap,S,500,@Captured))<>A then
      raise Exception.Create('Current inner settings changed captured photograph');
    S.PreviewX:=45; S.PreviewY:=-20;
    if Hash(R.Render(Src,Snap,S,500,@Captured))=A then
      raise Exception.Create('Captured settings locked preview position');
    S.PreviewX:=0; S.PreviewY:=0; S.PreviewStyle:=2;
    if Hash(R.Render(Src,Snap,S,500,@Captured))=A then
      raise Exception.Create('Captured settings locked preview style');
    S.PreviewStyle:=Captured.PreviewStyle; S.BackgroundDark:=45;
    if Hash(R.Render(Src,Snap,S,500,@Captured))=A then
      raise Exception.Create('Captured settings locked background');
    Inc(Tests,4);
    // シャッター後のカメラ内部も撮影時の内側設定を用いるが、本体姿勢は現在値。
    S:=Captured; S.Scale:=35; S.ShutterEffect:=0;
    A:=Hash(R.Render(Src,Snap,S,S.EnterFrames+S.WaitFrames,@Captured));
    S.InnerX:=200; S.InnerY:=180; S.InnerZoom:=250; S.InnerBlur:=90;
    if Hash(R.Render(Src,Snap,S,S.EnterFrames+S.WaitFrames,@Captured))<>A then
      raise Exception.Create('Frozen camera interior changed after capture');
    S.X:=30;
    if Hash(R.Render(Src,Snap,S,S.EnterFrames+S.WaitFrames,@Captured))=A then
      raise Exception.Create('Captured settings locked camera position');
    Inc(Tests,2);
    Writeln('PASS ',Tests,' render scenarios and repeated-frame hash checks');
  finally Snap.Free; Src.Free; R.Free; end;
end.