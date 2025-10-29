# ESP32 Flutter Voice Chat App

A real-time voice chat application that enables communication between two devices via ESP32 microcontrollers using Bluetooth and nRF24L01 radio modules.

## Features

- 🎤 **Voice Recording & Playback**: Record voice messages and play them back
- 📱 **Cross-Platform**: Flutter app works on Android and iOS
- 📡 **Bluetooth Communication**: Connect to ESP32 via Bluetooth SPP
- 📻 **Radio Bridge**: ESP32 acts as a bridge between devices using nRF24L01
- 🔄 **Real-time Messaging**: Send and receive text and voice messages instantly
- 🛠️ **Debug Console**: Built-in debugging tools for troubleshooting

## Architecture

```
Phone (Flutter) ←→ ESP32_NodeA ←→ nRF24L01 ←→ ESP32_NodeB ←→ Phone (Flutter)
```

## Hardware Requirements

### ESP32 Modules (2x)
- ESP32 development board
- nRF24L01 radio module
- Bluetooth capability

### Mobile Device
- Android 5.0+ or iOS 10.0+
- Bluetooth support

## Software Requirements

- Flutter SDK 3.0+
- Dart 3.0+
- Android Studio / VS Code
- Arduino IDE (for ESP32 programming)

## Installation

### 1. Clone the Repository
```bash
git clone https://github.com/YOUR_USERNAME/final_test.git
cd final_test
```

### 2. Install Flutter Dependencies
```bash
flutter pub get
```

### 3. ESP32 Setup
1. Install ESP32 board support in Arduino IDE
2. Install required libraries:
   - `nRF24L01` by TMRh20
   - `BluetoothSerial`
3. Upload the ESP32 code to both modules

### 4. Run the App
```bash
flutter run
```

## Usage

1. **Pair ESP32**: Connect your phone to the ESP32 via Bluetooth
2. **Start Chat**: Open the app and select your paired device
3. **Send Messages**: Type text or hold the microphone to record voice
4. **Debug**: Use the debug console to monitor communication

## Voice Message Protocol

The app uses a structured protocol for voice messages:

- **Chunk Size**: 28 bytes (4-byte aligned)
- **Format**: Base64 encoded AAC audio
- **Bitrate**: 128 kbps
- **Sample Rate**: 44.1 kHz
- **Channels**: Mono

## Debug Console

The debug console shows:
- Bluetooth connection status
- Voice message processing
- Base64 encoding/decoding
- File size and duration calculations
- Error messages and warnings

## Troubleshooting

### Common Issues

1. **Voice messages show 0KB**
   - Check Base64 data integrity
   - Verify ESP32 chunk transmission
   - Monitor debug console for errors

2. **Bluetooth connection fails**
   - Ensure ESP32 is in pairing mode
   - Check device compatibility
   - Restart Bluetooth on phone

3. **Voice playback issues**
   - Verify AAC format compatibility
   - Check file size calculations
   - Monitor debug logs for decoding errors

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── esp_bt_chat_screen.dart   # Main chat UI
├── voice_chat_extension.dart # Voice recording/playback
├── providers/
│   └── chat_provider.dart    # State management
└── services/
    └── bluetooth_service.dart # Bluetooth communication
```

## Dependencies

- `flutter_bluetooth_serial_plus`: Bluetooth communication
- `flutter_sound`: Audio recording and playback
- `audioplayers`: Audio playback
- `path_provider`: File system access
- `permission_handler`: Runtime permissions

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## Support

For issues and questions:
- Create an issue on GitHub
- Check the debug console for error messages
- Review the troubleshooting section

## Version History

- **v1.0.0**: Initial release with basic voice chat functionality
- **v1.1.0**: Added debug console and improved error handling
- **v1.2.0**: Enhanced voice message validation and Base64 processing