import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import '../services/bluetooth_service.dart';
import '../voice_chat_extension.dart' as voice;

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
  
  // Voice extension getters
  voice.VoiceChatExtension get voiceExtension => _voiceExtension;
  bool get isRecording => _voiceExtension.isRecording;
  bool get isPlaying => _voiceExtension.isPlaying;

  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<String>? _debugSubscription;

  ChatProvider() {
    _init();
  }

  void _init() {
    _messageSubscription = _bluetoothService.messageStream.listen((message) {
      _processIncomingMessage(message);
    });

    _connectionSubscription = _bluetoothService.connectionStream.listen((connected) {
      _isConnected = connected;
      notifyListeners();
    });

    _debugSubscription = _bluetoothService.debugStream.listen((log) {
      _debugLogs.add('${DateTime.now().toString().substring(11, 19)}: $log');
      if (_debugLogs.length > 100) {
        _debugLogs.removeAt(0);
      }
      notifyListeners();
    });

    // Listen to voice extension debug stream
    _voiceExtension.debugStream.listen((log) {
      _debugLogs.add('${DateTime.now().toString().substring(11, 19)}: [VOICE] $log');
      if (_debugLogs.length > 100) {
        _debugLogs.removeAt(0);
      }
      notifyListeners();
    });
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

  Future<bool> sendMessage(String text) async {
    if (text.trim().isEmpty) return false;

    ChatMessage message = ChatMessage(
      text: text.trim(),
      isMe: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      type: voice.MessageType.text,
    );

    _addMessage(message.text, true, message);

    bool success = await _bluetoothService.sendMessage(text);
    
    if (success) {
      message.status = MessageStatus.sent;
    } else {
      message.status = MessageStatus.failed;
    }
    
    notifyListeners();
    return success;
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

  /// Stop recording and send voice message with structured logging
  Future<bool> stopRecordingAndSend() async {
    final recordingPath = await _voiceExtension.stopRecording();
    if (recordingPath == null) {
      addStructuredDebug({
        'source': 'VOICE',
        'event': 'Recording failed or retrying',
        'metrics': {
          'isRetrying': _voiceExtension.isRetrying,
        }
      });
      return false;
    }

    addStructuredDebug({
      'source': 'VOICE',
      'event': 'Recording completed',
      'metrics': {
        'filePath': recordingPath,
      }
    });

    // Convert to Base64
    final base64Audio = await _voiceExtension.audioFileToBase64(recordingPath);
    if (base64Audio == null) {
      addStructuredDebug({
        'source': 'VOICE',
        'event': 'Base64 encoding failed',
        'metrics': {'filePath': recordingPath}
      });
      return false;
    }

    addStructuredDebug({
      'source': 'VOICE',
      'event': 'Base64 encoding completed',
      'metrics': {
        'base64Length': base64Audio.length,
        'estimatedSizeKB': (base64Audio.length * 3 / 4 / 1024).toStringAsFixed(1),
      }
    });

    // Calculate recording duration
    final recordingDuration = _voiceExtension.getRecordingDuration();
    
    // Create voice message
    final voiceMessage = voice.VoiceMessage.fromBase64(
      base64Audio: base64Audio,
      isMe: true,
      status: MessageStatus.sending,
      duration: recordingDuration,
    );

    // Add to messages
    final chatMessage = ChatMessage(
      text: '🎤 Voice message',
      isMe: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      type: voice.MessageType.voice,
      voiceMessage: voiceMessage,
    );

    _messages.add(chatMessage);
    notifyListeners();

    // Send over Bluetooth
    final success = await _voiceExtension.sendVoiceMessage(
      base64Audio,
      (chunk) => _bluetoothService.sendMessage(chunk),
    );

    if (success) {
      chatMessage.status = MessageStatus.sent;
      voiceMessage.status = MessageStatus.sent;
      addStructuredDebug({
        'source': 'VOICE',
        'event': 'Voice message sent successfully',
        'metrics': {
          'base64Length': base64Audio.length,
          'chunkCount': (base64Audio.length / 28).ceil(),
        }
      });
    } else {
      chatMessage.status = MessageStatus.failed;
      voiceMessage.status = MessageStatus.failed;
      addStructuredDebug({
        'source': 'VOICE',
        'event': 'Voice message send failed',
        'metrics': {'base64Length': base64Audio.length}
      });
    }

    notifyListeners();
    return success;
  }

  /// Play voice message
  Future<bool> playVoiceMessage(voice.VoiceMessage voiceMessage) async {
    return await _voiceExtension.playVoiceMessage(voiceMessage.base64Audio);
  }

  /// Stop current playback
  Future<void> stopPlayback() async {
    await _voiceExtension.stopPlayback();
  }

  void _addMessage(String text, bool isMe, [ChatMessage? message]) {
    if (message == null) {
      message = ChatMessage(
        text: text,
        isMe: isMe,
        timestamp: DateTime.now(),
        status: isMe ? MessageStatus.sent : MessageStatus.delivered,
        type: voice.MessageType.text,
      );
    }
    
    _messages.add(message);
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

  /// Add structured debug log with rich telemetry
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
    if (logEntry['metrics'].isNotEmpty) {
      final metrics = logEntry['metrics'] as Map<String, dynamic>;
      final metricsStr = metrics.entries
          .map((e) => '${e.key}=${e.value}')
          .join(', ');
      _debugLogs.add('$logString ($metricsStr)');
    } else {
      _debugLogs.add(logString);
    }
    
    if (_debugLogs.length > 100) {
      _debugLogs.removeAt(0);
    }
    notifyListeners();
  }

  /// Validate Base64 string format
  bool _isValidBase64(String str) {
    if (str.isEmpty) return false;
    // Check if string contains only valid Base64 characters
    final base64Pattern = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');
    return base64Pattern.hasMatch(str);
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _debugSubscription?.cancel();
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
  sending,
  sent,
  delivered,
  failed,
  received,
}
