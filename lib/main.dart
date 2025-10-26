import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:async';

void main() {
  runApp(const ESP32LoRaChatApp());
}

class ESP32LoRaChatApp extends StatelessWidget {
  const ESP32LoRaChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 LoRa Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      home: const ChatScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isConnected = false;
  bool _isRecording = false;
  bool _isBluetoothConnected = false;
  bool _isScanning = false;
  List<double> _recordingWaveform = [];
  Timer? _waveformTimer;
  double _currentAudioLevel = 0.0;
  double _maxAudioLevel = 0.0;
  bool _isVoiceDetected = false;
  
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  String? _recordingPath;
  String? _currentlyPlayingId;
  BluetoothDevice? _selectedDevice;
  List<BluetoothDevice> _bluetoothDevices = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _initAudio();
    _requestPermissions();
    _initBluetooth();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.microphone,
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.storage,
    ].request();
  }

  Future<void> _initAudio() async {
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
    await _recorder!.openRecorder();
    await _player!.openPlayer();
  }

  Future<void> _initBluetooth() async {
    bool isOn = await FlutterBluePlus.isOn;
    if (isOn) {
      setState(() {
        _isBluetoothConnected = true;
      });
    }
  }

  void _sendMessage() {
    if (_messageController.text.trim().isNotEmpty) {
      final message = ChatMessage(
        text: _messageController.text.trim(),
        isMe: true,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
      );
      
      setState(() {
        _messages.add(message);
      });
      _messageController.clear();
      
      // Simulate sending process
      _simulateMessageSending(message);
    }
  }

  void _simulateMessageSending(ChatMessage message) {
    // Update status to sent
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        message.status = MessageStatus.sent;
      });
    });
    
    // Update status to delivered
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        message.status = MessageStatus.delivered;
      });
    });
    
    // Update status to seen
    Future.delayed(const Duration(seconds: 3), () {
      setState(() {
        message.status = MessageStatus.seen;
      });
    });
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.aac';
      _recordingPath = '${directory.path}/$fileName';
      
      await _recorder!.startRecorder(
        toFile: _recordingPath!,
        codec: Codec.aacADTS,
        bitRate: 128000,
        sampleRate: 44100,
      );
      
      setState(() {
        _isRecording = true;
        _recordingWaveform.clear();
      });
      
      // Start waveform animation
      _startWaveformAnimation();
    } catch (e) {
      _showSnackBar('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _recorder!.stopRecorder();
      _waveformTimer?.cancel();
      setState(() {
        _isRecording = false;
      });
      
      if (_recordingPath != null && File(_recordingPath!).existsSync()) {
        final message = ChatMessage(
          text: "Voice message",
          isMe: true,
          timestamp: DateTime.now(),
          isVoiceMessage: true,
          audioPath: _recordingPath!,
          duration: const Duration(seconds: 0), // Will be updated
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          status: MessageStatus.sending,
          waveform: List.from(_recordingWaveform), // Save waveform data
        );
        
        setState(() {
          _messages.add(message);
        });
        
        // Get actual duration
        _updateAudioDuration(message);
        _simulateMessageSending(message);
      }
    } catch (e) {
      _showSnackBar('Failed to stop recording: $e');
      setState(() {
        _isRecording = false;
      });
    }
  }

  Future<void> _updateAudioDuration(ChatMessage message) async {
    try {
      // Start playing to get duration, then stop immediately
      await _player!.startPlayer(
        fromURI: message.audioPath!,
        codec: Codec.aacADTS,
      );
      
      // Wait a bit to get the duration
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Get the actual duration from the player
      // Note: flutter_sound doesn't have getDuration, so we'll use a default
      final duration = const Duration(seconds: 3);
      await _player!.stopPlayer();
      
      setState(() {
        message.duration = duration;
      });
    } catch (e) {
      // If we can't get duration, use a default
      setState(() {
        message.duration = const Duration(seconds: 3);
      });
    }
  }

  Future<void> _playVoiceMessage(String audioPath, String messageId) async {
    try {
      if (_currentlyPlayingId == messageId) {
        // If same message is playing, pause/resume
        if (_player!.isPlaying) {
          await _player!.pausePlayer();
          setState(() {
            _currentlyPlayingId = null;
          });
        } else {
          await _player!.resumePlayer();
          setState(() {
            _currentlyPlayingId = messageId;
          });
        }
      } else {
        // Play new message
        await _player!.stopPlayer();
        await _player!.startPlayer(
          fromURI: audioPath,
          codec: Codec.aacADTS,
        );
        setState(() {
          _currentlyPlayingId = messageId;
        });
        
        // Set a timer to reset playing state after estimated duration
        Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _currentlyPlayingId = null;
            });
          }
        });
      }
    } catch (e) {
      _showSnackBar('Failed to play audio: $e');
      setState(() {
        _currentlyPlayingId = null;
      });
    }
  }

  Future<void> _scanForDevices() async {
    setState(() {
      _isScanning = true;
      _bluetoothDevices.clear();
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    
    _scanSubscription = FlutterBluePlus.scanResults.listen((List<ScanResult> results) {
      for (ScanResult result in results) {
        if (!_bluetoothDevices.any((device) => device.remoteId == result.device.remoteId)) {
          setState(() {
            _bluetoothDevices.add(result.device);
          });
        }
      }
    });

    // Stop scanning after 10 seconds
    Timer(const Duration(seconds: 10), () {
      FlutterBluePlus.stopScan();
      setState(() {
        _isScanning = false;
      });
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        _selectedDevice = device;
        _isBluetoothConnected = true;
      });
      _showSnackBar('Connected to ${device.platformName.isNotEmpty ? device.platformName : device.remoteId.toString()}');
    } catch (e) {
      _showSnackBar('Failed to connect: $e');
    }
  }

  void _startWaveformAnimation() {
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (_isRecording) {
        setState(() {
          // Simulate more realistic voice detection
          _simulateVoiceDetection();
          
          // Add current audio level to waveform
          _recordingWaveform.add(_currentAudioLevel);
          
          // Keep only last 60 points for better visualization
          if (_recordingWaveform.length > 60) {
            _recordingWaveform.removeAt(0);
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _simulateVoiceDetection() {
    // Simulate voice activity detection with more realistic patterns
    final now = DateTime.now().millisecondsSinceEpoch;
    final timeVariation = (now % 2000) / 2000.0; // 2-second cycle
    
    // Simulate voice patterns - higher activity in middle of cycle
    final voiceActivity = _calculateVoiceActivity(timeVariation);
    
    // Add some randomness for natural variation
    final random = (now % 100) / 100.0;
    final noise = (random - 0.5) * 0.3;
    
    // Calculate final audio level
    _currentAudioLevel = (voiceActivity + noise).clamp(0.0, 1.0);
    
    // Update max level for scaling
    if (_currentAudioLevel > _maxAudioLevel) {
      _maxAudioLevel = _currentAudioLevel;
    }
    
    // Detect voice (threshold-based)
    _isVoiceDetected = _currentAudioLevel > 0.3;
  }

  double _calculateVoiceActivity(double timeVariation) {
    // Simulate different voice patterns
    if (timeVariation < 0.1) {
      // Silence at start
      return 0.1 + (timeVariation * 2);
    } else if (timeVariation < 0.3) {
      // Voice building up
      return 0.2 + (timeVariation - 0.1) * 2;
    } else if (timeVariation < 0.7) {
      // Peak voice activity
      return 0.6 + (timeVariation - 0.3) * 0.5;
    } else if (timeVariation < 0.9) {
      // Voice tapering off
      return 0.8 - (timeVariation - 0.7) * 2;
    } else {
      // Silence at end
      return 0.2 - (timeVariation - 0.9) * 2;
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showBluetoothDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.bluetooth, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('Bluetooth Devices'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              // Connection status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isBluetoothConnected ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isBluetoothConnected ? Colors.green : Colors.red,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isBluetoothConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: _isBluetoothConnected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isBluetoothConnected 
                          ? 'Connected to ESP32' 
                          : 'No device connected',
                      style: TextStyle(
                        color: _isBluetoothConnected ? Colors.green[700] : Colors.red[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Scan button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isScanning ? 'Scanning for devices...' : 'Available Devices',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isScanning ? null : _scanForDevices,
                    icon: _isScanning 
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search, size: 18),
                    label: Text(_isScanning ? 'Scanning...' : 'Scan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Device list
              Expanded(
                child: _bluetoothDevices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.bluetooth_searching,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isScanning 
                                  ? 'Searching for devices...' 
                                  : 'Tap "Scan" to find ESP32 devices',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _bluetoothDevices.length,
                        itemBuilder: (context, index) {
                          final device = _bluetoothDevices[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.bluetooth, color: Colors.blue),
                              ),
                              title: Text(
                                device.platformName.isNotEmpty 
                                    ? device.platformName 
                                    : 'ESP32 Device',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'ID: ${device.remoteId.toString().substring(0, 8)}...',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              trailing: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _connectToDevice(device);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                ),
                                child: const Text('Connect'),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _recorder?.closeRecorder();
    _player?.closePlayer();
    _scanSubscription?.cancel();
    _waveformTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {},
        ),
        title: Column(
          children: [
            const Text(
              'ESP32 LoRa Chat',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isBluetoothConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: _isBluetoothConnected ? Colors.blue : Colors.grey,
                  size: 16,
                ),
                const SizedBox(width: 4),
            Text(
                  _isBluetoothConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    color: _isBluetoothConnected ? Colors.blue : Colors.red,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: _showBluetoothDialog,
              icon: Icon(
                _isBluetoothConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                color: Colors.white,
                size: 18,
              ),
              label: Text(
                _isBluetoothConnected ? 'Connected' : 'Connect',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isBluetoothConnected ? Colors.green : Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages area
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start a conversation using ESP32 LoRa!',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),
          // Message input area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey, width: 0.2),
              ),
            ),
            child: Column(
              children: [
                // Waveform display during recording
                if (_isRecording) ...[
                  Container(
                    height: 50,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isVoiceDetected ? Colors.red[50] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: _isVoiceDetected ? Colors.red[300]! : Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Voice detection indicator
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isVoiceDetected ? Icons.mic : Icons.mic_off,
                              color: _isVoiceDetected ? Colors.red[600] : Colors.grey[500],
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isVoiceDetected ? 'Voice Detected' : 'Listening...',
                              style: TextStyle(
                                color: _isVoiceDetected ? Colors.red[600] : Colors.grey[600],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Waveform
                        Expanded(
                          child: _buildWaveform(_recordingWaveform, isRecording: true),
                        ),
                      ],
                    ),
                  ),
                ],
                Row(
                  children: [
                    // Microphone button
                    GestureDetector(
                      onTap: _toggleRecording,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _isRecording ? Colors.red : Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isRecording ? Icons.stop : Icons.mic,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Text input
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Send button
                    GestureDetector(
                      onTap: _sendMessage,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: message.isMe 
            ? MainAxisAlignment.end 
            : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: message.isMe ? Colors.blue : Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.isVoiceMessage)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _currentlyPlayingId == message.id 
                            ? Colors.blue[300]! 
                            : Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _playVoiceMessage(message.audioPath!, message.id!),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: _currentlyPlayingId == message.id 
                                          ? Colors.blue[400] 
                                          : Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Icon(
                                      _currentlyPlayingId == message.id && _player!.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(
                                    Icons.mic,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Voice Message',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatDuration(message.duration ?? Duration.zero),
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Waveform display for voice messages
                              Container(
                                height: 30,
                                width: double.infinity,
                                child: _buildWaveform(message.waveform ?? [], isRecording: false),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    message.text,
                    style: TextStyle(
                      color: message.isMe ? Colors.white : Colors.black,
                      fontSize: 16,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatDateTime(message.timestamp),
                      style: TextStyle(
                        color: message.isMe ? Colors.white70 : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    if (message.isMe) ...[
                      const SizedBox(width: 8),
                      _buildMessageStatus(message.status),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageStatus(MessageStatus status) {
    IconData icon;
    Color color;
    
    switch (status) {
      case MessageStatus.sending:
        icon = Icons.access_time;
        color = Colors.white70;
        break;
      case MessageStatus.sent:
        icon = Icons.check;
        color = Colors.white70;
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        color = Colors.white70;
        break;
      case MessageStatus.seen:
        icon = Icons.done_all;
        color = Colors.blue[200]!;
        break;
    }
    
    return Icon(icon, color: color, size: 16);
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    if (messageDate == today) {
      return DateFormat('HH:mm').format(dateTime);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday ${DateFormat('HH:mm').format(dateTime)}';
    } else {
      return DateFormat('MMM dd, HH:mm').format(dateTime);
    }
  }

  Widget _buildWaveform(List<double> waveform, {required bool isRecording}) {
    if (waveform.isEmpty) {
      // Show animated placeholder bars when no waveform data
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(30, (index) {
          return AnimatedContainer(
            duration: Duration(milliseconds: 150 + (index * 30)),
            width: 3,
            height: 6 + (index % 4) * 1.5,
            margin: const EdgeInsets.symmetric(horizontal: 0.8),
            decoration: BoxDecoration(
              color: isRecording ? Colors.red[200] : Colors.white.withOpacity(0.4),
              borderRadius: BorderRadius.circular(1.5),
            ),
          );
        }),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: waveform.asMap().entries.map((entry) {
        final index = entry.key;
        final amplitude = entry.value;
        final isPlaying = _currentlyPlayingId != null && !isRecording;
        
        // Enhanced height calculation with better scaling
        double height;
        if (isRecording) {
          // For recording, use more dynamic scaling
          height = (amplitude * 35).clamp(4.0, 35.0);
          // Add extra height for voice detection
          if (_isVoiceDetected && amplitude > 0.3) {
            height *= 1.2;
          }
        } else {
          // For playback, use more conservative scaling
          height = (amplitude * 25).clamp(6.0, 25.0);
        }
        
        // Add subtle animation based on position
        final animationOffset = (index % 3) * 0.1;
        final animatedHeight = height + (isRecording ? animationOffset * 2 : 0);
        
        return AnimatedContainer(
          duration: Duration(milliseconds: 60 + (index % 2) * 40),
          curve: Curves.easeInOut,
          width: 3,
          height: animatedHeight.clamp(4.0, 40.0),
          margin: const EdgeInsets.symmetric(horizontal: 0.8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _getWaveformColors(amplitude, isRecording, isPlaying),
            ),
            borderRadius: BorderRadius.circular(1.5),
            boxShadow: _getWaveformShadow(amplitude, isRecording, isPlaying),
          ),
        );
      }).toList(),
    );
  }

  List<Color> _getWaveformColors(double amplitude, bool isRecording, bool isPlaying) {
    if (isRecording) {
      if (_isVoiceDetected && amplitude > 0.3) {
        // High voice activity - bright red
        return [Colors.red[300]!, Colors.red[600]!, Colors.red[800]!];
      } else if (amplitude > 0.1) {
        // Low voice activity - orange
        return [Colors.orange[300]!, Colors.orange[500]!];
      } else {
        // Silence - dim red
        return [Colors.red[200]!, Colors.red[300]!];
      }
    } else if (isPlaying) {
      // Playing - blue gradient
      return [Colors.blue[200]!, Colors.blue[400]!, Colors.blue[600]!];
    } else {
      // Static - white gradient
      return [Colors.white70, Colors.white54, Colors.white38];
    }
  }

  List<BoxShadow> _getWaveformShadow(double amplitude, bool isRecording, bool isPlaying) {
    if (isRecording && _isVoiceDetected && amplitude > 0.3) {
      return [
        BoxShadow(
          color: Colors.red.withOpacity(0.4),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];
    } else if (isPlaying) {
      return [
        BoxShadow(
          color: Colors.blue.withOpacity(0.3),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];
    } else {
      return [
        BoxShadow(
          color: Colors.white.withOpacity(0.2),
          blurRadius: 1,
          offset: const Offset(0, 0.5),
        ),
      ];
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
}

class ChatMessage {
  final String text;
  final bool isMe;
  final DateTime timestamp;
  final bool isVoiceMessage;
  final String? audioPath;
  Duration? duration;
  final String? id;
  MessageStatus status;
  final List<double>? waveform;

  ChatMessage({
    required this.text,
    required this.isMe,
    required this.timestamp,
    this.isVoiceMessage = false,
    this.audioPath,
    this.duration,
    this.id,
    this.status = MessageStatus.sent,
    this.waveform,
  });
}

enum MessageStatus {
  sending,
  sent,
  delivered,
  seen,
}