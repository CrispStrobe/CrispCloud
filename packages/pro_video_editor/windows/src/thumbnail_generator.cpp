#include "thumbnail_generator.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>
#include <iostream>
#include <chrono>
#include <filesystem>
#include <shellapi.h>
#include <future>

namespace fs = std::filesystem;

namespace pro_video_editor {
/* 
	std::wstring GenerateTempFilename(const std::wstring& prefix, const std::wstring& extension) {
		wchar_t tempPath[MAX_PATH];
		GetTempPathW(MAX_PATH, tempPath);

		SYSTEMTIME time;
		GetSystemTime(&time);

		wchar_t filename[MAX_PATH];
		swprintf_s(filename, MAX_PATH, L"%s_%04d%02d%02d%02d%02d%02d%03d%s",
			prefix.c_str(),
			time.wYear, time.wMonth, time.wDay,
			time.wHour, time.wMinute, time.wSecond, time.wMilliseconds,
			extension.c_str());

		return std::wstring(tempPath) + filename;
	}

	bool WriteBytesToFile(const std::wstring& path, const std::vector<uint8_t>& bytes) {
		std::ofstream out(path, std::ios::binary);
		if (!out.is_open()) return false;
		out.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
		return true;
	}

	// Helper: get absolute path to ffmpeg.exe located in 'windows/bin/ffmpeg.exe'
	std::wstring GetFFmpegPath() {
		wchar_t exePath[MAX_PATH];
		GetModuleFileNameW(nullptr, exePath, MAX_PATH);

		// exePath = .../x64/runner/Debug/runner.exe
		std::filesystem::path exeDir = std::filesystem::path(exePath).parent_path(); // → Debug/
		std::filesystem::path x64Dir = exeDir.parent_path().parent_path();           // → x64/

		// Actual location of ffmpeg.exe (from CMake copy)
		std::filesystem::path ffmpegPath = x64Dir / "plugins" / "pro_video_editor_plugin" / "ffmpeg.exe";

		OutputDebugStringW((L"[FFmpeg Path] " + ffmpegPath.wstring() + L"\n").c_str());
		return ffmpegPath.wstring();
	}

	std::string WStringToUtf8(const std::wstring& wstr) {
		if (wstr.empty()) return {};

		int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.length(),
			nullptr, 0, nullptr, nullptr);
		std::string strTo(size_needed, 0);
		WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.length(),
			&strTo[0], size_needed, nullptr, nullptr);
		return strTo;
	}

	void HandleGenerateThumbnails(
		const flutter::EncodableMap& args,
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

		// Extract parameters
		const auto* videoBytes = std::get_if<std::vector<uint8_t>>(&args.at(flutter::EncodableValue("videoBytes")));
		const auto* timestampsList = std::get_if<flutter::EncodableList>(&args.at(flutter::EncodableValue("timestamps")));
		const auto* formatStr = std::get_if<std::string>(&args.at(flutter::EncodableValue("thumbnailFormat")));
		const auto* extensionStr = std::get_if<std::string>(&args.at(flutter::EncodableValue("extension")));
		const auto* width = std::get_if<double>(&args.at(flutter::EncodableValue("imageWidth")));


		if (!videoBytes || !timestampsList || !formatStr || !extensionStr || !width) {
			result->Error("InvalidArgument", "Missing required parameters");
			return;
		}
		int roundedWidth = static_cast<int>(std::round(*width));

		std::wstring videoExt(extensionStr->begin(), extensionStr->end());
		if (videoExt[0] != L'.') videoExt = L"." + videoExt;
		std::wstring imageExt(formatStr->begin(), formatStr->end());
		if (imageExt[0] != L'.') imageExt = L"." + imageExt;

		// Write video to temp file
		std::wstring tempVideoPath = GenerateTempFilename(L"video_temp", videoExt);
		if (!WriteBytesToFile(tempVideoPath, *videoBytes)) {
			result->Error("FileError", "Failed to write temp video file");
			return;
		}

		std::wstring ffmpegPath = GetFFmpegPath();

		OutputDebugStringW((L"[FFmpeg Path] " + ffmpegPath + L"\n").c_str());
		if (!fs::exists(ffmpegPath)) {
			result->Error("FFmpegError", "ffmpeg.exe not found. Make sure it is in windows/bin/.");
			return;
		}

		std::vector<std::future<void>> futures;
		std::vector<flutter::EncodableValue> thumbnails(timestampsList->size()); // pre-sized

		int index = 0;

		for (const auto& tsValue : *timestampsList) {
			if (!std::holds_alternative<int>(tsValue)) {
				++index;
				continue;
			}

			int currentIndex = index++;
			int64_t tsMs = static_cast<int64_t>(std::get<int>(tsValue));
			double tsSec = tsMs / 1000.0;

			futures.push_back(std::async(std::launch::async, [=, &thumbnails, &ffmpegPath, &tempVideoPath, &imageExt, &roundedWidth]() {
				std::wstringstream timestampStream;
				timestampStream.precision(3);
				timestampStream << std::fixed << tsSec;

				std::wstring tempImagePath = GenerateTempFilename(L"thumb_" + std::to_wstring(currentIndex), imageExt);

				std::wstringstream cmd;
				cmd << L"cmd.exe /C \""
					<< L"\"" << ffmpegPath << L"\""
					<< L" -ss " << timestampStream.str()
					<< L" -i \"" << tempVideoPath << L"\""
					<< L" -vframes 1 -vf scale=" << roundedWidth << L":-2 "
					<< L"\"" << tempImagePath << L"\""
					<< L"\"";

				std::wstring cmdStr = cmd.str();
				wprintf(L"[FFmpeg] Executing: %s\n", cmdStr.c_str());

				int retCode = _wsystem(cmdStr.c_str());

				if (retCode != 0) {
					std::wstringstream err;
					err << L"[FFmpeg] Exit code: " << retCode << L"\n";
					err << L"[FFmpeg] Timestamp: " << tsSec << L" seconds\n";
					err << L"[FFmpeg] Temp video path: " << tempVideoPath << L"\n";
					err << L"[FFmpeg] Command:\n" << cmdStr << L"\n";
					OutputDebugStringW(err.str().c_str());
				}
				else if (!fs::exists(tempImagePath)) {
					std::wstringstream err;
					err << L"FFmpeg succeeded but output image not found: " << tempImagePath;
					OutputDebugStringW(err.str().c_str());
				}
				else {
					std::ifstream in(tempImagePath, std::ios::binary);
					std::vector<uint8_t> imageBytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());

					thumbnails[currentIndex] = flutter::EncodableValue(imageBytes);
				}

				DeleteFileW(tempImagePath.c_str());
				}));
		}

		// Wait for all to complete
		for (auto& fut : futures) {
			fut.get();
		}


		DeleteFileW(tempVideoPath.c_str());
		result->Success(thumbnails);
	} */

}  // namespace pro_video_editor
