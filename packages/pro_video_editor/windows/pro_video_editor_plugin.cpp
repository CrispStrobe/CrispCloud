#include "pro_video_editor_plugin.h"

#include <windows.h>
#include <VersionHelpers.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <comdef.h>
#include <shlwapi.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include <sstream>
#include <vector>
#include <wincodec.h> 
#include <initguid.h>
#include "src/video_metadata.h"
#include "src/thumbnail_generator.h"

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "shlwapi.lib")

namespace pro_video_editor {

	void ProVideoEditorPlugin::RegisterWithRegistrar(
		flutter::PluginRegistrarWindows* registrar) {
		auto channel =
			std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
				registrar->messenger(), "pro_video_editor",
				&flutter::StandardMethodCodec::GetInstance());

		auto plugin = std::make_unique<ProVideoEditorPlugin>();

		channel->SetMethodCallHandler(
			[plugin_pointer = plugin.get()](const auto& call, auto result) {
				plugin_pointer->HandleMethodCall(call, std::move(result));
			});

		registrar->AddPlugin(std::move(plugin));
	}

	ProVideoEditorPlugin::ProVideoEditorPlugin() {
		// Initialize Media Foundation
		HRESULT hr = MFStartup(MF_VERSION);
		if (FAILED(hr)) {
			OutputDebugString(L"Failed to initialize Media Foundation");
		}
	}

	ProVideoEditorPlugin::~ProVideoEditorPlugin() {
		MFShutdown();
	}

	void ProVideoEditorPlugin::HandleMethodCall(
		const flutter::MethodCall<flutter::EncodableValue>& method_call,
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
		if (method_call.method_name().compare("getPlatformVersion") == 0) {
			std::ostringstream version_stream;
			version_stream << "Windows ";
			if (IsWindows10OrGreater()) {
				version_stream << "10+";
			}
			else if (IsWindows8OrGreater()) {
				version_stream << "8";
			}
			else if (IsWindows7OrGreater()) {
				version_stream << "7";
			}
			result->Success(flutter::EncodableValue(version_stream.str()));
		}
		else if (method_call.method_name().compare("getMetadata") == 0) {
			const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
			if (!args) {
				result->Error("InvalidArgument", "Expected a map");
				return;
			}

			pro_video_editor::HandleGetMetadata(*args, std::move(result));
		}
		else if (method_call.method_name().compare("createVideoThumbnails") == 0) {
			result->NotImplemented();
		/* 	const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
			if (!args) {
				result->Error("InvalidArgument", "Expected a map");
				return;
			}

			pro_video_editor::HandleGenerateThumbnails(*args, std::move(result)); */
		}
		else {
			result->NotImplemented();
		}
	}

}  // namespace pro_video_editor