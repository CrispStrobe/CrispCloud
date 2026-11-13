// SPDX-License-Identifier: MIT
// CrispCloud's narrow policy for explicitly selected XML resources.
#ifndef FILE_VIEWER_DOCUMENTS_XML_FILE_SELECTION_H_
#define FILE_VIEWER_DOCUMENTS_XML_FILE_SELECTION_H_

#include <sys/stat.h>

#include <cstddef>
#include <string>

namespace file_viewer_documents {

enum class XmlResourceKind { kNone, kSchema, kStylesheet };

// Keep this aligned with engines/xml/src/xmlSafety.ts. The JS loader checks the
// size again before reading; this native check never grants an arbitrary path.
constexpr size_t kMaximumXmlResourceBytes = 2 * 1024 * 1024;

// Evaluated only in the trusted main frame. A file input inside a document
// iframe leaves that iframe as the main document's activeElement and fails.
constexpr char kFocusedXmlResourceInput[] = R"JS((() => {
  const input = document.activeElement;
  const tools = document.querySelector('.xml-tools');
  if (!(input instanceof HTMLInputElement) || input.type !== 'file' ||
      input.disabled || input.multiple || input.hasAttribute('webkitdirectory') ||
      !input.isConnected || input.ownerDocument !== document ||
      !tools || input.closest('.xml-tools') !== tools) return '';
  const accept = input.getAttribute('accept');
  return accept === '.xsd' ? 'xsd' : accept === '.xsl,.xslt' ? 'xslt' : '';
})())JS";

inline XmlResourceKind XmlResourceKindFromResult(const std::string& value) {
  if (value == "xsd") return XmlResourceKind::kSchema;
  if (value == "xslt") return XmlResourceKind::kStylesheet;
  return XmlResourceKind::kNone;
}

inline bool IsApprovedXmlResourceFile(XmlResourceKind kind,
                                      const std::string& path) {
  if (kind == XmlResourceKind::kNone || path.empty() || path.front() != '/' ||
      path.size() >= 4096 || path.find('\0') != std::string::npos) return false;
  const auto dot = path.find_last_of('.');
  if (dot == std::string::npos) return false;
  std::string extension = path.substr(dot);
  for (auto& c : extension) {
    if (c >= 'A' && c <= 'Z') c = static_cast<char>(c + ('a' - 'A'));
  }
  if (kind == XmlResourceKind::kSchema ? extension != ".xsd"
                                     : extension != ".xsl" && extension != ".xslt") return false;
  struct stat status = {};
  // Do not return directories, devices, FIFOs or symlinks to WebKit. A regular
  // file may still change afterwards; the XML loader independently rechecks it.
  return lstat(path.c_str(), &status) == 0 && S_ISREG(status.st_mode) &&
         status.st_size >= 0 &&
         static_cast<unsigned long long>(status.st_size) <= kMaximumXmlResourceBytes;
}

}  // namespace file_viewer_documents
#endif  // FILE_VIEWER_DOCUMENTS_XML_FILE_SELECTION_H_
