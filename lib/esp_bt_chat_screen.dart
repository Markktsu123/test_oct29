import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:intl/intl.dart';
import 'providers/chat_provider.dart';
import 'voice_chat_extension.dart' as voice;

class ESP32ChatScreen extends StatefulWidget {
  const ESP32ChatScreen({super.key});

  @override
  State<ESP32ChatScreen> createState() => _ESP32ChatScreenState();
}

class _ESP32ChatScreenState extends State<ESP32ChatScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _debugScrollController = ScrollController();
  bool _isDebugConsoleVisible = false;
  bool _isRecording = false;
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _waveController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _waveController.repeat();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadPairedDevices();
    });
    
    // Listen to voice extension recording state
    context.read<ChatProvider>().voiceExtension.recordingStream.listen((isRecording) {
      if (mounted) {
        setState(() {
          _isRecording = isRecording;
        });
      }
    });

    // Start/stop wave animation with playback
    context.read<ChatProvider>().voiceExtension.playingStream.listen((isPlaying) {
      if (!mounted) return;
      if (isPlaying) {
        if (!_waveController.isAnimating) {
          _waveController.forward(from: 0);
        }
      } else {
        _waveController.stop();
      }
    });
  }

  void _sendMessage() {
    if (_messageController.text.trim().isNotEmpty) {
      context.read<ChatProvider>().sendMessage(_messageController.text);
      _messageController.clear();
      _scrollToBottom();
    }
  }

  Future<void> _startRecording() async {
    final provider = context.read<ChatProvider>();
    if (provider.isConnected) {
      final success = await provider.startRecording();
      if (success) {
        setState(() {
          _isRecording = true;
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _stopRecording() async {
    if (_isRecording) {
      final provider = context.read<ChatProvider>();
      await provider.stopRecordingAndSend();
      setState(() {
        _isRecording = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _playVoiceMessage(voice.VoiceMessage voiceMessage) async {
    final provider = context.read<ChatProvider>();
    await provider.playVoiceMessage(voiceMessage);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  void _showDeviceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.bluetooth, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('Select ESP32 Device'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Consumer<ChatProvider>(
            builder: (context, provider, child) {
              return Column(
                children: [
                  // Connection status
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: provider.isConnected ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: provider.isConnected ? Colors.green : Colors.red,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          provider.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                          color: provider.isConnected ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          provider.isConnected 
                              ? 'Connected to ${provider.selectedDevice?.name ?? "ESP32"}' 
                              : 'No device connected',
                          style: TextStyle(
                            color: provider.isConnected ? Colors.green[700] : Colors.red[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Refresh button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Paired Devices',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ElevatedButton.icon(
                        onPressed: provider.isConnecting ? null : () {
                          provider.loadPairedDevices();
                        },
                        icon: provider.isConnecting 
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        label: Text(provider.isConnecting ? 'Connecting...' : 'Refresh'),
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
                    child: provider.pairedDevices.isEmpty
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
                                  'No paired devices found',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Please pair with ESP32_NodeA first',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: provider.pairedDevices.length,
                            itemBuilder: (context, index) {
                              final device = provider.pairedDevices[index];
                              final isSelected = provider.selectedDevice?.address == device.address;
                              final isConnected = provider.isConnected && isSelected;
                              
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: isSelected ? Colors.blue[50] : null,
                                child: ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isConnected ? Colors.green[50] : Colors.blue[50],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                                      color: isConnected ? Colors.green : Colors.blue,
                                    ),
                                  ),
                                  title: Text(
                                    device.name ?? 'Unknown Device',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    'Address: ${device.address}',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                  trailing: isConnected
                                      ? ElevatedButton(
                                          onPressed: () {
                                            provider.disconnect();
                                            Navigator.pop(context);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text('Disconnect'),
                                        )
                                      : ElevatedButton(
                                          onPressed: provider.isConnecting ? null : () async {
                                            bool success = await provider.connectToDevice(device);
                                            if (success) {
                                              Navigator.pop(context);
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: Text(provider.isConnecting ? 'Connecting...' : 'Connect'),
                                        ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
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

  void _toggleDebugConsole() {
    setState(() {
      _isDebugConsoleVisible = !_isDebugConsoleVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          children: [
            const Text(
              'ESP32 Bluetooth Chat',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Consumer<ChatProvider>(
              builder: (context, provider, child) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      provider.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: provider.isConnected ? Colors.blue : Colors.grey,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      provider.isConnected ? 'Connected' : 'Disconnected',
                      style: TextStyle(
                        color: provider.isConnected ? Colors.blue : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _toggleDebugConsole,
            icon: Icon(
              _isDebugConsoleVisible ? Icons.bug_report : Icons.bug_report_outlined,
              color: Colors.blue,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: _showDeviceDialog,
              icon: const Icon(Icons.bluetooth, color: Colors.white, size: 18),
              label: const Text(
                'Devices',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
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
            child: Consumer<ChatProvider>(
              builder: (context, provider, child) {
                return provider.messages.isEmpty
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
                              'Connect to ESP32 and start chatting!',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: provider.messages.length,
                        itemBuilder: (context, index) {
                          return _buildMessageBubble(provider.messages[index]);
                        },
                      );
              },
            ),
          ),
          // Debug console
          if (_isDebugConsoleVisible)
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                border: const Border(top: BorderSide(color: Colors.grey)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      border: const Border(bottom: BorderSide(color: Colors.grey)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Debug Console',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () {
                                context.read<ChatProvider>().clearDebugLogs();
                              },
                              icon: const Icon(Icons.clear, color: Colors.white, size: 20),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _isDebugConsoleVisible = false;
                                });
                              },
                              icon: const Icon(Icons.close, color: Colors.white, size: 20),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Consumer<ChatProvider>(
                      builder: (context, provider, child) {
                        return ListView.builder(
                          controller: _debugScrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: provider.debugLogs.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                provider.debugLogs[index],
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
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
            child: Row(
              children: [
                // Voice recording button with tap-to-toggle and wave indicator
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (_isRecording) {
                          _stopRecording();
                        } else {
                          _startRecording();
                        }
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _isRecording ? Colors.red : Colors.grey[300],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isRecording ? Icons.stop : Icons.mic,
                          color: _isRecording ? Colors.white : Colors.grey[600],
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _RecordingWave(levelStream: context.read<ChatProvider>().voiceExtension.levelStream, active: _isRecording),
                  ],
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
                      color: Colors.blue,
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
                // Message content
                if (message.type == voice.MessageType.voice && message.voiceMessage != null)
                  _buildVoiceMessageContent(message.voiceMessage!)
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

  Widget _buildVoiceMessageContent(voice.VoiceMessage voiceMessage) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        final isPlaying = provider.currentlyPlayingMessageId == voiceMessage.id && provider.voiceExtension.isPlaying;
        return GestureDetector(
          onTap: () => _playVoiceMessage(voiceMessage),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isPlaying)
                  Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 20,
                  )
                else
                  _PlaybackWave(animation: _waveController),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice Message',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${voiceMessage.formattedSize} • ${voiceMessage.formattedDuration}',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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
      case MessageStatus.received:
        icon = Icons.done_all;
        color = Colors.blue[300]!;
        break;
      case MessageStatus.failed:
        icon = Icons.error;
        color = Colors.red[300]!;
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
}

class _RecordingWave extends StatelessWidget {
  final Stream<double> levelStream;
  final bool active;
  const _RecordingWave({required this.levelStream, required this.active});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: levelStream,
      initialData: 0.0,
      builder: (context, snapshot) {
        final level = (snapshot.data ?? 0.0).clamp(0.0, 1.0);
        final bars = 5;
        final List<Widget> children = [];
        for (int i = 0; i < bars; i++) {
          final variance = (1.0 - (i - 2).abs() * 0.15); // center bars taller
          final double h = 8.0 + (active ? level * 40.0 * variance : 0.0);
          children.add(AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: 4,
            height: h,
            decoration: BoxDecoration(
              color: active ? Colors.red : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ));
          if (i != bars - 1) children.add(const SizedBox(width: 3));
        }
        return Row(children: children);
      },
    );
  }
}

class _PlaybackWave extends StatelessWidget {
  final Animation<double> animation;
  const _PlaybackWave({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value; // 0..1
        final bars = 5;
        final List<Widget> children = [];
        for (int i = 0; i < bars; i++) {
          final double phase = (i * 0.6);
          final double wave = (0.5 + 0.5 * (math.sin((t * 2 * math.pi) + phase)));
          final double h = 12.0 + wave * 18.0; // 12..30
          children.add(Container(
            width: 4,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ));
        }
        return Row(children: children);
      },
    );
  }
}
