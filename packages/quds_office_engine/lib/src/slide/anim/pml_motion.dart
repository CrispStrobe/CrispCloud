import 'dart:math' as math;

import '../model/pml_presentation.dart';

/// Slide-to-slide transition, matching the common PowerPoint gallery.
enum PmlTransitionKind {
  none,
  morph,
  fade,
  fadeThroughBlack,
  cut,
  push,
  wipe,
  split,
  uncover,
  cover,
  dissolve,
  checkerboard,
  blinds,
  clock,
  shapeCircle,
  shapeDiamond,
  shapePlus,
  newsflash,
  zoom,
  flash,
  comb,
  strips,
  randomBars,
  reveal,
  gallery,
  doors,
}

/// Enum PmlTransitionDir.
enum PmlTransitionDir {
  left,
  right,
  up,
  down,
  horizontal,
  vertical,
  inward,
  outward,
}

/// Enum PmlAnimClass.
enum PmlAnimClass { entrance, emphasis, exit, motion }

/// Enum PmlAnimPreset.
enum PmlAnimPreset {
  appear,
  fade,
  flyIn,
  floatIn,
  peekIn,
  riseUp,
  split,
  wipe,
  grow,
  growTurn,
  zoom,
  swivel,
  bounce,
  pulse,
  spin,
  teeter,
  growShrink,
  disappear,
  fadeOut,
  flyOut,
  shrink,
  pathLine,
  pathArc,
}

/// Enum PmlAnimTrigger.
enum PmlAnimTrigger { onClick, withPrevious, afterPrevious }

/// Class PmlSlideTransition.
class PmlSlideTransition {
  /// PmlSlideTransition API.
  const PmlSlideTransition({
    this.kind = PmlTransitionKind.none,
    this.direction = PmlTransitionDir.left,
    this.durationMs = 700,
    this.advanceOnClick = true,
    this.advanceAfterMs,
  });

  /// kind API.
  final PmlTransitionKind kind;

  /// direction API.
  final PmlTransitionDir direction;

  /// durationMs API.
  final int durationMs;

  /// advanceOnClick API.
  final bool advanceOnClick;

  /// advanceAfterMs API.
  final int? advanceAfterMs;

  /// isNone API.
  bool get isNone => kind == PmlTransitionKind.none;

  /// copyWith API.
  PmlSlideTransition copyWith({
    PmlTransitionKind? kind,
    PmlTransitionDir? direction,
    int? durationMs,
    bool? advanceOnClick,
    int? advanceAfterMs,
    bool clearAdvanceAfter = false,
  }) {
    return PmlSlideTransition(
      kind: kind ?? this.kind,
      direction: direction ?? this.direction,
      durationMs: durationMs ?? this.durationMs,
      advanceOnClick: advanceOnClick ?? this.advanceOnClick,
      advanceAfterMs: clearAdvanceAfter
          ? null
          : (advanceAfterMs ?? this.advanceAfterMs),
    );
  }
}

/// Class PmlShapeAnimation.
class PmlShapeAnimation {
  /// PmlShapeAnimation API.
  PmlShapeAnimation({
    required this.shapeId,
    required this.preset,
    this.trigger = PmlAnimTrigger.onClick,
    this.direction = PmlTransitionDir.left,
    this.durationMs = 500,
    this.delayMs = 0,
    this.order = 0,
  });

  /// shapeId API.
  int shapeId;

  /// preset API.
  PmlAnimPreset preset;

  /// trigger API.
  PmlAnimTrigger trigger;

  /// direction API.
  PmlTransitionDir direction;

  /// durationMs API.
  int durationMs;

  /// delayMs API.
  int delayMs;

  /// order API.
  int order;

  /// category API.
  PmlAnimClass get category => switch (preset) {
    PmlAnimPreset.appear ||
    PmlAnimPreset.fade ||
    PmlAnimPreset.flyIn ||
    PmlAnimPreset.floatIn ||
    PmlAnimPreset.peekIn ||
    PmlAnimPreset.riseUp ||
    PmlAnimPreset.split ||
    PmlAnimPreset.wipe ||
    PmlAnimPreset.grow ||
    PmlAnimPreset.growTurn ||
    PmlAnimPreset.zoom ||
    PmlAnimPreset.swivel ||
    PmlAnimPreset.bounce => PmlAnimClass.entrance,
    PmlAnimPreset.pulse ||
    PmlAnimPreset.spin ||
    PmlAnimPreset.teeter ||
    PmlAnimPreset.growShrink => PmlAnimClass.emphasis,
    PmlAnimPreset.disappear ||
    PmlAnimPreset.fadeOut ||
    PmlAnimPreset.flyOut ||
    PmlAnimPreset.shrink => PmlAnimClass.exit,
    PmlAnimPreset.pathLine || PmlAnimPreset.pathArc => PmlAnimClass.motion,
  };

  /// copyWith API.
  PmlShapeAnimation copyWith({
    int? shapeId,
    PmlAnimPreset? preset,
    PmlAnimTrigger? trigger,
    PmlTransitionDir? direction,
    int? durationMs,
    int? delayMs,
    int? order,
  }) {
    return PmlShapeAnimation(
      shapeId: shapeId ?? this.shapeId,
      preset: preset ?? this.preset,
      trigger: trigger ?? this.trigger,
      direction: direction ?? this.direction,
      durationMs: durationMs ?? this.durationMs,
      delayMs: delayMs ?? this.delayMs,
      order: order ?? this.order,
    );
  }
}

/// Class PmlMotionCatalog.
class PmlMotionCatalog {
  /// transitions API.
  static const List<PmlTransitionKind> transitions = <PmlTransitionKind>[
    PmlTransitionKind.none,
    PmlTransitionKind.morph,
    PmlTransitionKind.fade,
    PmlTransitionKind.fadeThroughBlack,
    PmlTransitionKind.cut,
    PmlTransitionKind.push,
    PmlTransitionKind.wipe,
    PmlTransitionKind.split,
    PmlTransitionKind.uncover,
    PmlTransitionKind.cover,
    PmlTransitionKind.dissolve,
    PmlTransitionKind.checkerboard,
    PmlTransitionKind.blinds,
    PmlTransitionKind.clock,
    PmlTransitionKind.shapeCircle,
    PmlTransitionKind.shapeDiamond,
    PmlTransitionKind.shapePlus,
    PmlTransitionKind.newsflash,
    PmlTransitionKind.zoom,
    PmlTransitionKind.flash,
    PmlTransitionKind.comb,
    PmlTransitionKind.strips,
    PmlTransitionKind.randomBars,
    PmlTransitionKind.reveal,
    PmlTransitionKind.gallery,
    PmlTransitionKind.doors,
  ];

  /// entrance API.
  static const List<PmlAnimPreset> entrance = <PmlAnimPreset>[
    PmlAnimPreset.appear,
    PmlAnimPreset.fade,
    PmlAnimPreset.flyIn,
    PmlAnimPreset.floatIn,
    PmlAnimPreset.peekIn,
    PmlAnimPreset.riseUp,
    PmlAnimPreset.split,
    PmlAnimPreset.wipe,
    PmlAnimPreset.grow,
    PmlAnimPreset.growTurn,
    PmlAnimPreset.zoom,
    PmlAnimPreset.swivel,
    PmlAnimPreset.bounce,
  ];

  /// emphasis API.
  static const List<PmlAnimPreset> emphasis = <PmlAnimPreset>[
    PmlAnimPreset.pulse,
    PmlAnimPreset.spin,
    PmlAnimPreset.teeter,
    PmlAnimPreset.growShrink,
  ];

  /// exit API.
  static const List<PmlAnimPreset> exit = <PmlAnimPreset>[
    PmlAnimPreset.disappear,
    PmlAnimPreset.fadeOut,
    PmlAnimPreset.flyOut,
    PmlAnimPreset.shrink,
  ];

  /// motion API.
  static const List<PmlAnimPreset> motion = <PmlAnimPreset>[
    PmlAnimPreset.pathLine,
    PmlAnimPreset.pathArc,
  ];

  /// usesDirection API.
  static bool usesDirection(PmlTransitionKind kind) {
    return switch (kind) {
      PmlTransitionKind.push ||
      PmlTransitionKind.wipe ||
      PmlTransitionKind.split ||
      PmlTransitionKind.uncover ||
      PmlTransitionKind.cover ||
      PmlTransitionKind.blinds ||
      PmlTransitionKind.comb ||
      PmlTransitionKind.strips ||
      PmlTransitionKind.randomBars ||
      PmlTransitionKind.reveal ||
      PmlTransitionKind.doors => true,
      _ => false,
    };
  }

  /// animUsesDirection API.
  static bool animUsesDirection(PmlAnimPreset preset) {
    return preset == PmlAnimPreset.flyIn ||
        preset == PmlAnimPreset.floatIn ||
        preset == PmlAnimPreset.peekIn ||
        preset == PmlAnimPreset.wipe ||
        preset == PmlAnimPreset.split ||
        preset == PmlAnimPreset.flyOut ||
        preset == PmlAnimPreset.pathLine ||
        preset == PmlAnimPreset.pathArc;
  }

  /// transitionLabel API.
  static String transitionLabel(
    PmlTransitionKind kind, {
    required bool arabic,
  }) {
    return switch (kind) {
      PmlTransitionKind.none => arabic ? 'بدون' : 'None',
      PmlTransitionKind.morph => arabic ? 'تحوّل' : 'Morph',
      PmlTransitionKind.fade => arabic ? 'تلاشٍ' : 'Fade',
      PmlTransitionKind.fadeThroughBlack =>
        arabic ? 'تلاشٍ عبر الأسود' : 'Fade through black',
      PmlTransitionKind.cut => arabic ? 'قطع' : 'Cut',
      PmlTransitionKind.push => arabic ? 'دفع' : 'Push',
      PmlTransitionKind.wipe => arabic ? 'مسح' : 'Wipe',
      PmlTransitionKind.split => arabic ? 'انقسام' : 'Split',
      PmlTransitionKind.uncover => arabic ? 'كشف' : 'Uncover',
      PmlTransitionKind.cover => arabic ? 'تغطية' : 'Cover',
      PmlTransitionKind.dissolve => arabic ? 'ذوبان' : 'Dissolve',
      PmlTransitionKind.checkerboard => arabic ? 'رقعة شطرنج' : 'Checkerboard',
      PmlTransitionKind.blinds => arabic ? 'ستائر' : 'Blinds',
      PmlTransitionKind.clock => arabic ? 'ساعة' : 'Clock',
      PmlTransitionKind.shapeCircle => arabic ? 'دائرة' : 'Circle',
      PmlTransitionKind.shapeDiamond => arabic ? 'معين' : 'Diamond',
      PmlTransitionKind.shapePlus => arabic ? 'زائد' : 'Plus',
      PmlTransitionKind.newsflash => arabic ? 'خبر عاجل' : 'Newsflash',
      PmlTransitionKind.zoom => arabic ? 'تكبير' : 'Zoom',
      PmlTransitionKind.flash => arabic ? 'وميض' : 'Flash',
      PmlTransitionKind.comb => arabic ? 'مشط' : 'Comb',
      PmlTransitionKind.strips => arabic ? 'شرائط' : 'Strips',
      PmlTransitionKind.randomBars => arabic ? 'أشرطة عشوائية' : 'Random bars',
      PmlTransitionKind.reveal => arabic ? 'إظهار' : 'Reveal',
      PmlTransitionKind.gallery => arabic ? 'معرض' : 'Gallery',
      PmlTransitionKind.doors => arabic ? 'أبواب' : 'Doors',
    };
  }

  /// animLabel API.
  static String animLabel(PmlAnimPreset preset, {required bool arabic}) {
    return switch (preset) {
      PmlAnimPreset.appear => arabic ? 'ظهور' : 'Appear',
      PmlAnimPreset.fade => arabic ? 'تلاشٍ' : 'Fade',
      PmlAnimPreset.flyIn => arabic ? 'طيران للداخل' : 'Fly in',
      PmlAnimPreset.floatIn => arabic ? 'طفو للداخل' : 'Float in',
      PmlAnimPreset.peekIn => arabic ? 'إطلالة' : 'Peek in',
      PmlAnimPreset.riseUp => arabic ? 'صعود' : 'Rise up',
      PmlAnimPreset.split => arabic ? 'انقسام' : 'Split',
      PmlAnimPreset.wipe => arabic ? 'مسح' : 'Wipe',
      PmlAnimPreset.grow => arabic ? 'نمو' : 'Grow',
      PmlAnimPreset.growTurn => arabic ? 'نمو ودوران' : 'Grow & turn',
      PmlAnimPreset.zoom => arabic ? 'تكبير' : 'Zoom',
      PmlAnimPreset.swivel => arabic ? 'دوران ثلاثي' : 'Swivel',
      PmlAnimPreset.bounce => arabic ? 'ارتداد' : 'Bounce',
      PmlAnimPreset.pulse => arabic ? 'نبض' : 'Pulse',
      PmlAnimPreset.spin => arabic ? 'دوران' : 'Spin',
      PmlAnimPreset.teeter => arabic ? 'تأرجح' : 'Teeter',
      PmlAnimPreset.growShrink => arabic ? 'تكبير/تصغير' : 'Grow/Shrink',
      PmlAnimPreset.disappear => arabic ? 'اختفاء' : 'Disappear',
      PmlAnimPreset.fadeOut => arabic ? 'تلاشٍ للخارج' : 'Fade out',
      PmlAnimPreset.flyOut => arabic ? 'طيران للخارج' : 'Fly out',
      PmlAnimPreset.shrink => arabic ? 'انكماش' : 'Shrink',
      PmlAnimPreset.pathLine => arabic ? 'مسار مستقيم' : 'Line path',
      PmlAnimPreset.pathArc => arabic ? 'مسار قوسي' : 'Arc path',
    };
  }

  /// classLabel API.
  static String classLabel(PmlAnimClass cls, {required bool arabic}) {
    return switch (cls) {
      PmlAnimClass.entrance => arabic ? 'دخول' : 'Entrance',
      PmlAnimClass.emphasis => arabic ? 'تأكيد' : 'Emphasis',
      PmlAnimClass.exit => arabic ? 'خروج' : 'Exit',
      PmlAnimClass.motion => arabic ? 'مسار' : 'Motion',
    };
  }
}

/// Class PmlAnimSample.
class PmlAnimSample {
  /// PmlAnimSample API.
  const PmlAnimSample({
    this.visible = true,
    this.opacity = 1,
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.rotationDeg = 0,
    this.reveal = 1,
    this.wipeClip = false,
    this.splitClip = false,
    this.clipDir = PmlTransitionDir.left,
  });

  /// hidden API.
  static const PmlAnimSample hidden = PmlAnimSample(visible: false, opacity: 0);

  /// identity API.
  static const PmlAnimSample identity = PmlAnimSample();

  /// visible API.
  final bool visible;

  /// opacity API.
  final double opacity;

  /// dx API.
  final double dx;

  /// dy API.
  final double dy;

  /// scale API.
  final double scale;

  /// rotationDeg API.
  final double rotationDeg;

  /// reveal API.
  final double reveal;

  /// wipeClip API.
  final bool wipeClip;

  /// splitClip API.
  final bool splitClip;

  /// clipDir API.
  final PmlTransitionDir clipDir;

  /// usesClip API.
  bool get usesClip => wipeClip || splitClip;
}

class _TimedAnim {
  _TimedAnim(this.anim, this.startMs);

  /// anim API.
  final PmlShapeAnimation anim;

  /// startMs API.
  final int startMs;

  /// endMs API.
  int get endMs => startMs + anim.durationMs;
}

class _AnimGroup {
  _AnimGroup({required this.waitForClick, required this.items});

  /// waitForClick API.
  final bool waitForClick;

  /// items API.
  final List<_TimedAnim> items;

  /// spanMs API.
  int get spanMs {
    var max = 0;
    for (final _TimedAnim item in items) {
      if (item.endMs > max) {
        max = item.endMs;
      }
    }
    return max;
  }
}

/// Click-driven slideshow clock for transitions and shape animations.
class PmlSlideShow {
  /// PmlSlideShow API.
  PmlSlideShow(this.presentation);

  /// presentation API.
  final PmlPresentation presentation;

  /// slideIndex API.
  var slideIndex = 0;

  /// presenting API.
  var presenting = false;

  /// finished API.
  var finished = false;
  var _transitioning = false;
  var _transitionElapsed = 0;
  var _slideElapsed = 0;
  var _clickIndex = 0;
  var _previewOnly = false;
  var _endAfterTransition = false;
  var _autoPlayClicks = false;
  int? _onlyAnimationIndex;
  var _holdElapsed = 0;
  var _holdingPreview = false;
  var _outgoingIndex = 0;
  var _transitionReverse = false;
  var _rewinding = false;
  var _rewindElapsed = 0;
  var _rewindDurationMs = 1;
  var _rewindGroupIndex = -1;
  var _rewindFromMs = 0;
  final List<int> _clickAt = <int>[];
  List<_AnimGroup> _groups = const <_AnimGroup>[];
  List<PmlShapeAnimation> _samplingAnims = const <PmlShapeAnimation>[];

  /// previewHoldMs API.
  static const int previewHoldMs = 350;

  /// isPreview API.
  bool get isPreview => _previewOnly;

  /// isTransitioning API.
  bool get isTransitioning => _transitioning;

  /// isTransitionReverse API.
  bool get isTransitionReverse => _transitioning && _transitionReverse;

  /// isRewinding API.
  bool get isRewinding => _rewinding;

  /// playingTransition API.
  PmlSlideTransition? get playingTransition =>
      _transitioning ? currentSlide.transition : null;

  /// transitionProgress API.
  double get transitionProgress {
    if (!_transitioning) {
      return 1;
    }
    final PmlSlideTransition t = currentSlide.transition;
    if (_isInstantTransition(t)) {
      return _transitionReverse ? 0 : 1;
    }
    final double raw = (_transitionElapsed / t.durationMs).clamp(0.0, 1.0);
    return _transitionReverse ? 1.0 - raw : raw;
  }

  /// currentSlide API.
  PmlSlide get currentSlide {
    if (presentation.slides.isEmpty) {
      return PmlSlide(id: 256);
    }
    return presentation.slides[slideIndex.clamp(
      0,
      presentation.slides.length - 1,
    )];
  }

  /// outgoingSlide API.
  PmlSlide? get outgoingSlide {
    if (!_transitioning) {
      return null;
    }
    if (presentation.slides.isEmpty) {
      return PmlSlide(id: 0);
    }
    return presentation.slides[_outgoingIndex.clamp(
      0,
      presentation.slides.length - 1,
    )];
  }

  /// start API.
  void start({
    int from = 0,
    bool withTransition = false,
    bool previewOnly = false,
    bool endAfterTransition = false,
    bool autoPlayClicks = false,
    int? onlyAnimationIndex,
  }) {
    presenting = true;
    finished = false;
    _previewOnly = previewOnly;
    _endAfterTransition = endAfterTransition;
    _autoPlayClicks = autoPlayClicks;
    _onlyAnimationIndex = onlyAnimationIndex;
    _holdElapsed = 0;
    _holdingPreview = false;
    slideIndex = from.clamp(0, math.max(0, presentation.slides.length - 1));
    _enterSlide(playTransition: withTransition);
  }

  /// stop API.
  void stop() {
    presenting = false;
    _transitioning = false;
    _transitionReverse = false;
    finished = false;
    _clearRewind();
  }

  /// next API.
  bool next() {
    if (!presenting || finished) {
      return false;
    }
    if (_rewinding) {
      _resumeFromRewind();
      return true;
    }
    if (_transitioning) {
      if (_transitionReverse) {
        _flipTransitionDirection();
        return true;
      }
      _finishTransition();
      return true;
    }
    if (_clickIndex < _groups.length) {
      _fireClick(_slideElapsed);
      return true;
    }
    final int? dest = presentation.visibleIndexAfter(slideIndex);
    if (!_previewOnly && dest != null) {
      _outgoingIndex = slideIndex;
      slideIndex = dest;
      _enterSlide(playTransition: true);
      return true;
    }
    finished = true;
    presenting = false;
    return false;
  }

  /// previous API.
  bool previous() {
    if (!presenting) {
      return false;
    }
    finished = false;
    if (_rewinding) {
      _finishRewind();
      return true;
    }
    if (_transitioning) {
      if (_transitionReverse) {
        _finishTransition();
        return true;
      }
      _startReverseTransition(_outgoingIndex);
      return true;
    }
    if (_clickIndex > 0) {
      _startRewindLastGroup();
      return true;
    }
    final int? dest = presentation.visibleIndexAfter(slideIndex, direction: -1);
    if (dest != null) {
      _startReverseTransition(dest);
      return true;
    }
    return false;
  }

  void _endPreview() {
    finished = true;
    presenting = false;
    _holdingPreview = false;
  }

  /// elapse API.
  void elapse(int ms) {
    if (!presenting || finished || ms <= 0) {
      return;
    }
    if (_holdingPreview) {
      _holdElapsed += ms;
      if (_holdElapsed >= previewHoldMs) {
        _endPreview();
      }
      return;
    }
    if (_rewinding) {
      _rewindElapsed += ms;
      if (_rewindElapsed >= _rewindDurationMs) {
        _finishRewind();
      }
      return;
    }
    if (_transitioning) {
      _transitionElapsed += ms;
      final int duration = math.max(1, currentSlide.transition.durationMs);
      if (_transitionElapsed >= duration) {
        _finishTransition();
      }
      return;
    }
    _slideElapsed += ms;
    _autoFireReadyGroups();
    if (_previewOnly &&
        !_transitioning &&
        _clickIndex >= _groups.length &&
        _slideElapsed >= _contentSpan()) {
      _holdingPreview = true;
      _holdElapsed = 0;
      return;
    }
    final int? after = currentSlide.transition.advanceAfterMs;
    if (after != null &&
        after > 0 &&
        !_previewOnly &&
        _clickIndex >= _groups.length &&
        _slideElapsed >= after + _contentSpan()) {
      next();
    }
  }

  /// sample API.
  PmlAnimSample sample(int shapeId) {
    if (!presenting) {
      return PmlAnimSample.identity;
    }
    if (_transitioning) {
      if (_previewOnly && _endAfterTransition) {
        return PmlAnimSample.identity;
      }
      if (_transitionReverse) {
        return _sampleAt(shapeId, _slideElapsed);
      }
      final bool hasEntrance = _samplingAnims.any(
        (PmlShapeAnimation a) =>
            a.shapeId == shapeId && a.category == PmlAnimClass.entrance,
      );
      return hasEntrance ? PmlAnimSample.hidden : PmlAnimSample.identity;
    }
    return _sampleAt(shapeId, _slideElapsed);
  }

  List<PmlShapeAnimation> _animsForSlide() {
    final int? only = _onlyAnimationIndex;
    if (only != null && only >= 0 && only < currentSlide.animations.length) {
      return <PmlShapeAnimation>[currentSlide.animations[only]];
    }
    return currentSlide.animations;
  }

  /// atEnd API.
  void _enterSlide({required bool playTransition, bool atEnd = false}) {
    _samplingAnims = _animsForSlide();
    _groups = _buildGroups(_samplingAnims);
    if (_autoPlayClicks) {
      _groups = <_AnimGroup>[
        for (final _AnimGroup g in _groups)
          _AnimGroup(waitForClick: false, items: g.items),
      ];
    }
    _clickAt.clear();
    _clickIndex = 0;
    _slideElapsed = 0;
    _transitionElapsed = 0;
    _holdElapsed = 0;
    _holdingPreview = false;
    _transitionReverse = false;
    _clearRewind();
    if (atEnd) {
      _transitioning = false;
      _armAllClicks();
      return;
    }
    final PmlSlideTransition t = currentSlide.transition;
    _transitioning = playTransition && !_isInstantTransition(t);
    if (!_transitioning) {
      _autoFireReadyGroups();
    }
  }

  void _armAllClicks() {
    var at = 0;
    for (final _AnimGroup group in _groups) {
      _clickAt.add(at);
      _clickIndex++;
      at += math.max(1, group.spanMs);
    }
    _slideElapsed = at;
  }

  void _startRewindLastGroup() {
    final int group = _clickIndex - 1;
    if (group < 0 || group >= _groups.length) {
      _popClick();
      return;
    }
    final int start = group < _clickAt.length ? _clickAt[group] : _slideElapsed;
    final int span = math.max(1, _groups[group].spanMs);
    final bool finished = _slideElapsed >= start + span;
    final double progress = finished
        ? 1.0
        : ((_slideElapsed - start) / span).clamp(0.0, 1.0);
    if (progress <= 0.01) {
      _popClick();
      return;
    }
    _rewinding = true;
    _rewindGroupIndex = group;
    _rewindElapsed = 0;
    _rewindFromMs = _slideElapsed;
    _rewindDurationMs = math.max(80, (span * progress).round());
  }

  void _resumeFromRewind() {
    if (!_rewinding) {
      return;
    }
    final int group = _rewindGroupIndex;
    if (group >= 0 && group < _groups.length) {
      final int groupStart = group < _clickAt.length ? _clickAt[group] : 0;
      final int span = math.max(1, _groups[group].spanMs);
      final double rewindP = (_rewindElapsed / _rewindDurationMs).clamp(
        0.0,
        1.0,
      );
      final int localNow = (_rewindFromMs - groupStart).clamp(0, span);
      _slideElapsed = groupStart + (localNow * (1.0 - rewindP)).round();
    }
    _clearRewind();
  }

  void _finishRewind() {
    if (!_rewinding) {
      return;
    }
    _clearRewind();
    _popClick();
  }

  void _popClick() {
    if (_clickIndex > 0) {
      _clickIndex--;
    }
    if (_clickAt.isNotEmpty) {
      _clickAt.removeLast();
    }
    if (_clickAt.isEmpty) {
      _slideElapsed = 0;
      return;
    }
    final int last = _clickAt.length - 1;
    _slideElapsed = _clickAt[last] + math.max(1, _groups[last].spanMs);
  }

  void _clearRewind() {
    _rewinding = false;
    _rewindElapsed = 0;
    _rewindDurationMs = 1;
    _rewindGroupIndex = -1;
    _rewindFromMs = 0;
  }

  static bool _isInstantTransition(PmlSlideTransition t) {
    return t.isNone || t.kind == PmlTransitionKind.cut || t.durationMs <= 0;
  }

  void _flipTransitionDirection() {
    final int duration = math.max(1, currentSlide.transition.durationMs);
    _transitionElapsed = (duration - _transitionElapsed).clamp(0, duration);
    _transitionReverse = !_transitionReverse;
  }

  void _startReverseTransition(int dest) {
    final PmlSlideTransition t = currentSlide.transition;
    if (_isInstantTransition(t)) {
      slideIndex = dest;
      _enterSlide(playTransition: false, atEnd: true);
      return;
    }
    if (_transitioning && !_transitionReverse) {
      _flipTransitionDirection();
      return;
    }
    _outgoingIndex = dest;
    _transitionElapsed = 0;
    _transitionReverse = true;
    _transitioning = true;
  }

  void _finishTransition() {
    final bool wasReverse = _transitionReverse;
    final int dest = _outgoingIndex;
    _transitioning = false;
    _transitionElapsed = 0;
    _transitionReverse = false;
    if (wasReverse) {
      slideIndex = dest;
      _enterSlide(playTransition: false, atEnd: true);
      return;
    }
    if (_endAfterTransition && _previewOnly) {
      _holdingPreview = true;
      _holdElapsed = 0;
      return;
    }
    _autoFireReadyGroups();
  }

  void _autoFireReadyGroups() {
    while (_clickIndex < _groups.length && !_groups[_clickIndex].waitForClick) {
      if (_clickIndex > 0) {
        final int prevStart = _clickAt[_clickIndex - 1];
        final int prevEnd = prevStart + _groups[_clickIndex - 1].spanMs;
        if (_slideElapsed < prevEnd) {
          break;
        }
      }
      _fireClick(_slideElapsed);
    }
  }

  void _fireClick(int atMs) {
    _clickAt.add(atMs);
    _clickIndex++;
  }

  int _contentSpan() {
    var end = 0;
    var cursor = 0;
    for (int i = 0; i < _clickAt.length && i < _groups.length; i++) {
      final int start = _clickAt[i];
      final int span = _groups[i].spanMs;
      final int groupEnd = start + span;
      if (groupEnd > end) {
        end = groupEnd;
      }
      cursor = groupEnd;
    }
    if (cursor > end) {
      end = cursor;
    }
    return end;
  }

  PmlAnimSample _sampleAt(int shapeId, int nowMs) {
    final List<PmlShapeAnimation> mine = <PmlShapeAnimation>[
      for (final PmlShapeAnimation a in _samplingAnims)
        if (a.shapeId == shapeId) a,
    ];
    final bool hasEntrance = mine.any(
      (PmlShapeAnimation a) => a.category == PmlAnimClass.entrance,
    );
    var visible = !hasEntrance;
    var opacity = 1.0;
    var dx = 0.0;
    var dy = 0.0;
    var scale = 1.0;
    var rot = 0.0;
    var wipeClip = false;
    var splitClip = false;
    var reveal = 1.0;
    var clipDir = PmlTransitionDir.left;
    for (int g = 0; g < _groups.length; g++) {
      if (g >= _clickIndex) {
        continue;
      }
      final int groupStart = g < _clickAt.length ? _clickAt[g] : nowMs;
      final int clock = _clockForGroup(g, groupStart, nowMs);
      for (final _TimedAnim item in _groups[g].items) {
        if (item.anim.shapeId != shapeId) {
          continue;
        }
        final int start = groupStart + item.startMs;
        final int dur = item.anim.durationMs <= 0 ? 1 : item.anim.durationMs;
        final bool started = clock >= start;
        final bool done = clock >= start + item.anim.durationMs;
        final double t = done
            ? 1
            : started
            ? _ease(((clock - start) / dur).clamp(0.0, 1.0))
            : 0;
        final PmlAnimSample part = _applyPreset(
          item.anim,
          t,
          started: started,
          done: done,
        );
        if (!started) {
          continue;
        }
        if (item.anim.category == PmlAnimClass.entrance) {
          visible = part.visible;
          opacity = part.opacity;
          dx += part.dx;
          dy += part.dy;
          scale *= part.scale;
          rot += part.rotationDeg;
        } else if (item.anim.category == PmlAnimClass.exit) {
          visible = part.visible;
          opacity *= part.opacity;
          dx += part.dx;
          dy += part.dy;
          scale *= part.scale;
          rot += part.rotationDeg;
        } else {
          visible = visible && part.visible;
          opacity *= part.opacity;
          dx += part.dx;
          dy += part.dy;
          scale *= part.scale;
          rot += part.rotationDeg;
        }
        if (part.usesClip) {
          wipeClip = part.wipeClip;
          splitClip = part.splitClip;
          reveal = part.reveal;
          clipDir = part.clipDir;
        }
      }
    }
    if (!visible) {
      return PmlAnimSample.hidden;
    }
    return PmlAnimSample(
      visible: true,
      opacity: opacity.clamp(0, 1),
      dx: dx,
      dy: dy,
      scale: scale,
      rotationDeg: rot,
      wipeClip: wipeClip,
      splitClip: splitClip,
      reveal: reveal,
      clipDir: clipDir,
    );
  }

  int _clockForGroup(int group, int groupStart, int nowMs) {
    if (!_rewinding || group != _rewindGroupIndex) {
      return nowMs;
    }
    final int span = math.max(1, _groups[group].spanMs);
    final double rewindP = (_rewindElapsed / _rewindDurationMs).clamp(0.0, 1.0);
    final int localNow = (_rewindFromMs - groupStart).clamp(0, span);
    return groupStart + (localNow * (1.0 - rewindP)).round();
  }

  static List<_AnimGroup> _buildGroups(List<PmlShapeAnimation> source) {
    final List<PmlShapeAnimation> anims = List<PmlShapeAnimation>.from(source)
      ..sort(
        (PmlShapeAnimation a, PmlShapeAnimation b) =>
            a.order.compareTo(b.order),
      );
    final List<_AnimGroup> groups = <_AnimGroup>[];
    var items = <_TimedAnim>[];
    var wait = true;
    var cursor = 0;
    var started = false;
    for (final PmlShapeAnimation anim in anims) {
      if (!started) {
        wait = anim.trigger == PmlAnimTrigger.onClick;
        started = true;
        items.add(_TimedAnim(anim, anim.delayMs));
        cursor = anim.delayMs + anim.durationMs;
        continue;
      }
      if (anim.trigger == PmlAnimTrigger.onClick) {
        groups.add(_AnimGroup(waitForClick: wait, items: items));
        items = <_TimedAnim>[_TimedAnim(anim, anim.delayMs)];
        wait = true;
        cursor = anim.delayMs + anim.durationMs;
      } else if (anim.trigger == PmlAnimTrigger.withPrevious) {
        items.add(_TimedAnim(anim, anim.delayMs));
        final int end = anim.delayMs + anim.durationMs;
        if (end > cursor) {
          cursor = end;
        }
      } else {
        items.add(_TimedAnim(anim, cursor + anim.delayMs));
        cursor = cursor + anim.delayMs + anim.durationMs;
      }
    }
    if (items.isNotEmpty) {
      groups.add(_AnimGroup(waitForClick: wait, items: items));
    }
    return groups;
  }

  static PmlAnimSample _applyPreset(
    PmlShapeAnimation anim,
    double t, {
    required bool started,
    required bool done,
  }) {
    final double from = 1 - t;
    final (double ox, double oy) = _dirOffset(anim.direction);
    switch (anim.preset) {
      case PmlAnimPreset.appear:
        return started ? PmlAnimSample.identity : PmlAnimSample.hidden;
      case PmlAnimPreset.fade:
        return PmlAnimSample(opacity: t, visible: started);
      case PmlAnimPreset.flyIn:
        return PmlAnimSample(
          opacity: t,
          dx: ox * from,
          dy: oy * from,
          visible: started,
        );
      case PmlAnimPreset.floatIn:
        return PmlAnimSample(
          opacity: t,
          dy: (anim.direction == PmlTransitionDir.down ? -1 : 1) * 0.18 * from,
          visible: started,
        );
      case PmlAnimPreset.peekIn:
        return PmlAnimSample(dx: ox * from, dy: oy * from, visible: started);
      case PmlAnimPreset.riseUp:
        return PmlAnimSample(opacity: t, dy: 0.28 * from, visible: started);
      case PmlAnimPreset.split:
        return PmlAnimSample(
          visible: started,
          splitClip: true,
          reveal: t,
          clipDir: anim.direction,
        );
      case PmlAnimPreset.wipe:
        return PmlAnimSample(
          visible: started,
          wipeClip: true,
          reveal: t,
          clipDir: anim.direction,
        );
      case PmlAnimPreset.grow:
        return PmlAnimSample(
          opacity: t,
          scale: 0.2 + 0.8 * t,
          visible: started,
        );
      case PmlAnimPreset.growTurn:
        return PmlAnimSample(
          opacity: t,
          scale: 0.15 + 0.85 * t,
          rotationDeg: -90 * from,
          visible: started,
        );
      case PmlAnimPreset.zoom:
        return PmlAnimSample(
          opacity: t,
          scale: 0.05 + 0.95 * t,
          visible: started,
        );
      case PmlAnimPreset.swivel:
        return PmlAnimSample(
          opacity: t,
          scale: 0.35 + 0.65 * t,
          rotationDeg: 70 * from,
          visible: started,
        );
      case PmlAnimPreset.bounce:
        final double bounce = t < 1
            ? (1 - t) * math.sin(t * math.pi * 3) * 0.18
            : 0;
        return PmlAnimSample(
          opacity: t,
          dy: bounce,
          scale: 0.7 + 0.3 * t,
          visible: started,
        );
      case PmlAnimPreset.pulse:
        final double p = started && !done
            ? 1 + 0.12 * math.sin(t * math.pi)
            : 1;
        return PmlAnimSample(scale: p);
      case PmlAnimPreset.spin:
        return PmlAnimSample(rotationDeg: started ? 360 * t : 0);
      case PmlAnimPreset.teeter:
        final double tilt = started && !done
            ? 8 * math.sin(t * math.pi * 4)
            : 0;
        return PmlAnimSample(rotationDeg: tilt);
      case PmlAnimPreset.growShrink:
        final double gs = started && !done
            ? 1 + 0.22 * math.sin(t * math.pi)
            : 1;
        return PmlAnimSample(scale: gs);
      case PmlAnimPreset.disappear:
        return done || !started
            ? (done ? PmlAnimSample.hidden : PmlAnimSample.identity)
            : PmlAnimSample.hidden;
      case PmlAnimPreset.fadeOut:
        return PmlAnimSample(opacity: from, visible: !done);
      case PmlAnimPreset.flyOut:
        return PmlAnimSample(
          opacity: from,
          dx: ox * t,
          dy: oy * t,
          visible: !done,
        );
      case PmlAnimPreset.shrink:
        return PmlAnimSample(
          opacity: from,
          scale: 1 - 0.85 * t,
          visible: !done,
        );
      case PmlAnimPreset.pathLine:
        return PmlAnimSample(dx: ox * 0.28 * t, dy: oy * 0.28 * t);
      case PmlAnimPreset.pathArc:
        return PmlAnimSample(
          dx: ox * 0.28 * t,
          dy: oy * 0.28 * t - math.sin(t * math.pi) * 0.16,
        );
    }
  }

  static (double, double) _dirOffset(PmlTransitionDir dir) {
    return switch (dir) {
      PmlTransitionDir.left => (-1.0, 0.0),
      PmlTransitionDir.right => (1.0, 0.0),
      PmlTransitionDir.up => (0.0, -1.0),
      PmlTransitionDir.down => (0.0, 1.0),
      PmlTransitionDir.horizontal => (-1.0, 0.0),
      PmlTransitionDir.vertical => (0.0, -1.0),
      PmlTransitionDir.inward || PmlTransitionDir.outward => (0.0, 0.0),
    };
  }

  /// pow API.
  static double _ease(double t) => 1 - math.pow(1 - t, 3).toDouble();
}
