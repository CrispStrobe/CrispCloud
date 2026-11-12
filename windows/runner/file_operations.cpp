#include "file_operations.h"
#include "utils.h"
#include <windows.h>
#include <ole2.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <cstring>
#include <filesystem>
#include <utility>
#include <memory>
#include <string>
#include <vector>

namespace {
using flutter::EncodableValue;
using flutter::EncodableMap;
using flutter::EncodableList;
using Microsoft::WRL::ComPtr;

std::wstring Wide(const std::string& value) {
  const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                  static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(n, L'\0');
  if (n) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                           static_cast<int>(value.size()), &result[0], n);
  return result;
}

std::string StringArg(const EncodableMap* args, const char* key) {
  if (!args) return {};
  const auto found = args->find(EncodableValue(key));
  if (found == args->end()) return {};
  const auto* value = std::get_if<std::string>(&found->second);
  return value ? *value : "";
}

// The sink records the actual recycle-bin item. It refuses a permanent-delete
// fallback, and refuses overwrite/merge decisions during restore.
class TrashSink final : public IFileOperationProgressSink {
 public:
  LONG refs = 1;
  std::wstring recycled;
  std::wstring restore_path;
  HRESULT outcome = E_PENDING;
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** out) override {
    if (!out) return E_POINTER;
    *out = nullptr;
    if (id == IID_IUnknown || id == IID_IFileOperationProgressSink) {
      *out = static_cast<IFileOperationProgressSink*>(this);
      AddRef(); return S_OK;
    }
    return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs); }
  ULONG STDMETHODCALLTYPE Release() override {
    const auto value = InterlockedDecrement(&refs);
    if (!value) delete this;
    return value;
  }
  HRESULT STDMETHODCALLTYPE StartOperations() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE FinishOperations(HRESULT value) override {
    if (FAILED(value)) outcome = value;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PreRenameItem(DWORD, IShellItem*, LPCWSTR) override { return E_ABORT; }
  HRESULT STDMETHODCALLTYPE PostRenameItem(DWORD, IShellItem*, LPCWSTR, HRESULT, IShellItem*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PreMoveItem(DWORD flags, IShellItem*, IShellItem*, LPCWSTR) override {
    if ((flags & TSF_OVERWRITE_EXIST) ||
        (!restore_path.empty() && GetFileAttributesW(restore_path.c_str()) != INVALID_FILE_ATTRIBUTES)) return E_ABORT;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PostMoveItem(DWORD, IShellItem*, IShellItem*, LPCWSTR, HRESULT value, IShellItem*) override {
    outcome = value; return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PreCopyItem(DWORD, IShellItem*, IShellItem*, LPCWSTR) override { return E_ABORT; }
  HRESULT STDMETHODCALLTYPE PostCopyItem(DWORD, IShellItem*, IShellItem*, LPCWSTR, HRESULT, IShellItem*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PreDeleteItem(DWORD flags, IShellItem*) override {
    return (flags & TSF_DELETE_RECYCLE_IF_POSSIBLE) ? S_OK : E_ABORT;
  }
  HRESULT STDMETHODCALLTYPE PostDeleteItem(DWORD, IShellItem*, HRESULT value, IShellItem* item) override {
    outcome = value;
    if (SUCCEEDED(value) && item) {
      PWSTR name = nullptr;
      if (SUCCEEDED(item->GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, &name))) {
        recycled = name; CoTaskMemFree(name);
      }
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PreNewItem(DWORD, IShellItem*, LPCWSTR) override { return E_ABORT; }
  HRESULT STDMETHODCALLTYPE PostNewItem(DWORD, IShellItem*, LPCWSTR, LPCWSTR, DWORD, HRESULT, IShellItem*) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE UpdateProgress(UINT, UINT) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE ResetTimer() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PauseTimer() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE ResumeTimer() override { return S_OK; }
};

HRESULT Trash(const std::wstring& path, std::wstring* receipt) {
  ComPtr<IFileOperation> operation;
  HRESULT hr = CoCreateInstance(CLSID_FileOperation, nullptr, CLSCTX_ALL,
                                IID_PPV_ARGS(&operation));
  if (FAILED(hr)) return hr;
  hr = operation->SetOperationFlags(FOF_ALLOWUNDO | FOF_SILENT | FOF_NOERRORUI |
                                    FOFX_EARLYFAILURE | FOFX_ADDUNDORECORD);
  if (FAILED(hr)) return hr;
  ComPtr<IShellItem> item;
  hr = SHCreateItemFromParsingName(path.c_str(), nullptr, IID_PPV_ARGS(&item));
  if (FAILED(hr)) return hr;
  ComPtr<TrashSink> sink;
  sink.Attach(new TrashSink());
  hr = operation->DeleteItem(item.Get(), sink.Get());
  if (SUCCEEDED(hr)) hr = operation->PerformOperations();
  BOOL aborted = FALSE;
  operation->GetAnyOperationsAborted(&aborted);
  if (FAILED(hr) || aborted || FAILED(sink->outcome)) return FAILED(hr) ? hr : E_ABORT;
  *receipt = sink->recycled;
  return receipt->empty() ? E_FAIL : S_OK;
}

HRESULT Restore(const std::wstring& receipt, const std::wstring& path) {
  if (GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES) return HRESULT_FROM_WIN32(ERROR_FILE_EXISTS);
  const auto slash = path.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return E_INVALIDARG;
  ComPtr<IFileOperation> operation;
  HRESULT hr = CoCreateInstance(CLSID_FileOperation, nullptr, CLSCTX_ALL, IID_PPV_ARGS(&operation));
  if (FAILED(hr)) return hr;
  operation->SetOperationFlags(FOF_SILENT | FOF_NOERRORUI | FOFX_EARLYFAILURE);
  ComPtr<IShellItem> item, parent;
  hr = SHCreateItemFromParsingName(receipt.c_str(), nullptr, IID_PPV_ARGS(&item));
  if (FAILED(hr)) return hr;
  hr = SHCreateItemFromParsingName(path.substr(0, slash).c_str(), nullptr, IID_PPV_ARGS(&parent));
  if (FAILED(hr)) return hr;
  ComPtr<TrashSink> sink; sink.Attach(new TrashSink()); sink->restore_path = path;
  hr = operation->MoveItem(item.Get(), parent.Get(), path.substr(slash + 1).c_str(), sink.Get());
  if (SUCCEEDED(hr)) hr = operation->PerformOperations();
  BOOL aborted = FALSE; operation->GetAnyOperationsAborted(&aborted);
  return FAILED(hr) ? hr : (aborted ? E_ABORT : sink->outcome);
}

// A standard IDataObject carries every selected path encoded
// as Unicode CF_HDROP, including selections spanning different directories.
class FileDragSource final : public IDropSource {
 public:
  LONG refs = 1;
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** out) override {
    if (!out) return E_POINTER;
    *out = nullptr;
    if (id != IID_IUnknown && id != IID_IDropSource) return E_NOINTERFACE;
    *out = static_cast<IDropSource*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs); }
  ULONG STDMETHODCALLTYPE Release() override {
    const auto count = InterlockedDecrement(&refs);
    if (!count) delete this;
    return count;
  }
  HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL escape, DWORD keys) override {
    if (escape) return DRAGDROP_S_CANCEL;
    return (keys & MK_LBUTTON) ? S_OK : DRAGDROP_S_DROP;
  }
  HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD) override {
    return DRAGDROP_S_USEDEFAULTCURSORS;
  }
};

// Expose only the real CF_HDROP payload. An empty shell ID-list format must
// not shadow the file list when the receiver prefers shell-item formats.
class FileDragDataObject final : public IDataObject {
 public:
  explicit FileDragDataObject(std::vector<wchar_t> names) : names_(std::move(names)) {}
  LONG refs = 1;
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** out) override {
    if (!out) return E_POINTER;
    *out = nullptr;
    if (id != IID_IUnknown && id != IID_IDataObject) return E_NOINTERFACE;
    *out = static_cast<IDataObject*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs); }
  ULONG STDMETHODCALLTYPE Release() override {
    const auto count = InterlockedDecrement(&refs);
    if (!count) delete this;
    return count;
  }
  HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC* format) override {
    if (!format) return E_POINTER;
    return format->cfFormat == CF_HDROP && (format->tymed & TYMED_HGLOBAL) &&
        format->dwAspect == DVASPECT_CONTENT && format->lindex == -1 ? S_OK : DV_E_FORMATETC;
  }
  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* format, STGMEDIUM* medium) override {
    if (!medium) return E_POINTER;
    *medium = {};
    const HRESULT supported = QueryGetData(format);
    if (FAILED(supported)) return supported;
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT,
        sizeof(DROPFILES) + names_.size() * sizeof(wchar_t));
    auto* drop = memory ? static_cast<DROPFILES*>(GlobalLock(memory)) : nullptr;
    if (!drop) {
      if (memory) GlobalFree(memory);
      return E_OUTOFMEMORY;
    }
    drop->pFiles = sizeof(DROPFILES);
    drop->fWide = TRUE;
    std::memcpy(reinterpret_cast<char*>(drop) + sizeof(DROPFILES), names_.data(), names_.size() * sizeof(wchar_t));
    GlobalUnlock(memory);
    medium->tymed = TYMED_HGLOBAL;
    medium->hGlobal = memory;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC*, STGMEDIUM*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC*, FORMATETC* output) override {
    if (!output) return E_POINTER;
    output->ptd = nullptr;
    return DATA_S_SAMEFORMATETC;
  }
  HRESULT STDMETHODCALLTYPE SetData(FORMATETC*, STGMEDIUM*, BOOL) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD direction, IEnumFORMATETC** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (direction != DATADIR_GET) return E_NOTIMPL;
    FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    return SHCreateStdEnumFmtEtc(1, &format, result);
  }
  HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC*, DWORD, IAdviseSink*, DWORD*) override { return OLE_E_ADVISENOTSUPPORTED; }
  HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override { return OLE_E_ADVISENOTSUPPORTED; }
  HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA**) override { return OLE_E_ADVISENOTSUPPORTED; }
 private:
  const std::vector<wchar_t> names_;
};

HRESULT StartFileDrag(const EncodableMap* args, bool* accepted) {
  *accepted = false;
  if (!args) return E_INVALIDARG;
  const auto found = args->find(EncodableValue("paths"));
  if (found == args->end()) return E_INVALIDARG;
  const auto* paths = std::get_if<EncodableList>(&found->second);
  if (!paths || paths->empty()) return E_INVALIDARG;
  std::vector<wchar_t> names;
  for (const auto& value : *paths) {
    const auto* path = std::get_if<std::string>(&value);
    if (!path || path->find('\0') != std::string::npos) return E_INVALIDARG;
    const auto wide = Wide(*path);
    if (wide.empty() || !std::filesystem::path(wide).is_absolute() ||
        GetFileAttributesW(wide.c_str()) == INVALID_FILE_ATTRIBUTES) return E_INVALIDARG;
    names.insert(names.end(), wide.begin(), wide.end());
    names.push_back(L'\0');
  }
  names.push_back(L'\0');
  if (!(GetAsyncKeyState(VK_LBUTTON) & 0x8000)) return S_OK;
  const HRESULT initialized = OleInitialize(nullptr);
  if (FAILED(initialized)) return initialized;
  HRESULT outcome;
  {
    ComPtr<FileDragDataObject> data;
    data.Attach(new FileDragDataObject(std::move(names)));
    ComPtr<FileDragSource> source;
    source.Attach(new FileDragSource());
    DWORD effect = DROPEFFECT_NONE;
    ReleaseCapture();
    outcome = DoDragDrop(data.Get(), source.Get(), DROPEFFECT_COPY, &effect);
    *accepted = outcome == DRAGDROP_S_DROP && (effect & DROPEFFECT_COPY) != 0;
    if (outcome == DRAGDROP_S_CANCEL || outcome == DRAGDROP_S_DROP) outcome = S_OK;
  }
  OleUninitialize();
  return outcome;
}

bool WriteClipboard(const EncodableMap* args) {
  if (!args) return false;
  const auto found = args->find(EncodableValue("paths"));
  if (found == args->end()) return false;
  const auto* paths = std::get_if<EncodableList>(&found->second);
  if (!paths || paths->empty()) return false;
  std::vector<wchar_t> names;
  for (const auto& value : *paths) {
    const auto* path = std::get_if<std::string>(&value);
    if (!path || path->empty()) return false;
    const auto wide = Wide(*path);
    names.insert(names.end(), wide.begin(), wide.end()); names.push_back(L'\0');
  }
  names.push_back(L'\0');
  HGLOBAL data = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, sizeof(DROPFILES) + names.size() * sizeof(wchar_t));
  if (!data) return false;
  auto* drop = static_cast<DROPFILES*>(GlobalLock(data));
  if (!drop) { GlobalFree(data); return false; }
  drop->pFiles = sizeof(DROPFILES); drop->fWide = TRUE;
  std::memcpy(reinterpret_cast<char*>(drop) + sizeof(DROPFILES), names.data(), names.size() * sizeof(wchar_t));
  GlobalUnlock(data);
  if (!OpenClipboard(GetActiveWindow())) { GlobalFree(data); return false; }
  EmptyClipboard();
  if (!SetClipboardData(CF_HDROP, data)) { CloseClipboard(); GlobalFree(data); return false; }
  HGLOBAL effect = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
  if (effect) {
    auto* effect_data = static_cast<DWORD*>(GlobalLock(effect));
    const auto cut = args->find(EncodableValue("cut"));
    const bool moving = cut != args->end() && std::get_if<bool>(&cut->second) && std::get<bool>(cut->second);
    if (effect_data) { *effect_data = moving ? DROPEFFECT_MOVE : DROPEFFECT_COPY; GlobalUnlock(effect); }
    if (!effect_data || !SetClipboardData(RegisterClipboardFormatW(L"Preferred DropEffect"), effect)) GlobalFree(effect);
  }
  CloseClipboard(); return true;
}

EncodableValue ReadClipboard() {
  if (!OpenClipboard(GetActiveWindow())) return EncodableValue();
  EncodableList paths;
  const auto drop = static_cast<HDROP>(GetClipboardData(CF_HDROP));
  if (drop) {
    const UINT count = DragQueryFileW(drop, 0xffffffff, nullptr, 0);
    for (UINT i = 0; i < count; ++i) {
      const UINT n = DragQueryFileW(drop, i, nullptr, 0);
      std::vector<wchar_t> path(n + 1);
      DragQueryFileW(drop, i, path.data(), n + 1);
      paths.emplace_back(Utf8FromUtf16(path.data()));
    }
  }
  bool cut = false;
  const auto effect = GetClipboardData(RegisterClipboardFormatW(L"Preferred DropEffect"));
  if (effect) {
    const auto* value = static_cast<DWORD*>(GlobalLock(effect));
    if (value) { cut = (*value & DROPEFFECT_MOVE) != 0; GlobalUnlock(effect); }
  }
  CloseClipboard();
  return EncodableValue(EncodableMap{{EncodableValue("paths"), EncodableValue(paths)}, {EncodableValue("cut"), EncodableValue(cut)}});
}
}  // namespace

void RegisterFileOperations(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "crispcloud/files", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    if (call.method_name() == "startFileDrag") {
      bool accepted = false;
      const HRESULT status = StartFileDrag(args, &accepted);
      if (FAILED(status)) result->Error("file_drag_failed", "Windows could not start the complete file drag.");
      else result->Success(EncodableValue(accepted));
      return;
    }
    if (call.method_name() == "readClipboard") { result->Success(ReadClipboard()); return; }
    if (call.method_name() == "writeClipboard") {
      if (WriteClipboard(args)) result->Success(); else result->Error("clipboard_failed", "The system file clipboard is unavailable.");
      return;
    }
    const std::string path = StringArg(args, call.method_name() == "trash" ? "path" : "originalPath");
    if (path.empty()) { result->Error("invalid_path", "A file path is required."); return; }
    if (call.method_name() == "trash") {
      std::wstring receipt;
      const HRESULT hr = Trash(Wide(path), &receipt);
      if (FAILED(hr)) result->Error("trash_failed", "Windows could not recycle this item. No permanent-delete fallback was requested.");
      else result->Success(EncodableValue(EncodableMap{{EncodableValue("originalPath"), EncodableValue(path)}, {EncodableValue("trashId"), EncodableValue(Utf8FromUtf16(receipt.c_str()))}}));
    } else if (call.method_name() == "restoreTrash") {
      const HRESULT hr = Restore(Wide(StringArg(args, "trashId")), Wide(path));
      if (FAILED(hr)) result->Error("restore_failed", "The original path is occupied or the recycled item is unavailable."); else result->Success();
    } else result->NotImplemented();
  });
}
