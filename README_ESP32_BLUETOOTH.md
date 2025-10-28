# ESP32 Bluetooth Chat App

This Flutter app establishes a bi-directional serial stream with an ESP32 device via **Classic Bluetooth (SPP)**, matching the communication protocol of the provided C++ firmware.

## Features

- **Classic Bluetooth (SPP) Communication**: Uses `flutter_bluetooth_serial` package for Classic Bluetooth communication
- **Auto-Discovery**: Automatically discovers and pairs with "ESP32_NodeA"
- **Persistent Connection**: Maintains a persistent asynchronous stream using `BluetoothConnection.toAddress()`
- **Real-time Messaging**: Send and receive messages in real-time
- **CRLF Line Termination**: Ensures compatibility with ESP32 firmware by using `\n` line termination
- **Error Handling**: Comprehensive error handling for disconnects, failed pairing, and missing permissions
- **State Management**: Uses Provider for reactive state management
- **Debug Console**: Built-in debug console for monitoring Bluetooth I/O

## ESP32 Firmware Compatibility

The app is designed to work with ESP32 firmware that:
- Uses `BluetoothSerial` (SPP) with `SerialBT.begin("ESP32_NodeA")`
- Sends/receives plain UTF-8 text lines terminated by '\n'
- Forwards messages via nRF24L01+ to another ESP32 node
- Echoes incoming RF data back over Bluetooth

## Setup Instructions

1. **Pair ESP32 Device**: First, pair your ESP32 device with your phone using the device's Bluetooth settings. The ESP32 should be named "ESP32_NodeA".

2. **Run the App**: Launch the Flutter app and tap the "Devices" button to see paired devices.

3. **Connect**: Select your ESP32 device from the list and tap "Connect".

4. **Start Chatting**: Once connected, you can send messages that will be forwarded to the other ESP32 node via nRF24L01+.

## File Structure

- `lib/main.dart` - Main app entry point with Provider setup
- `lib/esp_bt_chat_screen.dart` - Main chat interface
- `lib/services/bluetooth_service.dart` - Bluetooth Classic communication service
- `lib/providers/chat_provider.dart` - State management for chat functionality

## Dependencies

- `flutter_bluetooth_serial: ^0.4.0` - Classic Bluetooth communication
- `provider: ^6.1.1` - State management
- `permission_handler: ^11.0.1` - Bluetooth permissions
- `intl: ^0.19.0` - Date/time formatting

## Permissions

The app requires the following permissions:
- `BLUETOOTH`
- `BLUETOOTH_ADMIN`
- `BLUETOOTH_CONNECT`
- `BLUETOOTH_SCAN`
- `ACCESS_FINE_LOCATION`

## Usage

1. **Connect to ESP32**: Tap "Devices" → Select "ESP32_NodeA" → Tap "Connect"
2. **Send Messages**: Type in the text field and tap send
3. **View Messages**: Incoming messages from ESP32 will appear in the chat
4. **Debug Console**: Tap the bug icon to view Bluetooth communication logs
5. **Disconnect**: Use the "Disconnect" button in the device list

## Troubleshooting

- **No devices found**: Ensure ESP32 is paired with your phone first
- **Connection failed**: Check if ESP32 is in pairing mode and named "ESP32_NodeA"
- **Messages not sending**: Verify Bluetooth connection status in the app
- **Permission denied**: Grant all required Bluetooth permissions in device settings
