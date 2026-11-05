import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/core/platform/io/io_helper.dart';
import '/plugins/emoji_picker_flutter/emoji_picker_flutter.dart';
import '/pro_image_editor_platform_interface.dart';

/// Initial value for RecentEmoji
const initVal = 1;

/// Helper class that provides internal usage
class EmojiPickerInternalUtils {
  // Get available emoji for given category title
  Future<CategoryEmoji> _getAvailableEmojis(CategoryEmoji category) async {
    var available =
        (await ProImageEditorPlatform.instance.getSupportedEmojis(
          category.emoji.map((e) => e.emoji).toList(growable: false),
        )) ??
        [];

    return category.copyWith(
      emoji: [
        for (int i = 0; i < available.length; i++)
          if (available[i]) category.emoji[i],
      ],
    );
  }

  /// Filters out emojis not supported on the platform
  Future<List<CategoryEmoji>> filterUnsupported(
    List<CategoryEmoji> data,
  ) async {
    if (kIsWeb || !Platform.isAndroid) {
      return data;
    }
    final futures = [for (final cat in data) _getAvailableEmojis(cat)];
    return await Future.wait(futures);
  }

  /// Returns list of recently used emoji from cache
  Future<List<RecentEmoji>> getRecentEmojis() async {
    final prefs = await SharedPreferences.getInstance();
    var emojiJson = prefs.getString('recent');
    if (emojiJson == null) {
      return [];
    }
    var json = jsonDecode(emojiJson) as List<dynamic>;
    return json.map<RecentEmoji>(RecentEmoji.fromJson).toList();
  }

  /// Add an emoji to recently used list
  Future<List<RecentEmoji>> addEmojiToRecentlyUsed({
    required Emoji emoji,
    Config config = const Config(),
  }) async {
    // Remove emoji's skin tone in Recent-Category
    if (emoji.hasSkinTone) {
      emoji = removeSkinTone(emoji);
    }
    var recentEmoji = await getRecentEmojis();
    var recentEmojiIndex = recentEmoji.indexWhere(
      (element) => element.emoji.emoji == emoji.emoji,
    );
    if (recentEmojiIndex != -1) {
      // Already exist in recent list
      // Remove it
      recentEmoji.removeAt(recentEmojiIndex);
    }
    // Add it first position
    recentEmoji.insert(0, RecentEmoji(emoji, initVal));

    // Limit entries to recentsLimit
    recentEmoji = recentEmoji.sublist(
      0,
      min(config.emojiViewConfig.recentsLimit, recentEmoji.length),
    );

    // save locally
    final prefs = await SharedPreferences.getInstance();
    unawaited(prefs.setString('recent', jsonEncode(recentEmoji)));

    return recentEmoji;
  }

  /// Add an emoji to popular used list or increase its counter
  Future<List<RecentEmoji>> addEmojiToPopularUsed({
    required Emoji emoji,
    Config config = const Config(),
  }) async {
    // Remove emoji's skin tone in Recent-Category
    if (emoji.hasSkinTone) {
      emoji = removeSkinTone(emoji);
    }
    var recentEmoji = await getRecentEmojis();
    var recentEmojiIndex = recentEmoji.indexWhere(
      (element) => element.emoji.emoji == emoji.emoji,
    );
    if (recentEmojiIndex != -1) {
      // Already exist in recent list
      // Just update counter
      recentEmoji[recentEmojiIndex].counter++;
    } else if (recentEmoji.length == config.emojiViewConfig.recentsLimit &&
        config.emojiViewConfig.replaceEmojiOnLimitExceed) {
      // Replace latest emoji with the fresh one
      recentEmoji[recentEmoji.length - 1] = RecentEmoji(emoji, initVal);
    } else {
      recentEmoji.add(RecentEmoji(emoji, initVal));
    }

    // Sort by counter desc
    recentEmoji.sort((a, b) => b.counter - a.counter);

    // Limit entries to recentsLimit
    recentEmoji = recentEmoji.sublist(
      0,
      min(config.emojiViewConfig.recentsLimit, recentEmoji.length),
    );

    // save locally
    final prefs = await SharedPreferences.getInstance();
    unawaited(prefs.setString('recent', jsonEncode(recentEmoji)));

    return recentEmoji;
  }

  /// Clears the list of recent emojis in local storage
  Future<void> clearRecentEmojisInLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('recent', jsonEncode([]));
  }

  /// Remove skin tone from given emoji
  Emoji removeSkinTone(Emoji emoji) {
    return emoji.copyWith(
      emoji: emoji.emoji.replaceFirst(RegExp(SkinTone.values.join('|')), ''),
    );
  }
}
