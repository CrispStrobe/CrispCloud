// ignore_for_file: public_member_api_docs

import 'color.dart';

/// An iterator over the channels of a [Color].
class ChannelIterator implements Iterator<num> {
  ChannelIterator(this.color);
  int index = -1;
  Color color;

  @override
  bool moveNext() {
    index++;
    return index < color.length;
  }

  @override
  num get current => color[index];
}
