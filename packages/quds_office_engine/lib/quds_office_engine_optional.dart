/// Optional APIs that are **not** part of the default engine surface.
///
/// Import this library only when a host needs PPT media package IO.
/// Raster “diagram” visuals stay in `quds_office_engine`; real DrawingML
/// SmartArt (`dgm:`) remains out of scope.
library;

export 'src/optional/pptx_media.dart';
