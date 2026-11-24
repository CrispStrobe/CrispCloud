#include "pdf_text.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <algorithm>
#include <cstring>
#include <memory>
#include <string>
#include <variant>
#include <vector>

namespace {

template <typename T>
T Resolve(HMODULE library, const char* name) {
  // PDFium is already loaded by pdfx. Resolve its public API without searching
  // the working directory or installing a second DLL.
  const FARPROC address = GetProcAddress(library, name);
  static_assert(sizeof(address) == sizeof(T));
  T function = nullptr;
  std::memcpy(&function, &address, sizeof(function));
  return function;
}

struct PdfiumText {
  explicit PdfiumText(HMODULE library)
      : init(Resolve<void(WINAPI*)()>(library, "FPDF_InitLibrary")),
        open(Resolve<void*(WINAPI*)(const void*, size_t, const char*)>(
            library, "FPDF_LoadMemDocument64")),
        close(Resolve<void(WINAPI*)(void*)>(library, "FPDF_CloseDocument")),
        page_count(Resolve<int(WINAPI*)(void*)>(library, "FPDF_GetPageCount")),
        load_page(Resolve<void*(WINAPI*)(void*, int)>(library, "FPDF_LoadPage")),
        close_page(Resolve<void(WINAPI*)(void*)>(library, "FPDF_ClosePage")),
        load_text(Resolve<void*(WINAPI*)(void*)>(library, "FPDFText_LoadPage")),
        close_text(Resolve<void(WINAPI*)(void*)>(library, "FPDFText_ClosePage")),
        count(Resolve<int(WINAPI*)(void*)>(library, "FPDFText_CountChars")),
        get(Resolve<int(WINAPI*)(void*, int, int, unsigned short*)>(
            library, "FPDFText_GetText")) {}

  void(WINAPI* init)();
  void*(WINAPI* open)(const void*, size_t, const char*);
  void(WINAPI* close)(void*);
  int(WINAPI* page_count)(void*);
  void*(WINAPI* load_page)(void*, int);
  void(WINAPI* close_page)(void*);
  void*(WINAPI* load_text)(void*);
  void(WINAPI* close_text)(void*);
  int(WINAPI* count)(void*);
  int(WINAPI* get)(void*, int, int, unsigned short*);

  bool Available() const {
    return init && open && close && page_count && load_page && close_page &&
           load_text && close_text && count && get;
  }
};

using Value = flutter::EncodableValue;
using Result = flutter::MethodResult<Value>;

void ExtractText(const std::vector<uint8_t>& bytes, Result& result) {
  constexpr size_t kMaxInput = 64 * 1024 * 1024;
  constexpr int kMaxTextUnits = 2 * 1024 * 1024;
  constexpr int kMaxPages = 4096;
  if (bytes.empty() || bytes.size() > kMaxInput) {
    result.Error("pdf_limit", "PDF input is empty or too large");
    return;
  }
  const HMODULE library = GetModuleHandleW(L"pdfium.dll");
  if (!library) {
    result.Error("pdf_unavailable", "PDFium is unavailable");
    return;
  }
  const PdfiumText pdf(library);
  if (!pdf.Available()) {
    result.Error("pdf_unavailable", "PDFium text functions are unavailable");
    return;
  }
  // Flutter dispatches this handler and pdfx on the Windows platform thread.
  // Close our handles before returning without tearing down shared PDFium state.
  pdf.init();
  const std::unique_ptr<void, decltype(pdf.close)> doc(
      pdf.open(bytes.data(), bytes.size(), nullptr), pdf.close);
  if (!doc) {
    result.Error("pdf_open", "PDFium could not open this document");
    return;
  }
  std::wstring text;
  const int pages = std::min(pdf.page_count(doc.get()), kMaxPages);
  for (int index = 0;
       index < pages && text.size() + 5 < static_cast<size_t>(kMaxTextUnits);
       ++index) {
    const std::unique_ptr<void, decltype(pdf.close_page)> page(
        pdf.load_page(doc.get(), index), pdf.close_page);
    if (!page) continue;
    const std::unique_ptr<void, decltype(pdf.close_text)> content(
        pdf.load_text(page.get()), pdf.close_text);
    if (!content) continue;
    const int remaining = kMaxTextUnits - static_cast<int>(text.size()) - 4;
    const int count = std::min(pdf.count(content.get()), remaining / 2);
    if (count <= 0) continue;
    std::vector<unsigned short> units(static_cast<size_t>(count) * 2 + 1);
    const int length = pdf.get(content.get(), 0, count, units.data());
    if (length <= 1 || static_cast<size_t>(length) > units.size()) continue;
    if (!text.empty()) text.append(L"\n\n");
    for (int i = 0; i < length - 1; ++i) {
      if (units[i] != 0) text.push_back(static_cast<wchar_t>(units[i]));
    }
  }
  if (text.empty()) {
    result.Success(Value(std::string()));
    return;
  }
  const int length = static_cast<int>(text.size());
  const int utf8_length =
      WideCharToMultiByte(CP_UTF8, 0, text.data(), length, nullptr, 0, nullptr,
                          nullptr);
  if (utf8_length <= 0) {
    result.Error("pdf_text", "Could not decode PDF text");
    return;
  }
  std::string utf8(static_cast<size_t>(utf8_length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), length, utf8.data(), utf8_length,
                      nullptr, nullptr);
  result.Success(Value(std::move(utf8)));
}

}  // namespace

void RegisterPdfText(flutter::BinaryMessenger* messenger) {
  flutter::MethodChannel<Value> channel(
      messenger, "crispcloud/pdf_text",
      &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler(
      [](const flutter::MethodCall<Value>& call,
         std::unique_ptr<Result> result) {
        if (call.method_name() != "extractText") {
          result->NotImplemented();
          return;
        }
        const auto* bytes = call.arguments()
                                ? std::get_if<std::vector<uint8_t>>(call.arguments())
                                : nullptr;
        if (!bytes) {
          result->Error("pdf_input", "Expected PDF bytes");
          return;
        }
        ExtractText(*bytes, *result);
      });
}
