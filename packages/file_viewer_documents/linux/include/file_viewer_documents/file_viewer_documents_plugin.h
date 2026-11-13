// SPDX-License-Identifier: MIT
// Adapted from CrispStrobe/crisperbooks 32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52.
// Modified for CrispCloud document hosting; see HOST_PROVENANCE.json and retained MIT notice.
#ifndef FLUTTER_PLUGIN_FILE_VIEWER_DOCUMENTS_READER_PLUGIN_H_
#define FLUTTER_PLUGIN_FILE_VIEWER_DOCUMENTS_READER_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

FLUTTER_PLUGIN_EXPORT void file_viewer_documents_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif
