unit SYNC_PhotoShot_Capture;

// 現在のフィルター入力を取得し、描画処理に依存しない所有画像へ変換する。
// SYNC_Mine の GetImageData 入力取得方式と SDK の PIXEL_RGBA 定義に基づく。
// 過去フレーム取得・履歴キャッシュ・画面全体のデスクトップ撮影は行わない。

interface

uses
  AviUtl2FilterTypes, Winapi.GDIPOBJ;

// 背景加工・カメラ合成より前に呼ぶ。戻り値は呼出側が Free する。
// 呼出側で GDI+ を開始済みとする。失敗時は nil。Video と入力画素は保持しない。
// 現在のオブジェクト画像のみを取得し、Framebuffer へ対象を切り替えない。
function CapturePhotoShotInput(Video: PFILTER_PROC_VIDEO): TGPBitmap;

implementation

uses
  System.SysUtils, Winapi.GDIPAPI;

function CapturePhotoShotInput(Video: PFILTER_PROC_VIDEO): TGPBitmap;
var
  Pixels: TArray<TPIXEL_RGBA>;
  Width, Height, X, Y: Integer;
  Index: NativeInt;
  Data: TBitmapData;
  Row: PByte;
begin
  Result := nil;
  if (Video = nil) or (Video^.Object_ = nil) or
    not Assigned(Video^.GetImageData) then Exit;
  Width := Video^.Object_^.Width;
  Height := Video^.Object_^.Height;
  // Mine と同じ上限。積は Int64 で判定し、破損したホスト情報で巨大確保しない。
  if (Width <= 0) or (Height <= 0) or (Width > 8192) or (Height > 8192) or
    (Int64(Width) * Height > 33554432) then Exit;
  SetLength(Pixels, NativeInt(Width) * Height);
  Video^.GetImageData(@Pixels[0]);
  Result := TGPBitmap.Create(Width, Height, PixelFormat32bppARGB);
  try
    if Result.GetLastStatus <> Ok then
    begin
      FreeAndNil(Result);
      Exit;
    end;
    Data := Default(TBitmapData);
    if Result.LockBits(MakeRect(0, 0, Width, Height), ImageLockModeWrite,
      PixelFormat32bppARGB, Data) <> Ok then
    begin
      FreeAndNil(Result);
      Exit;
    end;
    try
      for Y := 0 to Height - 1 do
      begin
        Row := PByte(NativeInt(Data.Scan0) + NativeInt(Y) * Data.Stride);
        Index := NativeInt(Y) * Width;
        for X := 0 to Width - 1 do
        begin
          // SDK は RGBA。GDI+ の ARGB ピクセルのメモリ配置は BGRA。
          // 非乗算アルファで取り込み、GDI+ 描画時の二重乗算を避ける。
          Row[0] := Pixels[Index].B;
          Row[1] := Pixels[Index].G;
          Row[2] := Pixels[Index].R;
          Row[3] := Pixels[Index].A;
          Inc(Row, 4);
          Inc(Index);
        end;
      end;
    finally
      Result.UnlockBits(Data);
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

end.
