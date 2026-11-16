//
// Generated file. Do not edit.
// This file is generated from template in file `flutter_tools/lib/src/flutter_plugins.dart`.
//

// @dart = 3.13

import 'dart:io'; // flutter_ignore: dart_io_import.
import 'package:cryptography_flutter/cryptography_flutter.dart' as cryptography_flutter;
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:file_selector_android/file_selector_android.dart' as file_selector_android;
import 'package:flutter_inappwebview_android/flutter_inappwebview_android.dart' as flutter_inappwebview_android;
import 'package:local_auth_android/local_auth_android.dart' as local_auth_android;
import 'package:path_provider_android/path_provider_android.dart' as path_provider_android;
import 'package:shared_preferences_android/shared_preferences_android.dart' as shared_preferences_android;
import 'package:url_launcher_android/url_launcher_android.dart' as url_launcher_android;
import 'package:video_player_android/video_player_android.dart' as video_player_android;
import 'package:cryptography_flutter/cryptography_flutter.dart' as cryptography_flutter;
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:file_selector_ios/file_selector_ios.dart' as file_selector_ios;
import 'package:flutter_inappwebview_ios/flutter_inappwebview_ios.dart' as flutter_inappwebview_ios;
import 'package:local_auth_darwin/local_auth_darwin.dart' as local_auth_darwin;
import 'package:path_provider_foundation/path_provider_foundation.dart' as path_provider_foundation;
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart' as shared_preferences_foundation;
import 'package:url_launcher_ios/url_launcher_ios.dart' as url_launcher_ios;
import 'package:video_player_avfoundation/video_player_avfoundation.dart' as video_player_avfoundation;
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:file_selector_linux/file_selector_linux.dart' as file_selector_linux;
import 'package:flutter_local_notifications_linux/flutter_local_notifications_linux.dart' as flutter_local_notifications_linux;
import 'package:package_info_plus/package_info_plus.dart' as package_info_plus;
import 'package:path_provider_linux/path_provider_linux.dart' as path_provider_linux;
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:shared_preferences_linux/shared_preferences_linux.dart' as shared_preferences_linux;
import 'package:url_launcher_linux/url_launcher_linux.dart' as url_launcher_linux;
import 'package:cryptography_flutter/cryptography_flutter.dart' as cryptography_flutter;
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:file_selector_macos/file_selector_macos.dart' as file_selector_macos;
import 'package:flutter_inappwebview_macos/flutter_inappwebview_macos.dart' as flutter_inappwebview_macos;
import 'package:local_auth_darwin/local_auth_darwin.dart' as local_auth_darwin;
import 'package:path_provider_foundation/path_provider_foundation.dart' as path_provider_foundation;
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart' as shared_preferences_foundation;
import 'package:url_launcher_macos/url_launcher_macos.dart' as url_launcher_macos;
import 'package:video_player_avfoundation/video_player_avfoundation.dart' as video_player_avfoundation;
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:file_selector_windows/file_selector_windows.dart' as file_selector_windows;
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart' as flutter_inappwebview_windows;
import 'package:flutter_secure_storage_windows/flutter_secure_storage_windows.dart' as flutter_secure_storage_windows;
import 'package:local_auth_windows/local_auth_windows.dart' as local_auth_windows;
import 'package:package_info_plus/package_info_plus.dart' as package_info_plus;
import 'package:path_provider_windows/path_provider_windows.dart' as path_provider_windows;
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:shared_preferences_windows/shared_preferences_windows.dart' as shared_preferences_windows;
import 'package:url_launcher_windows/url_launcher_windows.dart' as url_launcher_windows;

@pragma('vm:entry-point')
class _PluginRegistrant {

  @pragma('vm:entry-point')
  static void register() {
    if (Platform.isAndroid) {
      try {
        cryptography_flutter.FlutterCryptography.registerWith();
      } catch (err) {
        print(
          '`cryptography_flutter` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        file_picker.FilePickerIO.registerWith();
      } catch (err) {
        print(
          '`file_picker` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        file_selector_android.FileSelectorAndroid.registerWith();
      } catch (err) {
        print(
          '`file_selector_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        flutter_inappwebview_android.AndroidInAppWebViewPlatform.registerWith();
      } catch (err) {
        print(
          '`flutter_inappwebview_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        local_auth_android.LocalAuthAndroid.registerWith();
      } catch (err) {
        print(
          '`local_auth_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        path_provider_android.PathProviderAndroid.registerWith();
      } catch (err) {
        print(
          '`path_provider_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        shared_preferences_android.SharedPreferencesAndroid.registerWith();
      } catch (err) {
        print(
          '`shared_preferences_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        url_launcher_android.UrlLauncherAndroid.registerWith();
      } catch (err) {
        print(
          '`url_launcher_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        video_player_android.AndroidVideoPlayer.registerWith();
      } catch (err) {
        print(
          '`video_player_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

    } else if (Platform.isIOS) {
      try {
        cryptography_flutter.FlutterCryptography.registerWith();
      } catch (err) {
        print(
          '`cryptography_flutter` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        file_picker.FilePickerIO.registerWith();
      } catch (err) {
        print(
          '`file_picker` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        file_selector_ios.FileSelectorIOS.registerWith();
      } catch (err) {
        print(
          '`file_selector_ios` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        flutter_inappwebview_ios.IOSInAppWebViewPlatform.registerWith();
      } catch (err) {
        print(
          '`flutter_inappwebview_ios` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        local_auth_darwin.LocalAuthDarwin.registerWith();
      } catch (err) {
        print(
          '`local_auth_darwin` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        path_provider_foundation.PathProviderFoundation.registerWith();
      } catch (err) {
        print(
          '`path_provider_foundation` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        shared_preferences_foundation.SharedPreferencesFoundation.registerWith();
      } catch (err) {
        print(
          '`shared_preferences_foundation` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        url_launcher_ios.UrlLauncherIOS.registerWith();
      } catch (err) {
        print(
          '`url_launcher_ios` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        video_player_avfoundation.AVFoundationVideoPlayer.registerWith();
      } catch (err) {
        print(
          '`video_player_avfoundation` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

    } else if (Platform.isLinux) {
      try {
        file_picker.FilePickerLinux.registerWith();
      } catch (err) {
        print(
          '`file_picker` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        file_selector_linux.FileSelectorLinux.registerWith();
      } catch (err) {
        print(
          '`file_selector_linux` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        flutter_local_notifications_linux.LinuxFlutterLocalNotificationsPlugin.registerWith();
      } catch (err) {
        print(
          '`flutter_local_notifications_linux` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        package_info_plus.PackageInfoPlusLinuxPlugin.registerWith();
      } catch (err) {
        print(
          '`package_info_plus` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        path_provider_linux.PathProviderLinux.registerWith();
      } catch (err) {
        print(
          '`path_provider_linux` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        share_plus.SharePlusLinuxPlugin.registerWith();
      } catch (err) {
        print(
          '`share_plus` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        shared_preferences_linux.SharedPreferencesLinux.registerWith();
      } catch (err) {
        print(
          '`shared_preferences_linux` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        url_launcher_linux.UrlLauncherLinux.registerWith();
      } catch (err) {
        print(
          '`url_launcher_linux` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

    } else if (Platform.isMacOS) {
      try {
        cryptography_flutter.FlutterCryptography.registerWith();
      } catch (err) {
        print(
          '`cryptography_flutter` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        file_picker.FilePickerMacOS.registerWith();
      } catch (err) {
        print(
          '`file_picker` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        file_selector_macos.FileSelectorMacOS.registerWith();
      } catch (err) {
        print(
          '`file_selector_macos` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        flutter_inappwebview_macos.MacOSInAppWebViewPlatform.registerWith();
      } catch (err) {
        print(
          '`flutter_inappwebview_macos` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        local_auth_darwin.LocalAuthDarwin.registerWith();
      } catch (err) {
        print(
          '`local_auth_darwin` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        path_provider_foundation.PathProviderFoundation.registerWith();
      } catch (err) {
        print(
          '`path_provider_foundation` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        shared_preferences_foundation.SharedPreferencesFoundation.registerWith();
      } catch (err) {
        print(
          '`shared_preferences_foundation` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        url_launcher_macos.UrlLauncherMacOS.registerWith();
      } catch (err) {
        print(
          '`url_launcher_macos` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        video_player_avfoundation.AVFoundationVideoPlayer.registerWith();
      } catch (err) {
        print(
          '`video_player_avfoundation` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

    } else if (Platform.isWindows) {
      try {
        file_picker.FilePickerWindows.registerWith();
      } catch (err) {
        print(
          '`file_picker` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        file_selector_windows.FileSelectorWindows.registerWith();
      } catch (err) {
        print(
          '`file_selector_windows` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        flutter_inappwebview_windows.WindowsInAppWebViewPlatform.registerWith();
      } catch (err) {
        print(
          '`flutter_inappwebview_windows` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        flutter_secure_storage_windows.FlutterSecureStorageWindows.registerWith();
      } catch (err) {
        print(
          '`flutter_secure_storage_windows` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        local_auth_windows.LocalAuthWindows.registerWith();
      } catch (err) {
        print(
          '`local_auth_windows` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        package_info_plus.PackageInfoPlusWindowsPlugin.registerWith();
      } catch (err) {
        print(
          '`package_info_plus` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        path_provider_windows.PathProviderWindows.registerWith();
      } catch (err) {
        print(
          '`path_provider_windows` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        share_plus.SharePlusWindowsPlugin.registerWith();
      } catch (err) {
        print(
          '`share_plus` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        shared_preferences_windows.SharedPreferencesWindows.registerWith();
      } catch (err) {
        print(
          '`shared_preferences_windows` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        url_launcher_windows.UrlLauncherWindows.registerWith();
      } catch (err) {
        print(
          '`url_launcher_windows` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

    }
  }
}
