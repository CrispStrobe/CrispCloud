#include "../../linux/reader_surface_size.h"

#include <cassert>
#include <iostream>

int main() {
  int cases = 0;
  for (const double width : {1.0, 720.0, 3000.0, 3840.0, 8192.0}) {
    for (const double height : {1.0, 500.0, 2000.0, 2160.0, 8192.0}) {
      for (const double scale : {0.25, 1.0, 1.5, 2.0, 4.0, 8.0}) {
        for (const int gtk_scale : {1, 2, 3, 4}) {
          const auto size = crisp_ebook::BoundedSurfaceSize(
              width, height, scale, gtk_scale);
          assert(size.width >= 1 && size.height >= 1);
          assert(static_cast<int64_t>(size.width) * size.height * gtk_scale *
                     gtk_scale <=
                 crisp_ebook::kMaximumPixels);
          assert(size.input_scale > 0);
          assert(size.input_scale * gtk_scale <= scale);
          ++cases;
        }
      }
    }
  }
  const auto ordinary = crisp_ebook::BoundedSurfaceSize(720, 500, 2, 2);
  assert(ordinary.width == 720 && ordinary.height == 500);
  assert(ordinary.input_scale == 1);
  std::cout << cases << " bounded surface cases passed\n";
}
