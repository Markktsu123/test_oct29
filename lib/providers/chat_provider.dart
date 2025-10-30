import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import '../services/bluetooth_service.dart';
import '../voice_chat_extension.dart' as voice;
import '../proto/frame.dart';

class ChatProvider with ChangeNotifier {
  final BluetoothService _bluetoothService = BluetoothService();
  final voice.VoiceChatExtension _voiceExtension = voice.VoiceChatExtension();

  List<BluetoothDevice> _pairedDevices = [];
  BluetoothDevice? _selectedDevice;
  bool _isConnected = false;
  List<ChatMessage> _messages = [];
  List<String> _debugLogs = [];
  bool _isConnecting = false;

  List<BluetoothDevice> get pairedDevices => _pairedDevices;
  BluetoothDevice? get selectedDevice => _selectedDevice;
  bool get isConnected => _isConnected;
  List<ChatMessage> get messages => _messages;
  List<String> get debugLogs => _debugLogs;
  bool get isConnecting => _isConnecting;

  voice.VoiceChatExtension get voiceExtension => _voiceExtension;
  bool get isRecording => _voiceExtension.isRecording;
  bool get isPlaying => _voiceExtension.isPlaying;

  StreamSubscription<String>? _legacyMsgSub;
  StreamSubscription<Uint8List>? _byteSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<String>? _debugSub;

  final FrameParser _parser = FrameParser();
  final Map<int, List<Uint8List?>> _rxByMsgId = {};
  final Map<int, int> _rxTotalChunks = {};

  ChatProvider() {
    _init();
  }

  void _init() {
    // Binary stream (frames)
    _byteSub = _bluetoothService.byteStream.listen((chunk) {
      final frames = _parser.feed(chunk);
      if (frames.isEmpty) return;
      for (final f in frames) {
        if (f.type == FrameType.text) {
          final text = utf8.decode(f.payload, allowMalformed: true);
          _addMessage(text, false);
        } else if (f.type == FrameType.voice) {
          _onVoiceFrame(f);
        } else {
          addStructuredDebug({'source': 'BT', 'event': 'Unknown frame', 'metrics': {'type': f.type}});
        }
      }
    });

    // Connection & debug
    _connectionSub = _bluetoothService.connectionStream.listen((connected) {
      _isConnected = connected;
      notifyListeners();
    });

    _debugSub = _bluetoothService.debugStream.listen((log) {
      _pushDebug(log);
    });

    // Existing voice extension debug passthrough
    _voiceExtension.debugStream.listen((log) => _pushDebug('[VOICE] $log'));
  }

  void _pushDebug(String s) {
    _debugLogs.add('${DateTime.now().toString().substring(11, 19)}: $s');
    if (_debugLogs.length > 200) _debugLogs.removeAt(0);
    notifyListeners();
  }

  Future<void> loadPairedDevices() async {
    _pairedDevices = await _bluetoothService.getPairedDevices();
    notifyListeners();
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    _isConnecting = true;
    notifyListeners();

    try {
      bool success = await _bluetoothService.connectToDevice(device);
      if (success) {
        _selectedDevice = device;
        _isConnected = true;
      }
      return success;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _bluetoothService.disconnect();
    _selectedDevice = null;
    _isConnected = false;
    notifyListeners();
  }

  // TEXT: send as a single binary frame
  Future<bool> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final msg = ChatMessage(
      text: trimmed,
      isMe: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      type: voice.MessageType.text,
    );
    _messages.add(msg);
    notifyListeners();

    final payload = Uint8List.fromList(utf8.encode(trimmed));
    final msgId = DateTime.now().millisecondsSinceEpoch & 0xFFFF;
    final frame = buildFrame(Frame(
      type: FrameType.text,
      flags: 0,
      msgId: msgId,
      chunkIdx: 0,
      chunkCnt: 1,
      payload: payload,
    ));

    final ok = await _bluetoothService.sendBytes(frame);
    msg.status = ok ? MessageStatus.sent : MessageStatus.failed;
    notifyListeners();
    return ok;
  }

  /// Process incoming message and handle voice messages
  void _processIncomingMessage(String data) {
    addStructuredDebug({
      'source': 'CHAT',
      'event': 'Processing incoming data',
      'metrics': {'dataLength': data.length}
    });
    
    final messages = _voiceExtension.processIncomingData(data);
    
    addStructuredDebug({
      'source': 'CHAT',
      'event': 'Processed messages',
      'metrics': {'messageCount': messages.length}
    });
    
    for (final message in messages) {
      if (message.startsWith('VOICE_MESSAGE:')) {
        // Extract the Base64 data from the voice message marker
        final base64Audio = message.substring(14); // Remove 'VOICE_MESSAGE:' prefix
        
        // Validate Base64 data
        if (base64Audio.isEmpty) {
          addStructuredDebug({
            'source': 'CHAT',
            'event': 'Voice message rejected - empty data',
            'metrics': {}
          });
          continue;
        }

        if (!_isValidBase64(base64Audio)) {
          addStructuredDebug({
            'source': 'CHAT',
            'event': 'Voice message rejected - invalid Base64',
            'metrics': {'length': base64Audio.length}
          });
          continue;
        }
        
        addStructuredDebug({
          'source': 'CHAT',
          'event': 'Creating voice message',
          'metrics': {'base64Length': base64Audio.length}
        });
        _addVoiceMessage(base64Audio, false);
      } else if (message.startsWith('<VOICE_START>') || message.startsWith('<VOICE_END>')) {
        // Voice markers, handled by voice extension
        continue;
      } else {
        // Regular text message
        _addMessage(message, false);
      }
    }
  }

  /// Add voice message to chat
  void _addVoiceMessage(String base64Audio, bool isMe) {
    addStructuredDebug({
      'source': 'CHAT',
      'event': 'Adding voice message',
      'metrics': {'base64Length': base64Audio.length, 'isMe': isMe}
    });
    
    // Calculate duration for voice messages
    Duration? messageDuration;
    if (isMe) {
      // For sent messages, use recording duration
      messageDuration = _voiceExtension.getRecordingDuration();
    } else {
      // For received messages, estimate duration from file size (Base64 encoded AAC at 128kbps)
      try {
        final bytes = base64Decode(base64Audio);
        // Correct estimation: Base64 encoded AAC at 128kbps ≈ 21.3KB per second
        final estimatedSeconds = bytes.length / 21333.0;
        messageDuration = Duration(milliseconds: (estimatedSeconds * 1000).round());
      } catch (e) {
        messageDuration = null;
      }
    }
    
    final voiceMessage = voice.VoiceMessage.fromBase64(
      base64Audio: base64Audio,
      isMe: isMe,
      status: isMe ? MessageStatus.sent : MessageStatus.received,
      duration: messageDuration,
    );

    final chatMessage = ChatMessage(
      text: '🎤 Voice message',
      isMe: isMe,
      timestamp: DateTime.now(),
      status: isMe ? MessageStatus.sent : MessageStatus.received,
      type: voice.MessageType.voice,
      voiceMessage: voiceMessage,
    );

    _messages.add(chatMessage);
    addStructuredDebug({
      'source': 'CHAT',
      'event': 'Voice message added to chat',
      'metrics': {'totalMessages': _messages.length, 'voiceSize': voiceMessage.formattedSize}
    });
    notifyListeners();
  }

  /// Start recording voice message
  Future<bool> startRecording() async {
    return await _voiceExtension.startRecording();
  }

  Future<bool> stopRecordingAndSend() async {
    final path = await _voiceExtension.stopRecording();
    if (path == null) return false;

    final bytes = await _voiceExtension.audioFileToBytes(path);
    if (bytes == null || bytes.isEmpty) {
      addStructuredDebug({'source': 'VOICE', 'event': 'Empty audio bytes'});
      return false;
    }

    final duration = _voiceExtension.getRecordingDuration();
    final msgId = DateTime.now().millisecondsSinceEpoch & 0xFFFF;

    // (UI) add bubble early
    final vm = voice.VoiceMessage.fromBytes(
      audioBytes: bytes,
      isMe: true,
      status: MessageStatus.sending,
      duration: duration,
    );
    final chatMsg = ChatMessage(
      text: '🎤 Voice message',
      isMe: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      type: voice.MessageType.voice,
      voiceMessage: vm,
    );
    _messages.add(chatMsg);
    notifyListeners();

    // chunk & send
    const chunkSize = 512; // try 256..512
    final total = (bytes.length / chunkSize).ceil();
    var ok = true;
    for (int i = 0; i < total; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize < bytes.length) ? start + chunkSize : bytes.length;
      final frame = buildFrame(Frame(
        type: FrameType.voice,
        flags: (i < total - 1) ? 1 : 0,
        msgId: msgId,
        chunkIdx: i,
        chunkCnt: total,
        payload: Uint8List.sublistView(bytes, start, end),
      ));
      final s = await _bluetoothService.sendBytes(frame);
      if (!s) { ok = false; break; }
      await Future.delayed(const Duration(milliseconds: 2));
    }

    chatMsg.status = ok ? MessageStatus.sent : MessageStatus.failed;
    vm.status = ok ? MessageStatus.sent : MessageStatus.failed;
    notifyListeners();
    return ok;
  }

  Future<bool> playVoiceMessage(voice.VoiceMessage v) async {
    return await _voiceExtension.playVoiceBytes(v.audioBytes);
  }

  /// Stop current playback
  Future<void> stopPlayback() async {
    await _voiceExtension.stopPlayback();
  }

  void _addMessage(String text, bool isMe, [ChatMessage? message]) {
    _messages.add(message ?? ChatMessage(
      text: text,
      isMe: isMe,
      timestamp: DateTime.now(),
      status: isMe ? MessageStatus.sent : MessageStatus.delivered,
      type: voice.MessageType.text,
    ));
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  void clearDebugLogs() {
    _debugLogs.clear();
    notifyListeners();
  }

  void addStructuredDebug(Map<String, dynamic> payload) {
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = {
      'timestamp': timestamp,
      'source': payload['source'] ?? 'unknown',
      'event': payload['event'] ?? 'unknown',
      'metrics': payload['metrics'] ?? {},
      ...payload,
    };
    final logString = '[${logEntry['source']}] ${logEntry['event']}';
    if ((logEntry['metrics'] as Map).isNotEmpty) {
      final m = (logEntry['metrics'] as Map).entries.map((e) => '${e.key}=${e.value}').join(', ');
      _debugLogs.add('$logString ($m)');
    } else {
      _debugLogs.add(logString);
    }
    if (_debugLogs.length > 200) _debugLogs.removeAt(0);
    notifyListeners();
  }

  /// Validate Base64 string format
  bool _isValidBase64(String str) {
    if (str.isEmpty) return false;
    // Check if string contains only valid Base64 characters
    final base64Pattern = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');
    return base64Pattern.hasMatch(str);
  }

  void _onVoiceFrame(Frame f) async {
    final parts = _rxByMsgId.putIfAbsent(f.msgId, () => List<Uint8List?>.filled(f.chunkCnt, null, growable: true));
    if (parts.length < f.chunkCnt) {
      parts.length = f.chunkCnt;
    }
    parts[f.chunkIdx] = f.payload;
    _rxTotalChunks[f.msgId] = f.chunkCnt;

    final complete = parts.length == f.chunkCnt && parts.every((e) => e != null);
    if (!complete) return;

    final bb = BytesBuilder();
    for (final p in parts) { bb.add(p!); }
    final audio = bb.toBytes();

    final vm = voice.VoiceMessage.fromBytes(
      audioBytes: audio,
      isMe: false,
      status: MessageStatus.received,
      duration: null,
    );

    final chatMsg = ChatMessage(
      text: '🎤 Voice message',
      isMe: false,
      timestamp: DateTime.now(),
      status: MessageStatus.received,
      type: voice.MessageType.voice,
      voiceMessage: vm,
    );

    _messages.add(chatMsg);
    notifyListeners();

    _rxByMsgId.remove(f.msgId);
    _rxTotalChunks.remove(f.msgId);
  }

  @override
  void dispose() {
    _legacyMsgSub?.cancel();
    _byteSub?.cancel();
    _connectionSub?.cancel();
    _debugSub?.cancel();
    _bluetoothService.dispose();
    _voiceExtension.dispose();
    super.dispose();
  }
}

class ChatMessage {
  final String text;
  final bool isMe;
  final DateTime timestamp;
  MessageStatus status;
  final voice.MessageType type;
  final voice.VoiceMessage? voiceMessage;

  ChatMessage({
    required this.text,
    required this.isMe,
    required this.timestamp,
    this.status = MessageStatus.sent,
    this.type = voice.MessageType.text,
    this.voiceMessage,
  });
}

enum MessageStatus {
  sending, sent, delivered, failed, received,
}
