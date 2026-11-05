#include "video_metadata.h"

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <propvarutil.h>
#include <shlwapi.h>
#include <combaseapi.h>
#include <flutter/standard_method_codec.h>
#include <string>
#include <vector>
#include <algorithm>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "shlwapi.lib")

namespace pro_video_editor {

void HandleGetMetadata(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    
    auto itPath = args.find(flutter::EncodableValue("inputPath"));
    if (itPath == args.end()) {
        result->Error("InvalidArgument", "Missing inputPath");
        return;
    }
    const auto* pathStr = std::get_if<std::string>(&itPath->second);
    if (!pathStr) {
        result->Error("InvalidArgument", "Invalid inputPath format");
        return;
    }

    std::wstring inputPath(pathStr->begin(), pathStr->end());

    HANDLE file_handle = CreateFileW(inputPath.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file_handle == INVALID_HANDLE_VALUE) {
        result->Error("FileError", "Failed to open file");
        return;
    }

    LARGE_INTEGER file_size;
    std::string creationDateStr = "";
    if (GetFileSizeEx(file_handle, &file_size)) {
        FILETIME creationTime, accessTime, writeTime;
        if (GetFileTime(file_handle, &creationTime, &accessTime, &writeTime)) {
            SYSTEMTIME stUTC;
            FileTimeToSystemTime(&creationTime, &stUTC);
            char buffer[64];
            sprintf_s(buffer, "%04d-%02d-%02d %02d:%02d:%02d",
                      stUTC.wYear, stUTC.wMonth, stUTC.wDay,
                      stUTC.wHour, stUTC.wMinute, stUTC.wSecond);
            creationDateStr = buffer;
        }
    }
    CloseHandle(file_handle);

    IMFSourceReader* source_reader = nullptr;
    IMFAttributes* attributes = nullptr;
    HRESULT hr = MFCreateAttributes(&attributes, 1);
    if (FAILED(hr)) {
        result->Error("MediaError", "Failed to create attributes");
        return;
    }

    hr = MFCreateSourceReaderFromURL(inputPath.c_str(), attributes, &source_reader);
    attributes->Release();
    if (FAILED(hr)) {
        result->Error("MediaError", "Failed to create source reader");
        return;
    }

    double duration_ms = 0.0;
    UINT32 width = 0, height = 0;
    int rotation = 0;
    int bitrate = 0;

    PROPVARIANT prop;
    PropVariantInit(&prop);

    if (SUCCEEDED(source_reader->GetPresentationAttribute(static_cast<UINT32>(MF_SOURCE_READER_MEDIASOURCE), MF_PD_DURATION, &prop)) && prop.vt == VT_UI8) {
        duration_ms = static_cast<double>(prop.uhVal.QuadPart) / 10'000;
    }
    PropVariantClear(&prop);

    IMFMediaType* media_type = nullptr;
    hr = source_reader->GetNativeMediaType(static_cast<UINT32>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), 0, &media_type);
    if (SUCCEEDED(hr) && media_type) {
        MFGetAttributeSize(media_type, MF_MT_FRAME_SIZE, &width, &height);

        int64_t fileSizeInBits = file_size.QuadPart * 8;
        if (duration_ms > 0.0) {
            bitrate = static_cast<int>(fileSizeInBits / (duration_ms / 1000.0));
        }

        UINT32 rotationVal = 0;
        if (SUCCEEDED(media_type->GetUINT32(MF_MT_VIDEO_ROTATION, &rotationVal))) {
            rotation = static_cast<int>(rotationVal);
        }

        media_type->Release();
    }

    source_reader->Release();

    std::string title = "";
    std::string artist = "";
    std::string author = "";
    std::string album = "";
    std::string albumArtist = "";

    flutter::EncodableMap result_map;
    result_map[flutter::EncodableValue("fileSize")] = flutter::EncodableValue(static_cast<int64_t>(file_size.QuadPart));
    result_map[flutter::EncodableValue("duration")] = flutter::EncodableValue(duration_ms);
    result_map[flutter::EncodableValue("width")] = flutter::EncodableValue(static_cast<int>(width));
    result_map[flutter::EncodableValue("height")] = flutter::EncodableValue(static_cast<int>(height));
    result_map[flutter::EncodableValue("rotation")] = flutter::EncodableValue(rotation);
    result_map[flutter::EncodableValue("bitrate")] = flutter::EncodableValue(bitrate);
    result_map[flutter::EncodableValue("title")] = flutter::EncodableValue(title);
    result_map[flutter::EncodableValue("artist")] = flutter::EncodableValue(artist);
    result_map[flutter::EncodableValue("author")] = flutter::EncodableValue(author);
    result_map[flutter::EncodableValue("album")] = flutter::EncodableValue(album);
    result_map[flutter::EncodableValue("albumArtist")] = flutter::EncodableValue(albumArtist);
    result_map[flutter::EncodableValue("date")] = flutter::EncodableValue(creationDateStr);

    result->Success(flutter::EncodableValue(result_map));
}


}  // namespace pro_video_editor
