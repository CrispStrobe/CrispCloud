// SPDX-License-Identifier: MIT
// Adapted from CrispStrobe/crisperbooks 32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52.
// Modified for CrispCloud document hosting; see HOST_PROVENANCE.json and retained MIT notice.
#ifndef FILE_VIEWER_DOCUMENTS_READER_WEBKIT_SETTINGS_H_
#define FILE_VIEWER_DOCUMENTS_READER_WEBKIT_SETTINGS_H_

#include <webkit2/webkit2.h>

namespace file_viewer_documents {

// Shared by the actual reader and its isolated startup helper so readiness is
// exercised with exactly the same view settings, including offscreen painting.
template <typename Api>
void ConfigureWebKitSettings(Api& api, WebKitSettings* settings) {
  api.webkit_settings_set_enable_javascript(settings, TRUE);
  api.webkit_settings_set_javascript_can_open_windows_automatically(settings, FALSE);
  api.webkit_settings_set_allow_file_access_from_file_urls(settings, FALSE);
  api.webkit_settings_set_allow_universal_access_from_file_urls(settings, FALSE);
  api.webkit_settings_set_enable_html5_local_storage(settings, FALSE);
  api.webkit_settings_set_enable_html5_database(settings, FALSE);
  api.webkit_settings_set_enable_page_cache(settings, FALSE);
  api.webkit_settings_set_enable_developer_extras(settings, FALSE);
  api.webkit_settings_set_enable_media_stream(settings, FALSE);
  api.webkit_settings_set_enable_tabs_to_links(settings, TRUE);
  api.webkit_settings_set_media_playback_requires_user_gesture(settings, TRUE);
  api.webkit_settings_set_hardware_acceleration_policy(
      settings, WEBKIT_HARDWARE_ACCELERATION_POLICY_NEVER);
}

}  // namespace file_viewer_documents
#endif  // FILE_VIEWER_DOCUMENTS_READER_WEBKIT_SETTINGS_H_
