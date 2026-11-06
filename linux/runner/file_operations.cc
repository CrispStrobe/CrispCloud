#include "file_operations.h"
#include <gtk/gtk.h>
#include <gio/gio.h>
#include <set>
#include <string>
#include <vector>

namespace {
std::vector<std::string> clipboard_uris;
bool clipboard_cut = false;

const char* string_arg(FlValue* args, const char* key) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return nullptr;
  FlValue* value = fl_value_lookup_string(args, key);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING ? fl_value_get_string(value) : nullptr;
}

void clipboard_get(GtkClipboard*, GtkSelectionData* selection, guint info, gpointer) {
  std::string text;
  if (info == 1) text = clipboard_cut ? "cut\n" : "copy\n";
  if (info == 2) text = clipboard_cut ? "1" : "0";
  else for (const auto& uri : clipboard_uris) text += uri + (info == 1 ? "\n" : "\r\n");
  gtk_selection_data_set(selection, gtk_selection_data_get_target(selection), 8,
                         reinterpret_cast<const guchar*>(text.data()), static_cast<gint>(text.size()));
}
void clipboard_clear(GtkClipboard*, gpointer) { clipboard_uris.clear(); }

bool trash_items(std::set<std::string>* all, const char* original,
                 const std::set<std::string>* before, std::string* found, GError** error) {
  g_autoptr(GFile) root = g_file_new_for_uri("trash:///");
  g_autoptr(GFileEnumerator) list = g_file_enumerate_children(root,
      "standard::name,trash::orig-path", G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, nullptr, error);
  if (!list) return false;
  while (true) {
    g_autoptr(GFileInfo) info = g_file_enumerator_next_file(list, nullptr, error);
    if (!info) break;
    const char* name = g_file_info_get_name(info);
    if (!name) continue;
    g_autoptr(GFile) file = g_file_get_child(root, name);
    g_autofree char* uri = g_file_get_uri(file);
    if (all) all->insert(uri);
    const char* path = g_file_info_get_attribute_byte_string(info, G_FILE_ATTRIBUTE_TRASH_ORIG_PATH);
    if (found && path && original && g_strcmp0(path, original) == 0 &&
        (!before || before->count(uri) == 0)) {
      if (!found->empty()) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED, "The recycled item is ambiguous; restore it from the system Trash.");
        return false;
      }
      *found = uri;
    }
  }
  return !error || !*error;
}

void handle(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const char* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlValue) response = nullptr;
  bool known = true;
  if (g_strcmp0(method, "trash") == 0) {
    const char* path = string_arg(args, "path");
    if (!path || !g_path_is_absolute(path)) {
      g_set_error_literal(&error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT, "An absolute path is required.");
    } else {
      std::set<std::string> before;
      if (trash_items(&before, nullptr, nullptr, nullptr, &error)) {
        g_autoptr(GFile) source = g_file_new_for_path(path);
        if (g_file_trash(source, nullptr, &error)) {
          std::string receipt;
          if (trash_items(nullptr, path, &before, &receipt, &error) && !receipt.empty()) {
            response = fl_value_new_map();
            fl_value_set_string_take(response, "originalPath", fl_value_new_string(path));
            fl_value_set_string_take(response, "trashId", fl_value_new_string(receipt.c_str()));
          } else if (!error) g_set_error_literal(&error, G_IO_ERROR, G_IO_ERROR_FAILED, "The item is in Trash; restore it using the system file manager.");
        }
      }
    }
  } else if (g_strcmp0(method, "restoreTrash") == 0) {
    const char* path = string_arg(args, "originalPath");
    const char* receipt = string_arg(args, "trashId");
    if (!path || !receipt || !g_path_is_absolute(path) || !g_str_has_prefix(receipt, "trash:///")) {
      g_set_error_literal(&error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT, "Invalid trash receipt.");
    } else {
      g_autoptr(GFile) source = g_file_new_for_uri(receipt);
      g_autoptr(GFile) destination = g_file_new_for_path(path);
      // No OVERWRITE flag: an occupied original path is a conflict.
      g_file_move(source, destination, G_FILE_COPY_NOFOLLOW_SYMLINKS,
                  nullptr, nullptr, nullptr, &error);
    }
  } else if (g_strcmp0(method, "writeClipboard") == 0) {
    FlValue* paths = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, "paths") : nullptr;
    if (!paths || fl_value_get_type(paths) != FL_VALUE_TYPE_LIST || fl_value_get_length(paths) == 0) {
      g_set_error_literal(&error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT, "Select local files to copy.");
    } else {
      std::vector<std::string> uris;
      for (size_t i = 0; i < fl_value_get_length(paths); ++i) {
        FlValue* value = fl_value_get_list_value(paths, i);
        if (fl_value_get_type(value) != FL_VALUE_TYPE_STRING) continue;
        g_autofree char* uri = g_filename_to_uri(fl_value_get_string(value), nullptr, &error);
        if (!uri) break;
        uris.emplace_back(uri);
      }
      if (!error) {
        GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
        gtk_clipboard_clear(clipboard);
        clipboard_uris = uris;
        FlValue* cut = fl_value_lookup_string(args, "cut");
        clipboard_cut = cut && fl_value_get_type(cut) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(cut);
        GtkTargetEntry targets[] = {
          {const_cast<gchar*>("text/uri-list"), 0, 0},
          {const_cast<gchar*>("x-special/gnome-copied-files"), 0, 1},
          {const_cast<gchar*>("application/x-kde-cutselection"), 0, 2},
        };
        if (!gtk_clipboard_set_with_data(clipboard, targets, 3, clipboard_get, clipboard_clear, nullptr)) {
          g_set_error_literal(&error, G_IO_ERROR, G_IO_ERROR_FAILED, "The file clipboard is unavailable.");
        } else gtk_clipboard_set_can_store(clipboard, targets, 3);
      }
    }
  } else if (g_strcmp0(method, "readClipboard") == 0) {
    GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    gchar** uris = gtk_clipboard_wait_for_uris(clipboard);
    response = fl_value_new_map();
    FlValue* paths = fl_value_new_list();
    if (uris) {
      for (size_t i = 0; uris[i]; ++i) {
        g_autofree char* path = g_filename_from_uri(uris[i], nullptr, nullptr);
        if (path) fl_value_append_take(paths, fl_value_new_string(path));
      }
      g_strfreev(uris);
    }
    bool cut = false;
    GtkSelectionData* data = gtk_clipboard_wait_for_contents(clipboard, gdk_atom_intern_static_string("x-special/gnome-copied-files"));
    if (data) {
      const auto* bytes = gtk_selection_data_get_data(data);
      cut = gtk_selection_data_get_length(data) >= 4 && bytes && std::string(reinterpret_cast<const char*>(bytes), 4) == "cut\n";
      gtk_selection_data_free(data);
    }
    data = gtk_clipboard_wait_for_contents(clipboard, gdk_atom_intern_static_string("application/x-kde-cutselection"));
    if (data) {
      const auto* bytes = gtk_selection_data_get_data(data);
      if (gtk_selection_data_get_length(data) >= 1 && bytes && bytes[0] == '1') cut = true;
      gtk_selection_data_free(data);
    }
    fl_value_set_string_take(response, "paths", paths);
    fl_value_set_string_take(response, "cut", fl_value_new_bool(cut));
  } else known = false;
  if (!known) fl_method_call_respond_not_implemented(call, nullptr);
  else if (error) fl_method_call_respond_error(call, "file_operation_failed", error->message, nullptr, nullptr);
  else fl_method_call_respond_success(call, response, nullptr);
}
}  // namespace

void register_file_operations(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(messenger, "crispcloud/files", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, handle, nullptr, nullptr);
}
