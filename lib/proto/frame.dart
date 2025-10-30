import 'dart:typed_data';
import 'dart:collection';

class FrameType {
  static const int text = 0x01;
  static const int voice = 0x02;
  static const int ctrlAck = 0x10; // optional
}

class Frame {
  static const int sync = 0x7E;
  static const int ver = 0x01;

  final int type;
  final int flags;
  final int msgId;
  final int chunkIdx;
  final int chunkCnt;
  final Uint8List payload;

  Frame({
    required this.type,
    required this.flags,
    required this.msgId,
    required this.chunkIdx,
    required this.chunkCnt,
    required this.payload,
  });
}

int _u16le(int v) => v & 0xFFFF;

int crc16Kermit(Uint8List data) {
  int crc = 0x0000;
  for (final byte in data) {
    crc ^= byte;
    for (int i = 0; i < 8; i++) {
      if ((crc & 0x0001) != 0) {
        crc = (crc >> 1) ^ 0x8408;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc & 0xFFFF;
}

Uint8List buildFrame(Frame f) {
  final header = Uint8List(13);
  final b = ByteData.view(header.buffer);
  header[0] = Frame.sync;
  header[1] = Frame.ver;
  header[2] = f.type & 0xFF;
  header[3] = f.flags & 0xFF;
  b.setUint16(4, _u16le(f.msgId), Endian.little);
  b.setUint16(6, _u16le(f.chunkIdx), Endian.little);
  b.setUint16(8, _u16le(f.chunkCnt), Endian.little);
  b.setUint16(10, _u16le(f.payload.length), Endian.little);
  // crc placeholder at [11..12]

  final builder = BytesBuilder();
  builder.add(header);
  builder.add(f.payload);

  // CRC over VER..payload (exclude SYNC)
  final toCrc = builder.toBytes().sublist(1);
  final crc = crc16Kermit(toCrc);
  header[11] = crc & 0xFF;
  header[12] = (crc >> 8) & 0xFF;

  final out = BytesBuilder();
  out.add(header);
  out.add(f.payload);
  return out.toBytes();
}

class FrameParser {
  final _buf = BytesBuilder();

  List<Frame> feed(Uint8List chunk) {
    _buf.add(chunk);
    final out = <Frame>[];
    final data = _buf.toBytes();
    int i = 0;

    while (i + 13 <= data.length) {
      while (i < data.length && data[i] != Frame.sync) i++;
      if (i + 13 > data.length) break;

      final ver = data[i + 1];
      if (ver != Frame.ver) { i++; continue; }

      final bd = ByteData.sublistView(data, i);
      final type  = data[i + 2];
      final flags = data[i + 3];
      final msgId    = bd.getUint16(4, Endian.little);
      final chunkIdx = bd.getUint16(6, Endian.little);
      final chunkCnt = bd.getUint16(8, Endian.little);
      final payLen   = bd.getUint16(10, Endian.little);
      final crcGot   = bd.getUint16(11, Endian.little);

      final need = 13 + payLen;
      if (i + need > data.length) break;

      final body = Uint8List.view(data.buffer, data.offsetInBytes + i + 13, payLen);

      // recompute crc over VER..payload
      final toCrc = Uint8List(11 + payLen);
      toCrc.setRange(0, 11 + payLen, data.sublist(i + 1, i + 12 + payLen));
      final crcExp = crc16Kermit(toCrc);
      if (crcExp != crcGot) { i++; continue; }

      out.add(Frame(
        type: type, flags: flags, msgId: msgId,
        chunkIdx: chunkIdx, chunkCnt: chunkCnt, payload: body,
      ));
      i += need;
    }

    // keep remainder
    _buf.clear();
    if (i < data.length) _buf.add(Uint8List.fromList(data.sublist(i)));
    return out;
  }
}


