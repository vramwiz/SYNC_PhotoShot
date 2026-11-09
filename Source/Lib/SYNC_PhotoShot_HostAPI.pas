unit SYNC_PhotoShot_HostAPI;

// AviUtl2 SDK v2.1.15 plugin2.h / filter2.h の Win64 ABI 用 prefix 定義。
// 出典: C:\Users\vramw\Downloads\aviutl2_sdk_v2115。必要本体版 2011500。
// 既存 AviUtl2FilterTypes の定義を変更せず、編集 API の追加部分だけを補う。
// 下記ポインターはホスト所有。編集セクションと返却ハンドルを callback 外へ保持しない。

{$ALIGN 8}

interface

uses
  AviUtl2FilterTypes;

const
  PHOTOSHOT_HOST_API_VERSION = 2011500;
  PHOTOSHOT_EVENT_UPDATE_OBJECT = 1;
  PHOTOSHOT_EVENT_CHANGE_EDIT_FRAME = 2;
  PHOTOSHOT_EVENT_CHANGE_EDIT_SCENE = 3;
  PHOTOSHOT_EVENT_CHANGE_FOCUS_OBJECT = 4;
  PHOTOSHOT_EVENT_CHANGE_EDIT_STATE = 5;
  PHOTOSHOT_EDIT_STATE_EDIT = 0;
  PHOTOSHOT_EDIT_STATE_PLAY = 1;
  PHOTOSHOT_EDIT_STATE_SAVE = 2;

type
  EFFECT_HANDLE = Pointer;
  PPhotoShotEditSection = ^TPhotoShotEditSection;
  PPhotoShotEditHandle = ^TPhotoShotEditHandle;
  PPhotoShotHostAppTable = ^TPhotoShotHostAppTable;
  PPhotoShotCommonPluginTable = ^TPhotoShotCommonPluginTable;

  // Win64: callback は cdecl、C++ bool 戻り値は 1 byte とする。
  TPhotoShotEditCallback = procedure(Edit: PPhotoShotEditSection); cdecl;
  TPhotoShotEditParamCallback = procedure(Param: Pointer;
    Edit: PPhotoShotEditSection); cdecl;
  TPhotoShotEventCallback = procedure(Param: Pointer); cdecl;
  TRenderPhotoShotVideoCallback = procedure(Param: Pointer; Frame: Integer;
    Buffer: Pointer; Width, Height, Pitch: Integer); cdecl;
  TPhotoShotButtonCallback2 = procedure(Edit: PPhotoShotEditSection;
    Object_: OBJECT_HANDLE; Effect, Item: PWideChar); cdecl;

  TPhotoShotFindEffect = function(Object_: OBJECT_HANDLE;
    Effect: PWideChar): EFFECT_HANDLE; cdecl;
  TPhotoShotGetObjectID = function(Object_: OBJECT_HANDLE): Int64; cdecl;
  TPhotoShotGetEffectID = function(Effect: EFFECT_HANDLE): Int64; cdecl;

  TPhotoShotEditSection = record
    Base: TEDIT_SECTION; // offsets 0..208。SizeOf(Base)=216 を単体試験で検査。
    // offsets 216..392: get_layer_name から deprecated_set_grid_bpm_list まで。
    Reserved216To392: array[0..22] of Pointer;
    FindEffect: TPhotoShotFindEffect; // 400。effect に ":n" suffix を指定可能。
    // offsets 408..640: get_effect_list から set_object_flag まで。
    Reserved408To640: array[0..29] of Pointer;
    GetObjectID: TPhotoShotGetObjectID; // 648。
    GetEffectID: TPhotoShotGetEffectID; // 656。prefix size=664。
  end;

  TPhotoShotCallEditSection = function(Callback: TPhotoShotEditCallback): Byte; cdecl;
  TPhotoShotCallEditSectionParam = function(Param: Pointer;
    Callback: TPhotoShotEditParamCallback): Byte; cdecl;
  TPhotoShotGetEditInfo = procedure(Info: PEDIT_INFO; InfoSize: Integer); cdecl;
  TPhotoShotGetEditState = function: Integer; cdecl;
  TPhotoShotRenderingSceneVideo = function(Frame: Integer; Param: Pointer;
    Callback: TRenderPhotoShotVideoCallback): Byte; cdecl;
  TPhotoShotWaitRenderingTask = procedure; cdecl;

  TPhotoShotEditHandle = record
    CallEditSection: TPhotoShotCallEditSection; // 0。callback はメインスレッド。
    CallEditSectionParam: TPhotoShotCallEditSectionParam; // 8。
    GetEditInfo: TPhotoShotGetEditInfo; // 16。InfoSize 分のみ取得。
    RestartHostApp: Pointer; // 24。
    EnumEffectName: Pointer; // 32。
    EnumModuleInfo: Pointer; // 40。
    GetHostAppWindow: Pointer; // 48。
    GetEditState: TPhotoShotGetEditState; // 56。
    CallReadSection: TPhotoShotCallEditSection; // 64。callback は呼出元スレッド。
    CallReadSectionParam: TPhotoShotCallEditSectionParam; // 72。
    EnumEffectItem: Pointer; // 80。
    // タスク受付のみ。出力中等は 0。完了はイベント通知スレッドの callback。
    RenderingSceneVideo: TPhotoShotRenderingSceneVideo; // 88。
    RenderingSceneAudio: Pointer; // 96。
    // 参照／編集ロック中には使用しない。デッドロックの可能性が SDK に明記。
    WaitRenderingTask: TPhotoShotWaitRenderingTask; // 104。prefix size=112。
  end;

  TPhotoShotRegisterFilterPlugin = procedure(Table: PFILTER_PLUGIN_TABLE); cdecl;
  TPhotoShotCreateEditHandle = function: PPhotoShotEditHandle; cdecl;
  TPhotoShotRegisterEventListener = procedure(EventType: Integer; Param: Pointer;
    Callback: TPhotoShotEventCallback); cdecl;

  TPhotoShotHostAppTable = record
    SetPluginInformation: Pointer; // 0。
    RegisterInputPlugin: Pointer; // 8。
    RegisterOutputPlugin: Pointer; // 16。
    RegisterFilterPlugin: TPhotoShotRegisterFilterPlugin; // 24。
    RegisterScriptModule: Pointer; // 32。
    RegisterImportMenu: Pointer; // 40。
    RegisterExportMenu: Pointer; // 48。
    RegisterWindowClient: Pointer; // 56。
    CreateEditHandle: TPhotoShotCreateEditHandle; // 64。
    RegisterProjectLoadHandler: Pointer; // 72。
    RegisterProjectSaveHandler: Pointer; // 80。
    RegisterLayerMenu: Pointer; // 88。
    RegisterObjectMenu: Pointer; // 96。
    RegisterConfigMenu: Pointer; // 104。
    RegisterEditMenu: Pointer; // 112。
    RegisterClearCacheHandler: Pointer; // 120。
    RegisterChangeSceneHandler: Pointer; // 128。
    RegisterImportMenuParam: Pointer; // 136。
    RegisterExportMenuParam: Pointer; // 144。
    RegisterLayerMenuParam: Pointer; // 152。
    RegisterObjectMenuParam: Pointer; // 160。
    RegisterEditMenuParam: Pointer; // 168。
    RegisterFileDropHandler: Pointer; // 176。
    RegisterFileDropParamHandler: Pointer; // 184。
    RegisterObjectItemMenu: Pointer; // 192。
    RegisterObjectItemMenuParam: Pointer; // 200。
    RegisterScriptModuleName: Pointer; // 208。
    RegisterFontCollection: Pointer; // 216。
    // callback はイベント通知スレッド。callback 内から CallEditSection を呼ばない。
    RegisterEventListener: TPhotoShotRegisterEventListener; // 224。size=232。
  end;

  TPhotoShotCommonPluginTable = record
    Name: PWideChar;
    Information: PWideChar;
  end;

implementation

end.
