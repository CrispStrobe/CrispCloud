#include "file_drag_data.h"
#include <wrl/client.h>
#include <cstdlib>
#include <iostream>

void Require(bool condition, const char* message) {
  if (!condition) { std::cerr << message << "\n"; std::exit(1); }
}

int main() {
  Require(SUCCEEDED(OleInitialize(nullptr)), "OLE initialization failed");
  {
    const std::vector<std::wstring> paths = {
      LR"(C:\selected files\first.txt)",
      L"D:\\other folder\\\u65e5\u672c\u8a9e-\U0001f600.flac",
      LR"(\\server\share\selected directory)",
    };
    Microsoft::WRL::ComPtr<crisp_file_drag::FileDragDataObject> object;
    object.Attach(new crisp_file_drag::FileDragDataObject(paths));
    FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    Require(object->QueryGetData(&format) == S_OK, "File-drop format missing");
    STGMEDIUM medium = {};
    Require(object->GetData(&format, &medium) == S_OK, "File-drop payload unavailable");
    const auto drop = static_cast<HDROP>(medium.hGlobal);
    Require(DragQueryFileW(drop, 0xffffffff, nullptr, 0) == paths.size(), "Receiver lost part of the selection");
    for (UINT i = 0; i < paths.size(); ++i) {
      const UINT length = DragQueryFileW(drop, i, nullptr, 0);
      std::vector<wchar_t> value(length + 1);
      Require(DragQueryFileW(drop, i, value.data(), length + 1) == length, "Receiver could not read a path");
      Require(std::wstring(value.data()) == paths[i], "Receiver changed a Unicode path");
    }
    ReleaseStgMedium(&medium);
    Microsoft::WRL::ComPtr<IEnumFORMATETC> formats;
    Require(object->EnumFormatEtc(DATADIR_GET, &formats) == S_OK, "Cannot enumerate formats");
    FORMATETC announced = {};
    ULONG count = 0;
    Require(formats->Next(1, &announced, &count) == S_OK && count == 1 && announced.cfFormat == CF_HDROP,
        "Receiver was offered an empty or unrelated shell format");
    Require(formats->Next(1, &announced, &count) == S_FALSE, "Unexpected extra format");
    FORMATETC text = {CF_UNICODETEXT, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    Require(object->QueryGetData(&text) == DV_E_FORMATETC, "File drop became plain text");
  }
  OleUninitialize();
  std::cout << "Windows receiver recovered every selected Unicode file and directory.\n";
  return 0;
}
