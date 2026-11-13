#ifndef FILE_VIEWER_DOCUMENTS_READER_SURFACE_SIZE_H_
#define FILE_VIEWER_DOCUMENTS_READER_SURFACE_SIZE_H_

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace file_viewer_documents {

constexpr int64_t kMaximumPixels = 16 * 1024 * 1024;

struct SurfaceSize {
  int width;
  int height;
  double input_scale;
};

// Inputs have already passed the host's finite/range checks. Rounding down is
// deliberate: rounding both dimensions up after a continuous area cap can
// allocate a frame larger than that cap (for example 3840x2160 at 2x scale).
inline SurfaceSize BoundedSurfaceSize(double width, double height,
                                      double scale, int gtk_scale) {
  const double capped_scale =
      std::min(scale, std::sqrt(kMaximumPixels / (width * height)));
  const double input_scale = capped_scale / std::max(1, gtk_scale);
  return {std::max(1, static_cast<int>(std::floor(width * input_scale))),
          std::max(1, static_cast<int>(std::floor(height * input_scale))),
          input_scale};
}

}  // namespace file_viewer_documents

#endif  // FILE_VIEWER_DOCUMENTS_READER_SURFACE_SIZE_H_
