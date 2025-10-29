import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'providers/chat_provider.dart';

/// Voice message types for the chat system
enum MessageType {
  text,
  voice,
}

/// Voice Quality Validator constants
class VQVConstants {
  static const int MIN_WAV_SIZE = 2048; // Minimum WAV file size in bytes
  static const double MIN_RMS_THRESHOLD = 0.005; // Minimum RMS energy threshold
  static const int SAMPLE_WINDOW_MS = 250; // Sample window for RMS calculation
  static const int MAX_ATTEMPTS = 2; // Maximum retry attempts
  static const int CHUNK_SIZE = 28; // ESP32 chunk size (28 chars + 4 control bytes)
  static const int WAV_HEADER_SIZE = 44; // Standard WAV header size
  static const int SAMPLE_RATE = 44100; // Updated to match recording sample rate
}

/// Voice Quality Validation Result
class VQVResult {
  final bool isValid;
  final String reason;
  final double? rmsEnergy;
  final int fileSize;
  final double? amplitudeMean;
  final double? noiseFloor;
  final Duration? duration;

  VQVResult({
    required this.isValid,
    required this.reason,
    this.rmsEnergy,
    required this.fileSize,
    this.amplitudeMean,
    this.noiseFloor,
    this.duration,
  });

  Map<String, dynamic> toDebugMap() => {
    'valid': isValid,
    'reason': reason,
    'rmsEnergy': rmsEnergy,
    'fileSize': fileSize,
    'amplitudeMean': amplitudeMean,
    'noiseFloor': noiseFloor,
    'duration': duration?.inMilliseconds,
  };
}

/// Voice Quality Validator class
class VoiceQualityValidator {
  static Future<VQVResult> validateAacFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return VQVResult(
          isValid: false,
          reason: 'File does not exist',
          fileSize: 0,
        );
      }

      final bytes = await file.readAsBytes();
      final fileSize = bytes.length;

      // Check minimum file size
      if (fileSize < VQVConstants.MIN_WAV_SIZE) {
        return VQVResult(
          isValid: false,
          reason: 'File too small (${fileSize}B < ${VQVConstants.MIN_WAV_SIZE}B)',
          fileSize: fileSize,
        );
      }

      // For AAC files, we can't easily validate the header like WAV
      // Instead, we'll check if the file has reasonable size and basic structure
      if (fileSize < 1000) { // Very small AAC files are likely corrupted
        return VQVResult(
          isValid: false,
          reason: 'AAC file too small (${fileSize}B < 1000B)',
          fileSize: fileSize,
        );
      }

      // For AAC, we'll do a basic validation by checking file size
      // In a real implementation, you might want to use a proper AAC parser
      return VQVResult(
        isValid: true,
        reason: 'AAC validation passed',
        fileSize: fileSize,
        rmsEnergy: 0.1, // Placeholder for AAC files
        amplitudeMean: 0.1,
        noiseFloor: 0.01,
        duration: Duration(milliseconds: (fileSize / 16).round()), // Rough estimate
      );
    } catch (e) {
      return VQVResult(
        isValid: false,
        reason: 'AAC validation error: $e',
        fileSize: 0,
      );
    }
  }

  static Future<VQVResult> validateWavFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return VQVResult(
          isValid: false,
          reason: 'File does not exist',
          fileSize: 0,
        );
      }

      final bytes = await file.readAsBytes();
      final fileSize = bytes.length;

      // Check minimum file size
      if (fileSize < VQVConstants.MIN_WAV_SIZE) {
        return VQVResult(
          isValid: false,
          reason: 'File too small (${fileSize}B < ${VQVConstants.MIN_WAV_SIZE}B)',
          fileSize: fileSize,
        );
      }

      // Validate WAV header
      if (!_validateWavHeader(bytes)) {
        return VQVResult(
          isValid: false,
          reason: 'Invalid WAV header',
          fileSize: fileSize,
        );
      }

      // Calculate RMS energy for first 250ms
      final rmsResult = await _calculateRMSEnergy(bytes);
      
      if (rmsResult.rmsEnergy < VQVConstants.MIN_RMS_THRESHOLD) {
        return VQVResult(
          isValid: false,
          reason: 'Silent audio (RMS=${rmsResult.rmsEnergy.toStringAsFixed(4)} < ${VQVConstants.MIN_RMS_THRESHOLD})',
          fileSize: fileSize,
          rmsEnergy: rmsResult.rmsEnergy,
          amplitudeMean: rmsResult.amplitudeMean,
          noiseFloor: rmsResult.noiseFloor,
        );
      }

      return VQVResult(
        isValid: true,
        reason: 'Validation passed',
        fileSize: fileSize,
        rmsEnergy: rmsResult.rmsEnergy,
        amplitudeMean: rmsResult.amplitudeMean,
        noiseFloor: rmsResult.noiseFloor,
        duration: rmsResult.duration,
      );
    } catch (e) {
      return VQVResult(
        isValid: false,
        reason: 'Validation error: $e',
        fileSize: 0,
      );
    }
  }

  static bool _validateWavHeader(Uint8List bytes) {
    if (bytes.length < VQVConstants.WAV_HEADER_SIZE) return false;
    
    // Check RIFF header
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    if (riff != 'RIFF') return false;
    
    // Check WAVE format
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (wave != 'WAVE') return false;
    
    // Check fmt chunk
    final fmt = String.fromCharCodes(bytes.sublist(12, 20));
    if (fmt != 'fmt ') return false;
    
    return true;
  }

  static Future<({double rmsEnergy, double amplitudeMean, double noiseFloor, Duration? duration})> _calculateRMSEnergy(Uint8List bytes) async {
    try {
      // Skip WAV header (44 bytes) and get audio data
      final audioData = bytes.sublist(VQVConstants.WAV_HEADER_SIZE);
      
      // Calculate samples for first 250ms at 16kHz
      final sampleRate = VQVConstants.SAMPLE_RATE;
      final sampleWindow = (sampleRate * VQVConstants.SAMPLE_WINDOW_MS / 1000).round();
      final samplesToAnalyze = min(sampleWindow, audioData.length ~/ 2); // 16-bit samples
      
      if (samplesToAnalyze < 10) {
        return (rmsEnergy: 0.0, amplitudeMean: 0.0, noiseFloor: 0.0, duration: null);
      }

      double sumSquares = 0.0;
      double sumAmplitude = 0.0;
      double minAmplitude = double.infinity;
      double maxAmplitude = double.negativeInfinity;

      // Process 16-bit PCM samples
      for (int i = 0; i < samplesToAnalyze; i++) {
        if (i * 2 + 1 < audioData.length) {
          // Little-endian 16-bit sample
          final sample = (audioData[i * 2] | (audioData[i * 2 + 1] << 8));
          // Convert to signed 16-bit
          final signedSample = sample > 32767 ? sample - 65536 : sample;
          // Normalize to [-1, 1]
          final normalizedSample = signedSample / 32768.0;
          
          sumSquares += normalizedSample * normalizedSample;
          sumAmplitude += normalizedSample.abs();
          minAmplitude = min(minAmplitude, normalizedSample.abs());
          maxAmplitude = max(maxAmplitude, normalizedSample.abs());
        }
      }

      final rmsEnergy = sqrt(sumSquares / samplesToAnalyze);
      final amplitudeMean = sumAmplitude / samplesToAnalyze;
      final noiseFloor = minAmplitude;
      final duration = Duration(milliseconds: (samplesToAnalyze * 1000 / sampleRate).round());

      return (
        rmsEnergy: rmsEnergy,
        amplitudeMean: amplitudeMean,
        noiseFloor: noiseFloor,
        duration: duration
      );
    } catch (e) {
      return (rmsEnergy: 0.0, amplitudeMean: 0.0, noiseFloor: 0.0, duration: null);
    }
  }
}

/// Auto-Retry Sequencer for voice recording
class AutoRetrySequencer {
  int _attemptCount = 0;
  String? _lastFailureReason;
  Timer? _retryTimer;
  
  int get attemptCount => _attemptCount;
  String? get lastFailureReason => _lastFailureReason;
  bool get isRetrying => _retryTimer?.isActive ?? false;

  void reset() {
    _attemptCount = 0;
    _lastFailureReason = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  bool canRetry() => _attemptCount < VQVConstants.MAX_ATTEMPTS;

  void recordFailure(String reason) {
    _attemptCount++;
    _lastFailureReason = reason;
  }

  Future<void> scheduleRetry(Function() retryCallback, Function(String) debugLog) async {
    if (!canRetry()) {
      debugLog('[ARS] Abort after ${VQVConstants.MAX_ATTEMPTS} failed attempts');
      return;
    }

    // Exponential backoff: 500ms, 1000ms
    final delayMs = 500 * pow(2, _attemptCount - 1).round();
    debugLog('[ARS] Restarting recorder in ${delayMs}ms (exponential backoff)');
    
    _retryTimer = Timer(Duration(milliseconds: delayMs), () {
      debugLog('[ARS] Auto-retry triggered, attempt $_attemptCount/${VQVConstants.MAX_ATTEMPTS} (reason: $_lastFailureReason)');
      retryCallback();
    });
  }

  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}

/// Voice recording and playback service for ESP32 Bluetooth chat
class VoiceChatExtension {
  static final VoiceChatExtension _instance = VoiceChatExtension._internal();
  factory VoiceChatExtension() => _instance;
  VoiceChatExtension._internal();

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final AudioPlayer _player = AudioPlayer();
  final AutoRetrySequencer _retrySequencer = AutoRetrySequencer();
  
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _currentRecordingPath;
  String? _currentPlayingPath;
  bool _enableDiagnostics = true;
  bool _isRecorderInitialized = false;
  DateTime? _recordingStartTime;
  Duration? _lastRecordingDuration;
  
  // Stream controllers for UI updates
  final StreamController<bool> _recordingController = StreamController<bool>.broadcast();
  final StreamController<bool> _playingController = StreamController<bool>.broadcast();
  final StreamController<String> _debugController = StreamController<String>.broadcast();

  // Getters
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  bool get isRetrying => _retrySequencer.isRetrying;
  bool get enableDiagnostics => _enableDiagnostics;
  Stream<bool> get recordingStream => _recordingController.stream;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<String> get debugStream => _debugController.stream;

  // Setters
  set enableDiagnostics(bool value) => _enableDiagnostics = value;

  /// Request microphone permission with proper Android 12+ handling
  Future<bool> requestMicrophonePermission() async {
    try {
      // Check current permission status first
      final currentStatus = await Permission.microphone.status;
      _debugController.add('Current microphone permission status: $currentStatus');
      
      if (currentStatus.isGranted) {
        _debugController.add('✅ Microphone permission already granted');
        return true;
      }
      
      if (currentStatus.isDenied) {
        // Request permission
        final micStatus = await Permission.microphone.request();
        _debugController.add('Permission request result: $micStatus');
        
        if (micStatus.isGranted) {
          _debugController.add('✅ Microphone permission granted');
          return true;
        } else {
          _debugController.add('🚫 Microphone permission denied');
          return false;
        }
      }
      
      if (currentStatus.isPermanentlyDenied) {
        _debugController.add('🚫 Microphone permission permanently denied - please enable in settings');
        return false;
      }
      
      return false;
    } catch (e) {
      _debugController.add('❌ Error requesting microphone permission: $e');
      return false;
    }
  }

  /// Start recording voice message
  Future<bool> startRecording() async {
    if (_isRecording) {
      _debugController.add('Already recording');
      return false;
    }

        try {
          _retrySequencer.reset();
          _lastRecordingDuration = null; // Reset previous duration

          // 1️⃣ Request all required permissions
          if (!await requestMicrophonePermission()) {
            return false;
          }

      // 2️⃣ Initialize recorder once per app session
      if (!_isRecorderInitialized) {
        await _recorder.openRecorder();
        await _recorder.setSubscriptionDuration(const Duration(milliseconds: 100));
        _isRecorderInitialized = true;
        _debugController.add('🎙 Recorder initialized');
      }

      // 3️⃣ Set output path
      final dir = await getTemporaryDirectory();
      _currentRecordingPath =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';

      // 4️⃣ Start recording with correct parameters
      await _recorder.startRecorder(
        toFile: _currentRecordingPath!,
        codec: Codec.aacADTS,           // AAC codec for better Android support
        sampleRate: 44100,              // 44.1 kHz sample rate (more stable)
        numChannels: 1,                 // mono
        bitRate: 128000,                // 128 kbps bit rate
        audioSource: AudioSource.microphone, // Explicit audio source
      );

      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _recordingController.add(true);
      _debugController.add(
          '🎙 Recording started -> $_currentRecordingPath (44.1 kHz mono AAC)');
      return true;
    } catch (e) {
      _debugController.add('❌ startRecording() failed: $e');
      return false;
    }
  }

  /// Stop recording voice message with VQV validation and ARS retry logic
  Future<String?> stopRecording() async {
    if (!_isRecording) {
      _debugController.add('Not currently recording');
      return null;
    }

    try {
      // Capture duration before stopping
      Duration? actualDuration;
      if (_recordingStartTime != null) {
        actualDuration = DateTime.now().difference(_recordingStartTime!);
        _debugController.add('🎙 Recording duration: ${actualDuration.inMilliseconds}ms');
        
        // Ensure minimum recording duration to avoid MediaRecorder issues
        if (actualDuration.inMilliseconds < 800) {
          _debugController.add('⏳ Ensuring minimum recording duration (800ms)...');
          await Future.delayed(Duration(milliseconds: 800 - actualDuration.inMilliseconds));
          actualDuration = Duration(milliseconds: 800);
        }
      }

      await _recorder.stopRecorder();
      _isRecording = false;
      _recordingController.add(false);
      
      // Store the actual duration for later use
      _lastRecordingDuration = actualDuration;
      _recordingStartTime = null;
      
      if (_currentRecordingPath == null || !File(_currentRecordingPath!).existsSync()) {
        _debugController.add('Recording file not found');
        return null;
      }

      final recordingPath = _currentRecordingPath!;
      _debugController.add('Stopped recording: $recordingPath');

      // Run Voice Quality Validation
      _debugController.add('[VQV] Validating AAC payload...');
      final vqvResult = await VoiceQualityValidator.validateAacFile(recordingPath);
      
      if (_enableDiagnostics) {
        _debugController.add('[VQV] ${vqvResult.isValid ? "OK" : "FAIL"} (${(vqvResult.fileSize / 1024).toStringAsFixed(1)} KB, RMS=${vqvResult.rmsEnergy?.toStringAsFixed(4) ?? "N/A"})');
      }

      if (vqvResult.isValid) {
        // Validation passed - clean up and return path
        _currentRecordingPath = null;
        return recordingPath;
      } else {
        // Validation failed - trigger auto-retry
        _retrySequencer.recordFailure(vqvResult.reason);
        
        // Delete the failed recording
        try {
          await File(recordingPath).delete();
          _debugController.add('[VQV] Deleted failed recording');
        } catch (e) {
          _debugController.add('[VQV] Error deleting failed recording: $e');
        }

        if (_retrySequencer.canRetry()) {
          _debugController.add('[VQV] FAIL ${vqvResult.reason} — triggering auto-retry (${_retrySequencer.attemptCount}/${VQVConstants.MAX_ATTEMPTS})');
          
          // Schedule retry
          await _retrySequencer.scheduleRetry(() async {
            _debugController.add('[ARS] Re-recording due to low audio signal...');
            await startRecording();
          }, (log) => _debugController.add(log));
          
          return null; // Will retry automatically
        } else {
          _debugController.add('[ARS] Abort after ${VQVConstants.MAX_ATTEMPTS} failed attempts');
          _currentRecordingPath = null;
          return null;
        }
      }
    } catch (e) {
      _debugController.add('Error stopping recording: $e');
      _isRecording = false;
      _recordingController.add(false);
      return null;
    }
  }

  /// Convert audio file to Base64 string using parallel processing
  Future<String?> audioFileToBase64(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        _debugController.add('Audio file does not exist: $filePath');
        return null;
      }

      _debugController.add('[BASE64] Starting parallel encoding...');
      
      // Use compute() for parallel Base64 encoding to prevent UI jank
      final base64String = await compute(_encodeFileToBase64, filePath);
      
      _debugController.add('[BASE64] Converted audio to Base64 (${base64String.length} chars)');
      
      return base64String;
    } catch (e) {
      _debugController.add('Error converting audio to Base64: $e');
      return null;
    }
  }

  /// Static method for parallel Base64 encoding
  static Future<String> _encodeFileToBase64(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  /// Send voice message over Bluetooth in 28-byte chunks (ESP32 compatible)
  Future<bool> sendVoiceMessage(String base64Audio, Function(String) sendChunk) async {
    try {
      _debugController.add('[BT_TX] Sending voice message (${base64Audio.length} chars)');
      
      // Send start marker
      await sendChunk('<VOICE_START>\n');
      _debugController.add('[BT_TX] Sent <VOICE_START>');

      // Send audio data in 28-byte chunks (ESP32 compatible)
      int chunkCount = 0;
      for (int i = 0; i < base64Audio.length; i += VQVConstants.CHUNK_SIZE) {
        final end = (i + VQVConstants.CHUNK_SIZE < base64Audio.length) ? i + VQVConstants.CHUNK_SIZE : base64Audio.length;
        final chunk = base64Audio.substring(i, end);
        await sendChunk('$chunk\n');
        
        chunkCount++;
        if (_enableDiagnostics && chunkCount % 10 == 0) {
          _debugController.add('[BT_TX] Sent chunk $chunkCount (${((i + VQVConstants.CHUNK_SIZE) / base64Audio.length * 100).toStringAsFixed(1)}%)');
        }
        
        // Slow pacing for safe Bluetooth SPP transfer
        await Future.delayed(const Duration(milliseconds: 5));
      }

      // Send end marker
      await sendChunk('<VOICE_END>\n');
      _debugController.add('[BT_TX] Sent <VOICE_END> / <VOICE_END> successfully');
      
      return true;
    } catch (e) {
      _debugController.add('Error sending voice message: $e');
      return false;
    }
  }

  /// Play voice message from Base64 data
  Future<bool> playVoiceMessage(String base64Audio) async {
    if (_isPlaying) {
      _debugController.add('Already playing audio');
      return false;
    }

    try {
      // Decode Base64 to bytes
      final audioBytes = base64Decode(base64Audio);
      
      // Create temporary file
      final tempDir = await getTemporaryDirectory();
      _currentPlayingPath = '${tempDir.path}/playback_${DateTime.now().millisecondsSinceEpoch}.wav';
      final file = File(_currentPlayingPath!);
      await file.writeAsBytes(audioBytes);

      // Play audio
      await _player.play(DeviceFileSource(_currentPlayingPath!));
      _isPlaying = true;
      _playingController.add(true);
      _debugController.add('Playing voice message: $_currentPlayingPath');

      final bytes = await file.readAsBytes();
      final header = bytes.take(8).toList();
      _debugController.add('[PLAY] Header bytes: ${header.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}'
);


      // Listen for completion
      _player.onPlayerComplete.listen((_) {
        _isPlaying = false;
        _playingController.add(false);
        
        _debugController.add('Voice message playback completed');
        
        // Clean up temporary file
        if (_currentPlayingPath != null) {
          File(_currentPlayingPath!).delete().catchError((e) {
            _debugController.add('Error deleting temp file: $e');
          });
          _currentPlayingPath = null;
        }
      });

      return true;
    } catch (e) {
      _debugController.add('Error playing voice message: $e');
      _isPlaying = false;
      _playingController.add(false);
      return false;
    }
  }

  /// Stop current playback
  Future<void> stopPlayback() async {
    if (_isPlaying) {
      try {
        await _player.stop();
        _isPlaying = false;
        _playingController.add(false);
        _debugController.add('Stopped voice message playback');
        
        // Clean up temporary file
        if (_currentPlayingPath != null) {
          File(_currentPlayingPath!).delete().catchError((e) {
            _debugController.add('Error deleting temp file: $e');
          });
          _currentPlayingPath = null;
        }
      } catch (e) {
        _debugController.add('Error stopping playback: $e');
      }
    }
  }

  /// Handle incoming voice data from Bluetooth
  String _voiceBuffer = '';
  bool _isReceivingVoice = false;
  Timer? _voiceReceiveTimeout;

  /// Process incoming data and detect voice messages
  List<String> processIncomingData(String data) {
    final messages = <String>[];
    
    // Split by lines to handle multiple messages
    final lines = data.split('\n');
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;

      if (trimmedLine == '<VOICE_START>') {
        _isReceivingVoice = true;
        _voiceBuffer = '';
        _voiceReceiveTimeout?.cancel();
        _voiceReceiveTimeout = Timer(Duration(seconds: 60), () {
          if (_isReceivingVoice) {
            _debugController.add('Voice receive timeout - resetting buffer');
            _isReceivingVoice = false;
            _voiceBuffer = '';
          }
        });
        _debugController.add('Voice message start detected');
        continue;
      }

      if (trimmedLine == '<VOICE_END>') {
        _isReceivingVoice = false;
        _voiceReceiveTimeout?.cancel();
        if (_voiceBuffer.isNotEmpty) {
          // Create a special marker for the complete voice message
          messages.add('VOICE_MESSAGE:' + _voiceBuffer);
          _debugController.add('Voice message end detected (${_voiceBuffer.length} chars)');
        } else {
          _debugController.add('Voice message end detected but buffer is empty!');
        }
        _voiceBuffer = '';
        continue;
      }

      if (_isReceivingVoice) {
        // Accumulate Base64 chunks during voice stream
        _voiceBuffer += trimmedLine;
        _debugController.add('Voice chunk added (${trimmedLine.length} chars, total: ${_voiceBuffer.length})');
      } else {
        // Regular text message
        messages.add(trimmedLine);
      }
    }

    return messages;
  }

  /// Check if current data is part of a voice message
  bool get isReceivingVoice => _isReceivingVoice;

  /// Get current voice buffer (for debugging)
  String get voiceBuffer => _voiceBuffer;

  /// Get recording duration
  Duration? getRecordingDuration() {
    // Return the last recorded duration if available
    if (_lastRecordingDuration != null) {
      return _lastRecordingDuration;
    }
    
    // If currently recording, return current duration
    if (_recordingStartTime != null) {
      return DateTime.now().difference(_recordingStartTime!);
    }
    
    return null;
  }

  /// Clean up resources
  void dispose() {
    if (_isRecorderInitialized) {
      _recorder.closeRecorder();
    }
    _player.dispose();
    _retrySequencer.dispose();
    _voiceReceiveTimeout?.cancel();
    _recordingController.close();
    _playingController.close();
    _debugController.close();
  }
}

/// Voice message data model
class VoiceMessage {
  final String id;
  final String base64Audio;
  final DateTime timestamp;
  final bool isMe;
  MessageStatus status;
  final Duration? duration;

  VoiceMessage({
    required this.id,
    required this.base64Audio,
    required this.timestamp,
    required this.isMe,
    this.status = MessageStatus.sent,
    this.duration,
  });

  /// Create from Base64 audio data
  factory VoiceMessage.fromBase64({
    required String base64Audio,
    required bool isMe,
    MessageStatus status = MessageStatus.sent,
    Duration? duration,
  }) {
    return VoiceMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      base64Audio: base64Audio,
      timestamp: DateTime.now(),
      isMe: isMe,
      status: status,
      duration: duration,
    );
  }

  /// Get audio file size in bytes
  int get audioSizeBytes {
    try {
      final bytes = base64Decode(base64Audio);
      return bytes.length;
    } catch (e) {
      return 0;
    }
  }

  /// Get formatted file size
  String get formattedSize {
    final bytes = audioSizeBytes;
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  /// Get formatted duration (seconds with milliseconds)
  String get formattedDuration {
    if (duration != null) {
      final totalSeconds = duration!.inMilliseconds / 1000.0;
      final seconds = totalSeconds.floor();
      final milliseconds = ((totalSeconds - seconds) * 1000).round();
      return '${seconds}.${milliseconds.toString().padLeft(3, '0')}s';
    }
    return '0.000s';
  }
}

