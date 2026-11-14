// SPDX-License-Identifier: MPL-2.0
// Literal MS-DOC LVLF/Xst bytes distinguish real offset placeholders from
// ordinary text, including percent signs and levels without number sequences.

import 'dart:typed_data';

import 'list_sequence_fixture.dart';
import 'list_word_fixture.dart';
import 'structured_word_fixture.dart';

const listMetadataCases = [
  'bullet-ignored-restart',
  'none-ignored-restart',
  'none-literal',
  'none-empty-placeholder',
  'none-ancestor-placeholder',
  'literal-percent-text',
  'percent-before-placeholder',
  'numbered-valid-restart',
  'numbered-inactive-restart',
  'uncommon-format-literal',
  'uncommon-format-ancestor',
  'uncommon-format-legal',
  'literal-label-tab',
  'tab-before-placeholder',
  'none-label-tab',
  'literal-percent-one',
  'literal-percent-nine',
  'mixed-literal-percent',
  'override-literal-percent',
  'none-literal-percent',
];

const materializedListMetadataCases = [
  'literal-percent-one',
  'literal-percent-nine',
  'mixed-literal-percent',
  'override-literal-percent',
  'none-literal-percent',
];

const invalidListMetadataCases = ['numbered-active-bad-restart'];

Uint8List listMetadataFixture(String name) {
  List<int> literal(String text, {int format = 0}) =>
      listFixtureLevel(format: format, start: 7, text: text, placeholders: []);

  return switch (name) {
    'bullet-ignored-restart' => listWordFixture(
      levels: [
        listFixtureLevel(
          format: 23,
          text: '\u2022',
          placeholders: [],
          start: 0xffffffff,
          flags: 8,
          restart: 255,
        ),
      ],
    ),
    'none-ignored-restart' => listWordFixture(
      levels: [
        listFixtureLevel(
          format: 255,
          text: '',
          placeholders: [],
          start: 0xffffffff,
          flags: 8,
          restart: 255,
        ),
      ],
    ),
    'none-literal' => listWordFixture(
      levels: [literal('Appendix', format: 255)],
    ),
    'none-empty-placeholder' => listWordFixture(
      levels: [
        listFixtureLevel(
          format: 255,
          text: 'Appendix \x00.',
          placeholders: [10],
        ),
      ],
    ),
    'none-ancestor-placeholder' => listSequenceFixture(
      [(1, 0), (1, 1)],
      levels: [
        listFixtureLevel(start: 3),
        listFixtureLevel(
          level: 1,
          format: 255,
          text: '\x00 Appendix \x01',
          placeholders: [1, 12],
          flags: 8,
          restart: 255,
        ),
        for (var level = 2; level < 9; level++) listFixtureLevel(level: level),
      ],
    ),
    'literal-percent-text' => listWordFixture(levels: [literal('% %0 %x 50%')]),
    'percent-before-placeholder' => listWordFixture(
      levels: [
        listFixtureLevel(start: 7, text: '%\x00 %', placeholders: [2]),
      ],
    ),
    'numbered-valid-restart' => listWordFixture(
      levels: [listFixtureLevel(start: 7, flags: 8)],
    ),
    'numbered-inactive-restart' => listWordFixture(
      levels: [listFixtureLevel(start: 7, restart: 255)],
    ),
    'uncommon-format-literal' => listWordFixture(
      levels: [literal('Appendix', format: 45)],
    ),
    'uncommon-format-ancestor' => listSequenceFixture(
      [(1, 0), (1, 1)],
      levels: [
        listFixtureLevel(start: 3),
        listFixtureLevel(
          level: 1,
          format: 45,
          text: '\x00 Appendix',
          placeholders: [1],
        ),
        for (var level = 2; level < 9; level++) listFixtureLevel(level: level),
      ],
    ),
    'uncommon-format-legal' => listWordFixture(
      levels: [listFixtureLevel(format: 45, start: 7, flags: 4)],
    ),
    'literal-label-tab' => listWordFixture(levels: [literal('A\tB')]),
    'tab-before-placeholder' => listWordFixture(
      levels: [
        listFixtureLevel(start: 7, text: 'A\t\x00', placeholders: [3]),
      ],
    ),
    'none-label-tab' => listWordFixture(levels: [literal('A\tB', format: 255)]),
    'literal-percent-one' => listWordFixture(levels: [literal('%1')]),
    'literal-percent-nine' => listWordFixture(levels: [literal('%9')]),
    'mixed-literal-percent' => listWordFixture(
      levels: [listFixtureLevel(start: 7, text: '\x00 literal %1')],
    ),
    'override-literal-percent' => listWordFixture(
      instances: listFixtureInstances(
        overrides: [
          [...wordU32(0xffffffff), ...wordU32(0x20), ...literal('%1')],
        ],
      ),
    ),
    'none-literal-percent' => listWordFixture(
      levels: [literal('%1', format: 255)],
    ),
    'numbered-active-bad-restart' => listWordFixture(
      levels: [listFixtureLevel(flags: 8, restart: 255)],
    ),
    _ => throw ArgumentError.value(name, 'name', 'Unknown list metadata case'),
  };
}
