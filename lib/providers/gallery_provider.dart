import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gallery.dart';
import '../models/panel_side.dart';
import '../services/gallery_catalog_service.dart';
import '../services/log_service.dart';

export '../models/gallery.dart';

final galleryCatalogProvider = ChangeNotifierProvider<GalleryCatalogService>(
  (ref) => GalleryCatalogService(),
);

final galleryQueryProvider = StateProvider.family<GalleryQuery, PanelSide>(
  (ref, side) => const GalleryQuery(),
);

final galleryPreferencesProvider = StateNotifierProvider.family<
    GalleryPreferencesNotifier, GalleryPreferences, PanelSide>(
  (ref, side) => GalleryPreferencesNotifier(side),
);

class GalleryPreferencesNotifier extends StateNotifier<GalleryPreferences> {
  GalleryPreferencesNotifier(this.side) : super(const GalleryPreferences()) {
    _load();
  }

  static const _log = Log('GalleryPreferences');
  final PanelSide side;
  int _generation = 0;
  Future<void> _tail = Future.value();
  String get _key => 'gallery_preferences_${side.name}_v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (mounted && _generation == 0 && raw != null) {
        state = GalleryPreferences.decode(raw);
      }
    } catch (error) {
      _log.warn('Unable to restore gallery preferences', error);
    }
  }

  void update(GalleryPreferences value) {
    _generation++;
    state = value;
    _tail = _tail.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.encode());
    }).catchError((Object error) {
      _log.warn('Unable to save gallery preferences', error);
    });
  }
}
