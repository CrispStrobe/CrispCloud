import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/core/models/layers/layer.dart';
import 'package:pro_image_editor/core/models/layers/layer_interaction.dart';

void main() {
  group('EmojiLayer', () {
    test('should create an EmojiLayer instance with correct properties', () {
      final emojiLayer = EmojiLayer(
        emoji: '😀',
        offset: const Offset(100.0, 100.0),
        rotation: 45.0,
        scale: 2.0,
        id: 'layer1',
        flipX: true,
        flipY: false,
      );

      expect(emojiLayer.emoji, '😀');
      expect(emojiLayer.offset, const Offset(100.0, 100.0));
      expect(emojiLayer.rotation, 45.0);
      expect(emojiLayer.scale, 2.0);
      expect(emojiLayer.id, 'layer1');
      expect(emojiLayer.flipX, true);
      expect(emojiLayer.flipY, false);
      expect(emojiLayer.isEmojiLayer, true);
    });

    test(
      'should convert EmojiLayer to map with meta and interaction properties',
      () {
        final meta = {'test': 'value'};
        final interaction = LayerInteraction(
          enableEdit: true,
          enableMove: false,
          enableRotate: true,
          enableScale: false,
          enableSelection: true,
        );

        final emojiLayer = EmojiLayer(
          emoji: '😀',
          rotation: 30.0,
          scale: 1.5,
          flipX: true,
          flipY: false,
          offset: const Offset(10, 20),
          meta: meta,
          interaction: interaction,
        );

        final map = emojiLayer.toMap();

        expect(map['emoji'], '😀');
        expect(map['rotation'], 30.0);
        expect(map['scale'], 1.5);
        expect(map['type'], 'emoji');
        expect(map['flipX'], isTrue);
        expect(map['flipY'], isFalse);
        expect(map['x'], 10);
        expect(map['y'], 20);
        expect(map['meta'], meta);
        expect(map['interaction'], interaction.toMap());
      },
    );

    test('should convert EmojiLayer to map correctly', () {
      final meta = {'test': 'value'};
      final interaction = LayerInteraction(
        enableEdit: true,
        enableMove: false,
        enableRotate: true,
        enableScale: false,
        enableSelection: true,
      );

      final emojiLayer = EmojiLayer(
        emoji: '😀',
        rotation: 30.0,
        scale: 1.5,
        flipX: true,
        flipY: false,
        offset: const Offset(10, 20),
        meta: meta,
        interaction: interaction,
      );

      final map = emojiLayer.toMap();

      expect(map['emoji'], '😀');
      expect(map['rotation'], 30.0);
      expect(map['scale'], 1.5);
      expect(map['type'], 'emoji');
      expect(map['flipX'], isTrue);
      expect(map['flipY'], isFalse);
      expect(map['x'], 10);
      expect(map['y'], 20);
      expect(map['meta'], meta);
      expect(map['interaction'], interaction.toMap());
    });

    test('should create EmojiLayer from map correctly', () {
      final baseLayer = Layer(
        id: 'layer3',
        offset: const Offset(20.0, 20.0),
        rotation: 15.0,
        scale: 1.0,
      );

      final map = {'emoji': '😎'};

      final emojiLayer = EmojiLayer.fromMap(baseLayer, map);

      expect(emojiLayer.id, 'layer3');
      expect(emojiLayer.offset, const Offset(20.0, 20.0));
      expect(emojiLayer.rotation, 15.0);
      expect(emojiLayer.scale, 1.0);
      expect(emojiLayer.emoji, '😎');
    });

    test('should convert EmojiLayer to map from reference correctly', () {
      final referenceLayer = EmojiLayer(emoji: '😀', id: 'layer4');

      final emojiLayer = EmojiLayer(emoji: '😎', id: 'layer4');

      final map = emojiLayer.toMapFromReference(referenceLayer);

      expect(map['emoji'], '😎');
      expect(map.containsKey('type'), false);
    });
  });
}
