import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:pro_image_editor/core/models/layers/emoji_layer.dart';
import 'package:pro_image_editor/core/models/layers/layer_interaction.dart';

EmojiLayer emojiLayerMock = EmojiLayer(
  emoji: '😀',
  boxConstraints: const BoxConstraints(
    minWidth: 100,
    maxWidth: 300,
    minHeight: 80,
    maxHeight: 400,
  ),
  flipX: true,
  flipY: false,
  groupId: 'mock-group',
  interaction: LayerInteraction(
    enableEdit: true,
    enableMove: false,
    enableRotate: true,
    enableScale: false,
    enableSelection: true,
  ),
  meta: {'emoji-mock': 'meta'},
  offset: const Offset(150, 300),
  rotation: pi,
  scale: 2.75,
);
