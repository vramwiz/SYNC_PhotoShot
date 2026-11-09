unit SYNC_PhotoShot_FilterPlugin;

// 「写真撮影」の登録だけを行う最小構成。撮影演出は後続実装で追加する。
interface

uses
  AviUtl2FilterTypes;

// 入力なし。初回だけ登録を初期化し、DLL の有効期間中保持するテーブルを返す。
// 所有権は PluginFilterTable 側にあり、呼び出し側は解放しない。ディスク保存は行わない。
function GetPhotoShotFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  PluginFilterTable;

var
  // DLL 内の初回登録フラグ。ホストのプラグイン初期化・テーブル取得から使用する。
  PluginTableInitialized: Boolean;

// Video はホスト所有のフレーム情報。参照・保持・変更せず、処理成功を表す 1 を返す。
function PhotoShotProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
begin
  // 骨組みの段階では入力画像を変更せず、そのまま通す。
  Result := 1;
end;

function GetPhotoShotFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not PluginTableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER,
      '写真撮影', 'SYNC', '写真撮影プラグイン（最小構成）',
      PhotoShotProcVideo, nil);
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
