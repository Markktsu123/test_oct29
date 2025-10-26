# ESP32 LoRa Chat - Flutter App

A modern Flutter chat application with voice recording capabilities, designed for ESP32 LoRa communication testing. Features dynamic voice-responsive waveforms, Bluetooth connectivity, and a clean, intuitive interface.

## 🌟 Features

### 🎤 **Voice Recording & Playback**
- **Real-time voice recording** with dynamic waveform visualization
- **Voice activity detection** - waveforms respond to actual voice input
- **High-quality audio** - AAC format (128kbps, 44.1kHz)
- **Interactive playback** - click anywhere on voice messages to play/pause
- **Visual feedback** - animated waveforms during recording and playback

### 🔵 **Bluetooth Connectivity**
- **In-app device discovery** - no need to go to Android settings
- **One-tap connection** to ESP32 devices
- **Connection status** - visual indicators in header
- **Professional device list** with device information

### 💬 **Messaging Features**
- **Text messaging** with real-time status indicators
- **Message status** - sending, sent, delivered, seen
- **Smart date/time** - today, yesterday, or full date
- **Clean UI** - matches modern chat app design

### 🎨 **Visual Design**
- **Dynamic waveforms** with gradient colors and shadows
- **Voice detection** - visual indicators for voice activity
- **Smooth animations** - 60-100ms transitions with easing
- **Professional UI** - modern Material Design

## 📱 Screenshots

### Voice Recording
- Real-time waveform visualization during recording
- Voice activity detection with color-coded response
- Professional recording interface

### Bluetooth Connection
- In-app device discovery and connection
- Visual connection status indicators
- Easy ESP32 device pairing

### Chat Interface
- Clean message bubbles with status indicators
- Voice messages with waveform display
- Intuitive user interface

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.0.0 or higher)
- Android Studio or VS Code
- Android device for testing

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/esp32-lora-chat.git
   cd esp32-lora-chat
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

### Building APK

1. **Build release APK**
   ```bash
   flutter build apk --release
   ```

2. **APK location**
   ```
   build/app/outputs/flutter-apk/app-release.apk
   ```

## 📋 Dependencies

- `flutter_sound: ^9.2.13` - Audio recording and playback
- `flutter_blue_plus: ^1.12.13` - Bluetooth connectivity
- `permission_handler: ^11.0.1` - Runtime permissions
- `intl: ^0.19.0` - Date/time formatting
- `path_provider: ^2.1.1` - File system access

## 🔧 Technical Details

### Voice Recording
- **Format**: AAC (Advanced Audio Coding)
- **Bitrate**: 128kbps
- **Sample Rate**: 44.1kHz
- **File Extension**: .aac

### Waveform Visualization
- **Update Rate**: 80ms for smooth animation
- **Data Points**: 60 points for optimal performance
- **Height Range**: 4-40px based on voice activity
- **Color Coding**: Red for voice, orange for low activity, dim for silence

### Bluetooth
- **Protocol**: Bluetooth Low Energy (BLE)
- **Device Discovery**: 10-second scan timeout
- **Connection**: One-tap connection to ESP32 devices

## 📱 Permissions

The app automatically requests the following permissions:
- **Microphone** - For voice recording
- **Bluetooth** - For ESP32 device connection
- **Location** - Required for Bluetooth scanning
- **Storage** - For saving voice recordings

## 🎯 Use Cases

- **ESP32 LoRa Communication** - Test voice and text messages over LoRa
- **Voice Messaging Apps** - Professional voice chat interface
- **IoT Device Communication** - Connect to ESP32 devices via Bluetooth
- **Audio Recording** - High-quality voice recording with visualization

## 🔮 Future Enhancements

- [ ] Real ESP32 LoRa integration
- [ ] Message encryption
- [ ] Group messaging
- [ ] File sharing
- [ ] Push notifications
- [ ] Voice message transcription

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📞 Support

If you have any questions or need help, please open an issue on GitHub.

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- ESP32 community for LoRa communication protocols
- Open source audio libraries for voice recording capabilities

---

**Made with ❤️ for ESP32 LoRa communication testing**