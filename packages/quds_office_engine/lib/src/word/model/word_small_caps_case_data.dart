// Unicode 17.0.0 unconditional uppercase expansions, from:
// https://www.unicode.org/Public/17.0.0/ucd/SpecialCasing.txt
//
// UNICODE LICENSE V3
// COPYRIGHT AND PERMISSION NOTICE
// Copyright © 1991-2026 Unicode, Inc.
//
// NOTICE TO USER: Carefully read the following legal agreement. BY
// DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
// SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
// TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
// DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of data files and any associated documentation (the "Data Files") or
// software and any associated documentation (the "Software") to deal in the
// Data Files or Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, and/or sell
// copies of the Data Files or Software, and to permit persons to whom the
// Data Files or Software are furnished to do so, provided that either (a)
// this copyright and permission notice appear with all copies of the Data
// Files or Software, or (b) this copyright and permission notice appear in
// associated Documentation.
// THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
// KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
// THIRD PARTY RIGHTS.
// IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
// BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
// OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
// WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
// ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
// FILES OR SOFTWARE.
// Except as contained in this notice, the name of a copyright holder shall
// not be used in advertising or otherwise to promote the sale, use or other
// dealings in these Data Files or Software without prior written
// authorization of the copyright holder.

part of 'word_small_caps.dart';

const _fullUppercaseExpansions = <int, String>{
  0xdf: '\u0053\u0053',
  0x149: '\u02bc\u004e',
  0x1f0: '\u004a\u030c',
  0x390: '\u0399\u0308\u0301',
  0x3b0: '\u03a5\u0308\u0301',
  0x587: '\u0535\u0552',
  0x1e96: '\u0048\u0331',
  0x1e97: '\u0054\u0308',
  0x1e98: '\u0057\u030a',
  0x1e99: '\u0059\u030a',
  0x1e9a: '\u0041\u02be',
  0x1f50: '\u03a5\u0313',
  0x1f52: '\u03a5\u0313\u0300',
  0x1f54: '\u03a5\u0313\u0301',
  0x1f56: '\u03a5\u0313\u0342',
  0x1f80: '\u1f08\u0399',
  0x1f81: '\u1f09\u0399',
  0x1f82: '\u1f0a\u0399',
  0x1f83: '\u1f0b\u0399',
  0x1f84: '\u1f0c\u0399',
  0x1f85: '\u1f0d\u0399',
  0x1f86: '\u1f0e\u0399',
  0x1f87: '\u1f0f\u0399',
  0x1f88: '\u1f08\u0399',
  0x1f89: '\u1f09\u0399',
  0x1f8a: '\u1f0a\u0399',
  0x1f8b: '\u1f0b\u0399',
  0x1f8c: '\u1f0c\u0399',
  0x1f8d: '\u1f0d\u0399',
  0x1f8e: '\u1f0e\u0399',
  0x1f8f: '\u1f0f\u0399',
  0x1f90: '\u1f28\u0399',
  0x1f91: '\u1f29\u0399',
  0x1f92: '\u1f2a\u0399',
  0x1f93: '\u1f2b\u0399',
  0x1f94: '\u1f2c\u0399',
  0x1f95: '\u1f2d\u0399',
  0x1f96: '\u1f2e\u0399',
  0x1f97: '\u1f2f\u0399',
  0x1f98: '\u1f28\u0399',
  0x1f99: '\u1f29\u0399',
  0x1f9a: '\u1f2a\u0399',
  0x1f9b: '\u1f2b\u0399',
  0x1f9c: '\u1f2c\u0399',
  0x1f9d: '\u1f2d\u0399',
  0x1f9e: '\u1f2e\u0399',
  0x1f9f: '\u1f2f\u0399',
  0x1fa0: '\u1f68\u0399',
  0x1fa1: '\u1f69\u0399',
  0x1fa2: '\u1f6a\u0399',
  0x1fa3: '\u1f6b\u0399',
  0x1fa4: '\u1f6c\u0399',
  0x1fa5: '\u1f6d\u0399',
  0x1fa6: '\u1f6e\u0399',
  0x1fa7: '\u1f6f\u0399',
  0x1fa8: '\u1f68\u0399',
  0x1fa9: '\u1f69\u0399',
  0x1faa: '\u1f6a\u0399',
  0x1fab: '\u1f6b\u0399',
  0x1fac: '\u1f6c\u0399',
  0x1fad: '\u1f6d\u0399',
  0x1fae: '\u1f6e\u0399',
  0x1faf: '\u1f6f\u0399',
  0x1fb2: '\u1fba\u0399',
  0x1fb3: '\u0391\u0399',
  0x1fb4: '\u0386\u0399',
  0x1fb6: '\u0391\u0342',
  0x1fb7: '\u0391\u0342\u0399',
  0x1fbc: '\u0391\u0399',
  0x1fc2: '\u1fca\u0399',
  0x1fc3: '\u0397\u0399',
  0x1fc4: '\u0389\u0399',
  0x1fc6: '\u0397\u0342',
  0x1fc7: '\u0397\u0342\u0399',
  0x1fcc: '\u0397\u0399',
  0x1fd2: '\u0399\u0308\u0300',
  0x1fd3: '\u0399\u0308\u0301',
  0x1fd6: '\u0399\u0342',
  0x1fd7: '\u0399\u0308\u0342',
  0x1fe2: '\u03a5\u0308\u0300',
  0x1fe3: '\u03a5\u0308\u0301',
  0x1fe4: '\u03a1\u0313',
  0x1fe6: '\u03a5\u0342',
  0x1fe7: '\u03a5\u0308\u0342',
  0x1ff2: '\u1ffa\u0399',
  0x1ff3: '\u03a9\u0399',
  0x1ff4: '\u038f\u0399',
  0x1ff6: '\u03a9\u0342',
  0x1ff7: '\u03a9\u0342\u0399',
  0x1ffc: '\u03a9\u0399',
  0xfb00: '\u0046\u0046',
  0xfb01: '\u0046\u0049',
  0xfb02: '\u0046\u004c',
  0xfb03: '\u0046\u0046\u0049',
  0xfb04: '\u0046\u0046\u004c',
  0xfb05: '\u0053\u0054',
  0xfb06: '\u0053\u0054',
  0xfb13: '\u0544\u0546',
  0xfb14: '\u0544\u0535',
  0xfb15: '\u0544\u053b',
  0xfb16: '\u054e\u0546',
  0xfb17: '\u0544\u053d',
};
