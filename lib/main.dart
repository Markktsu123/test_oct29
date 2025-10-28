import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'providers/chat_provider.dart';
import 'esp_bt_chat_screen.dart';

void main() {
  runApp(const ESP32LoRaChatApp());
}

class ESP32LoRaChatApp extends StatelessWidget {
  const ESP32LoRaChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ChatProvider(),
      child: MaterialApp(
        title: 'ESP32 Bluetooth Chat',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          fontFamily: 'Roboto',
        ),
        home: const ESP32ChatScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
