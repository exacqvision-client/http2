// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library http2.src.hpack.huffman;

import 'dart:io';

import 'huffman_table.dart';

class HuffmanDecodingException implements Exception {
  final String _message;

  HuffmanDecodingException(this._message);

  @override
  String toString() => 'HuffmanDecodingException: $_message';
}

/// A codec used for encoding/decoding using a huffman codec.
class HuffmanCodec {
  final HuffmanEncoder _encoder;
  final HuffmanDecoder _decoder;

  HuffmanCodec(this._encoder, this._decoder);

  List<int> decode(List<int> bytes) => _decoder.decode(bytes);

  List<int> encode(List<int> bytes) => _encoder.encode(bytes);
}

/// A huffman decoder based on a [HuffmanTreeNode].
class HuffmanDecoder {
  final HuffmanTreeNode _root;

  HuffmanDecoder(this._root);

  /// Decodes [bytes] using a huffman tree.
  List<int> decode(List<int> bytes) {
    var buffer = BytesBuilder();

    int currentByteOffset = 0;
    HuffmanTreeNode node = _root;
    int currentDepth = 0;
    while (currentByteOffset < bytes.length) {
      var byte = bytes[currentByteOffset];
      for (int currentBit = 7; currentBit >= 0; currentBit--) {
        bool right = (byte >> currentBit) & 1 == 1;
        if (right) {
          node = node.right;
        } else {
          node = node.left;
        }
        currentDepth++;
        if (node.value != null) {
          if (node.value == EOS_BYTE) {
            throw HuffmanDecodingException(
                'More than 7 bit padding is not allowed. Found entire EOS '
                'encoding');
          }
          buffer.addByte(node.value);
          node = _root;
          currentDepth = 0;
        }
      }
      currentByteOffset++;
    }

    if (node != _root) {
      if (currentDepth > 7) {
        throw HuffmanDecodingException(
            'Incomplete encoding of a byte or more than 7 bit padding.');
      }

      while (node.right != null) node = node.right;

      if (node.value != 256) {
        throw HuffmanDecodingException('Incomplete encoding of a byte.');
      }
    }

    return buffer.takeBytes();
  }
}

/// A huffman encoder based on a list of codewords.
class HuffmanEncoder {
  final List<EncodedHuffmanValue> _codewords;

  HuffmanEncoder(this._codewords);

  /// Encodes [bytes] using a list of codewords.
  List<int> encode(List<int> bytes) {
    var buffer = BytesBuilder();

    int currentByte = 0;
    int currentBitOffset = 7;

    writeValue(int value, int numBits) {
      int i = numBits - 1;
      while (i >= 0) {
        if (currentBitOffset == 7 && i >= 7) {
          assert(currentByte == 0);

          buffer.addByte((value >> (i - 7)) & 0xff);
          currentBitOffset = 7;
          currentByte = 0;
          i -= 8;
        } else {
          currentByte |= ((value >> i) & 1) << currentBitOffset;

          currentBitOffset--;
          if (currentBitOffset == -1) {
            buffer.addByte(currentByte);
            currentBitOffset = 7;
            currentByte = 0;
          }
          i--;
        }
      }
    }

    for (int i = 0; i < bytes.length; i++) {
      var byte = bytes[i];
      var value = _codewords[byte];
      writeValue(value.encodedBytes, value.numBits);
    }

    if (currentBitOffset < 7) {
      writeValue(0xff, 1 + currentBitOffset);
    }

    return buffer.takeBytes();
  }
}

/// Specifies the encoding of a specific value using huffman encoding.
class EncodedHuffmanValue {
  /// An integer representation of the encoded bit-string.
  final int encodedBytes;

  /// The number of bits in [encodedBytes].
  final int numBits;

  const EncodedHuffmanValue(this.encodedBytes, this.numBits);
}

/// A node in the huffman tree.
class HuffmanTreeNode {
  HuffmanTreeNode left;
  HuffmanTreeNode right;
  int value;
}

/// Generates a huffman decoding tree.
HuffmanTreeNode generateHuffmanTree(List<EncodedHuffmanValue> valueEncodings) {
  HuffmanTreeNode root = HuffmanTreeNode();

  for (int byteOffset = 0; byteOffset < valueEncodings.length; byteOffset++) {
    var entry = valueEncodings[byteOffset];

    HuffmanTreeNode current = root;
    for (int bitNr = 0; bitNr < entry.numBits; bitNr++) {
      bool right =
          ((entry.encodedBytes >> (entry.numBits - bitNr - 1)) & 1) == 1;

      if (right) {
        if (current.right == null) {
          current.right = HuffmanTreeNode();
        }
        current = current.right;
      } else {
        if (current.left == null) {
          current.left = HuffmanTreeNode();
        }
        current = current.left;
      }
    }

    current.value = byteOffset;
  }

  return root;
}
