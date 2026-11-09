library SYNC_PhotoShot;

// 写真撮影プラグインの AviUtl2 DLL エントリーポイント。

{$ALIGN 8}
// 標準の DLL を出力し、ビルド後イベントで .auf2 化・配備する。

uses
  SYNC_SmartphoneRenderer in 'Source\Lib\Smartphone\SYNC_SmartphoneRenderer.pas',
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  SYNC_PhotoShot_FilterPlugin in 'Source\Plugin\Filter\SYNC_PhotoShot_FilterPlugin.pas';

{$R *.res}

// 入力 Version はホストの版番号（現段階では未使用）。初期登録成功時 1、失敗時 0。
// テーブルは DLL の有効期間中保持し、例外をホストへ伝播させない。
function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 0;
  try
    GetPhotoShotFilterTable;
    Result := 1;
  except
    // Delphi例外をAviUtl2のCコールバック境界へ漏らさない。
  end;
end;

// ホスト終了時の通知。現段階は所有する動的資源がなく、入力・戻り値・副作用なし。
procedure UninitializePlugin; cdecl;
begin
  // 現段階では解放が必要な資源は保持しない。
end;

// 入力なし。DLL が所有する登録テーブルを返す。ホスト側で解放せず、失敗時は nil。
function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := nil;
  try
    Result := GetPhotoShotFilterTable;
  except
    // 登録失敗時はテーブルを返さずホスト側へ判断を委ねる。
  end;
end;

exports
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
