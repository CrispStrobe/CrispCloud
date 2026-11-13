// SPDX-License-Identifier: MIT
// Exercise the native chooser's policy against real filesystem objects.
#include "../xml_file_selection.h"

#include <unistd.h>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>

namespace {
size_t checks = 0;
void Check(bool value, const char* description) {
  if (!value) throw std::runtime_error(description);
  ++checks;
}

struct TemporaryDirectory {
  std::filesystem::path path;
  TemporaryDirectory() {
    auto name = (std::filesystem::temp_directory_path() / "crisp-xml-chooser.XXXXXX").string();
    if (mkdtemp(name.data()) == nullptr) throw std::runtime_error("Cannot create test directory");
    path = name;
  }
  ~TemporaryDirectory() {
    std::error_code ignored;
    std::filesystem::remove_all(path, ignored);
  }
};
}  // namespace

int main() {
  using file_viewer_documents::IsApprovedXmlResourceFile;
  using file_viewer_documents::XmlResourceKind;
  using file_viewer_documents::XmlResourceKindFromResult;
  try {
    TemporaryDirectory directory;
    const auto schema = (directory.path / "schema.xsd").string();
    const auto stylesheet = (directory.path / "stylesheet.XsLt").string();
    const auto short_stylesheet = (directory.path / "stylesheet.xsl").string();
    const auto generic_xml = (directory.path / "document.xml").string();
    for (const auto& path : {schema, stylesheet, short_stylesheet, generic_xml}) {
      std::ofstream output(path);
      output << "<root/>";
    }
    Check(XmlResourceKindFromResult("xsd") == XmlResourceKind::kSchema, "schema control rejected");
    Check(XmlResourceKindFromResult("xslt") == XmlResourceKind::kStylesheet, "stylesheet control rejected");
    for (const auto& result : {"", "xml", "XSD", "xsd,xslt", ".xsd", "[object Object]"}) {
      Check(XmlResourceKindFromResult(result) == XmlResourceKind::kNone, "unapproved control accepted");
    }
    Check(IsApprovedXmlResourceFile(XmlResourceKind::kSchema, schema), "local schema rejected");
    Check(IsApprovedXmlResourceFile(XmlResourceKind::kStylesheet, stylesheet), "mixed-case XSLT rejected");
    Check(IsApprovedXmlResourceFile(XmlResourceKind::kStylesheet, short_stylesheet), "XSL rejected");
    Check(!IsApprovedXmlResourceFile(XmlResourceKind::kSchema, stylesheet), "stylesheet accepted as schema");
    Check(!IsApprovedXmlResourceFile(XmlResourceKind::kStylesheet, schema), "schema accepted as stylesheet");
    Check(!IsApprovedXmlResourceFile(XmlResourceKind::kSchema, generic_xml), "general XML capability granted");
    Check(!IsApprovedXmlResourceFile(XmlResourceKind::kNone, schema), "missing control authorization accepted");
    Check(!IsApprovedXmlResourceFile(XmlResourceKind::kSchema, "schema.xsd"), "relative path accepted");
    Check(!IsApprovedXmlResourceFile(XmlResourceKind::kSchema, schema + std::string("\0.xsd", 5)), "NUL path accepted");
    Check(!IsApprovedXmlResourceFile(XmlResourceKind::kSchema, "/" + std::string(4092, 'a') + ".xsd"), "oversized path accepted");
    Check(!IsApprovedXmlResourceFile(XmlResourceKind::kSchema, (directory.path / "missing.xsd").string()), "missing file accepted");

    const auto link = directory.path / "link.xsd";
    std::filesystem::create_symlink(schema, link);
    Check(!IsApprovedXmlResourceFile(XmlResourceKind::kSchema, link.string()), "symlink accepted");
    const auto folder = directory.path / "folder.xsd";
    std::filesystem::create_directory(folder);
    Check(!IsApprovedXmlResourceFile(XmlResourceKind::kSchema, folder.string()), "directory accepted");
    const auto fifo = (directory.path / "pipe.xslt").string();
    Check(mkfifo(fifo.c_str(), 0600) == 0, "Cannot create test FIFO");
    Check(!IsApprovedXmlResourceFile(XmlResourceKind::kStylesheet, fifo), "FIFO accepted");

    const auto limit = file_viewer_documents::kMaximumXmlResourceBytes;
    Check(truncate(schema.c_str(), static_cast<off_t>(limit)) == 0, "Cannot size test file");
    Check(IsApprovedXmlResourceFile(XmlResourceKind::kSchema, schema), "exact byte limit rejected");
    Check(truncate(schema.c_str(), static_cast<off_t>(limit + 1)) == 0, "Cannot resize test file");
    Check(!IsApprovedXmlResourceFile(XmlResourceKind::kSchema, schema), "oversized resource accepted");
    std::cout << "XML resource chooser policy: " << checks << " checks passed\n";
    return EXIT_SUCCESS;
  } catch (const std::exception& error) {
    std::cerr << "XML resource chooser policy failed: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
