// src/video_metadata.h
#pragma once

#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>

namespace pro_video_editor {

	void HandleGetMetadata(
		const flutter::EncodableMap& args,
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

}  // namespace pro_video_editor
