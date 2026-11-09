unit PluginFilterTable;

// AviUtl2 Filterテーブルと設定項目の順次登録を一か所で管理する。
// SYNC_Nicomea から移植した共通基盤。SDK 型と登録項目の寿命を一元管理する。

interface

uses
  AviUtl2FilterTypes;

// 名前・説明・コールバックを登録し、既存の項目配列をリセットする。
// ポインターは保持するため、文字列・項目・コールバックは DLL の有効期間中存続させる。
procedure SetupPluginTable(Flag: Integer; Name, Label_, Information: PWideChar;
  VideoProc: TFuncProcVideo; AudioProc: TFuncProcAudio);
// Add 系は var Item を初期化して登録順に追加する。項目・文字列・選択肢の所有権は呼び出し側に残る。
// 名前と初期値を受け取り、戻り値はない。上限超過時は ERangeError。設定の永続化は担当しない。
procedure AddFile(var Item: TFILTER_ITEM_FILE; Name, Value,
  FileFilter: PWideChar);
procedure AddButton(var Item: TFILTER_ITEM_BUTTON; Name: PWideChar;
  Callback: TFilterItemButtonCallback);
procedure AddString(var Item: TFILTER_ITEM_STRING; Name, Value: PWideChar);
procedure AddColor(var Item: TFILTER_ITEM_COLOR; Name: PWideChar;
  B, G, R: Byte; X: Byte = 255);
procedure AddTrack(var Item: TFILTER_ITEM_TRACK; Name: PWideChar;
  Value, S, E, Step: Double);
procedure AddCheck(var Item: TFILTER_ITEM_CHECK; Name: PWideChar;
  Value: Byte);
procedure AddSelect(var Item: TFILTER_ITEM_SELECT; Name: PWideChar;
  Value: Integer; List: Pointer);
procedure AddGroup(var Item: TFILTER_ITEM_GROUP; Name: PWideChar;
  DefaultVisible: Byte);
procedure AddAlwaysHideRule(var Item: TFILTER_ITEM_HIDE_RULE; Name: PWideChar);

// 別ユニットで初期化済みの項目も同じ登録順へ組み込めるようにする。
procedure AddFilterItem(var Item: TFILTER_ITEM_TRACK); overload;
procedure AddFilterItem(var Item: TFILTER_ITEM_CHECK); overload;
procedure AddFilterItem(var Item: TFILTER_ITEM_GROUP); overload;
procedure AddFilterItem(var Item: TFILTER_ITEM_SELECT); overload;
procedure AddFilterItem(var Item: TFILTER_ITEM_COLOR); overload;

// 入力なし。DLL 所有のテーブルを返す。呼び出し側は解放せず、事前に SetupPluginTable を呼ぶ。
function GetPluginTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.SysUtils;

const
  MAX_GUI_ITEMS = 100;

var
  GTable: TFILTER_PLUGIN_TABLE;
  GItems: array[0..MAX_GUI_ITEMS - 1] of Pointer;
  GItemIndex: Integer;

procedure RegisterItem(Item: Pointer);
begin
  // 最後の1要素はAviUtl2が要求するnil終端用に予約する。
  if GItemIndex >= High(GItems) then
    raise ERangeError.CreateFmt(
      'Filter setting item count exceeds the limit (%d)',
      [High(GItems)]);
  GItems[GItemIndex] := Item;
  Inc(GItemIndex);
  GItems[GItemIndex] := nil;
end;

procedure SetupPluginTable(Flag: Integer; Name, Label_, Information: PWideChar;
  VideoProc: TFuncProcVideo; AudioProc: TFuncProcAudio);
begin
  GItemIndex := 0;
  FillChar(GItems, SizeOf(GItems), 0);
  GTable.Flag := Flag;
  GTable.Name := Name;
  GTable.Label_ := Label_;
  GTable.Information := Information;
  GTable.Items := @GItems[0];
  GTable.Func_Proc_Video := VideoProc;
  GTable.Func_Proc_Audio := AudioProc;
  GTable.Func_Create := nil;
  GTable.Func_Destroy := nil;
end;

procedure AddFile(var Item: TFILTER_ITEM_FILE; Name, Value,
  FileFilter: PWideChar);
begin
  Item.ItemType := 'file';
  Item.Name := Name;
  Item.Value := Value;
  Item.FileFilter := FileFilter;
  RegisterItem(@Item);
end;

procedure AddButton(var Item: TFILTER_ITEM_BUTTON; Name: PWideChar;
  Callback: TFilterItemButtonCallback);
begin
  Item.ItemType := 'button';
  Item.Name := Name;
  Item.Callback := Callback;
  Item.Callback2 := nil;
  RegisterItem(@Item);
end;

procedure AddString(var Item: TFILTER_ITEM_STRING; Name, Value: PWideChar);
begin
  Item.ItemType := 'string';
  Item.Name := Name;
  Item.Value := Value;
  RegisterItem(@Item);
end;

procedure AddColor(var Item: TFILTER_ITEM_COLOR; Name: PWideChar;
  B, G, R, X: Byte);
begin
  Item.ItemType := 'color';
  Item.Name := Name;
  Item.B := B;
  Item.G := G;
  Item.R := R;
  Item.X := X;
  RegisterItem(@Item);
end;

procedure AddTrack(var Item: TFILTER_ITEM_TRACK; Name: PWideChar;
  Value, S, E, Step: Double);
begin
  Item.ItemType := 'track';
  Item.Name := Name;
  Item.Value := Value;
  Item.S := S;
  Item.E := E;
  Item.Step := Step;
  RegisterItem(@Item);
end;

procedure AddCheck(var Item: TFILTER_ITEM_CHECK; Name: PWideChar;
  Value: Byte);
begin
  Item.ItemType := 'check';
  Item.Name := Name;
  Item.Value := Value;
  RegisterItem(@Item);
end;

procedure AddSelect(var Item: TFILTER_ITEM_SELECT; Name: PWideChar;
  Value: Integer; List: Pointer);
begin
  Item.ItemType := 'select';
  Item.Name := Name;
  Item.Value := Value;
  Item.List := List;
  RegisterItem(@Item);
end;

procedure AddGroup(var Item: TFILTER_ITEM_GROUP; Name: PWideChar;
  DefaultVisible: Byte);
begin
  Item.ItemType := 'group';
  Item.Name := Name;
  Item.DefaultVisible := DefaultVisible;
  RegisterItem(@Item);
end;

procedure AddAlwaysHideRule(var Item: TFILTER_ITEM_HIDE_RULE; Name: PWideChar);
begin
  Item := Default(TFILTER_ITEM_HIDE_RULE);
  Item.ItemType := 'hiderule';
  Item.Name := Name;
  RegisterItem(@Item);
end;

procedure AddFilterItem(var Item: TFILTER_ITEM_TRACK);
begin
  RegisterItem(@Item);
end;

procedure AddFilterItem(var Item: TFILTER_ITEM_CHECK);
begin
  RegisterItem(@Item);
end;

procedure AddFilterItem(var Item: TFILTER_ITEM_GROUP);
begin
  RegisterItem(@Item);
end;

procedure AddFilterItem(var Item: TFILTER_ITEM_SELECT);
begin
  RegisterItem(@Item);
end;

procedure AddFilterItem(var Item: TFILTER_ITEM_COLOR);
begin
  RegisterItem(@Item);
end;

function GetPluginTable: PFILTER_PLUGIN_TABLE;
begin
  Result := @GTable;
end;

end.
