#ifndef CRISPCLOUD_FILE_DRAG_DATA_H_
#define CRISPCLOUD_FILE_DRAG_DATA_H_
#include <windows.h>
#include <ole2.h>
#include <shellapi.h>
#include <shlobj.h>
#include <cstring>
#include <string>
#include <vector>

namespace crisp_file_drag {
// Expose only the real CF_HDROP payload. An empty shell ID-list format must
// not shadow the file list when the receiver prefers shell-item formats.
class FileDragDataObject final : public IDataObject {
 public:
  explicit FileDragDataObject(const std::vector<std::wstring>& paths) {
    for (const auto& path : paths) {
      names_.insert(names_.end(), path.begin(), path.end());
      names_.push_back(L'\0');
    }
    names_.push_back(L'\0');
  }
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
  std::vector<wchar_t> names_;
};

}  // namespace crisp_file_drag
#endif
