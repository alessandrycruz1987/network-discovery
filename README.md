# @cappitolian/network-discovery

A Capacitor plugin for network service discovery using mDNS/Bonjour. Allows automatic server-client connection without manual IP configuration.

---

## Features

- **Publish services** on the local network (server mode)
- **Discover services** automatically (client mode)
- Pass custom metadata via TXT records (like HTTP port, version, etc.)
- Anti-ghosting IP resolution logic
- Works on **iOS** (Bonjour/NWListener) and **Android** (NSD)
- Cross-platform compatible: iOS ↔ Android in both directions
- Tested with **Capacitor 7** and **Ionic 8**

---

## Installation
```bash
npm install @cappitolian/network-discovery
npx cap sync
```

---

## Usage

### Import
```typescript
import { NetworkDiscovery } from '@cappitolian/network-discovery';
```

### Server Mode - Publish Your Service
```typescript
// Start publishing your server
await NetworkDiscovery.startServer({
  serviceName: 'SSSPOSServer',
  serviceType: '_ssspos._tcp',
  port: 8081,                    // Discovery service port
  ip: '192.168.1.100',           // Your server IP
  metadata: {
    httpPort: '8080',            // Your actual HTTP server port
    version: '1.0.0',            // Any custom data
    deviceName: 'Main Server'
  }
});

console.log('Server is now discoverable on the network');

// Stop publishing when needed
await NetworkDiscovery.stopServer();
```

### Client Mode - Discover Services
```typescript
// Find a server on the network
const result = await NetworkDiscovery.findServer({
  serviceName: 'SSSPOSServer',
  serviceType: '_ssspos._tcp',
  timeout: 15000                 // Optional, defaults to 10000ms
});

if (result) {
  console.log('Server found!');
  console.log('IP:', result.ip);
  console.log('Discovery Port:', result.port);
  console.log('HTTP Port:', result.metadata.httpPort);
  console.log('Version:', result.metadata.version);
  
  // Connect to your HTTP server
  const httpUrl = `http://${result.ip}:${result.metadata.httpPort}`;
  // Make your API calls here
} else {
  console.log('Server not found within timeout');
}
```

---

## API Reference

### Methods

#### `startServer(options: StartServerOptions)`

Publishes a service on the local network.

**Parameters:**
```typescript
{
  serviceName: string;    // Name of your service
  serviceType: string;    // Service type (e.g., "_ssspos._tcp")
  port: number;           // Discovery service port
  ip: string;             // Your server IP address
  metadata?: {            // Optional custom key-value pairs
    [key: string]: string;
  };
}
```

#### `stopServer()`

Stops publishing the service.

#### `findServer(options: FindServerOptions)`

Searches for a service on the local network.

**Parameters:**
```typescript
{
  serviceName: string;
  serviceType: string;
  timeout?: number;       // Default: 10000ms
}
```

**Returns:**
```typescript
{
  ip: string;
  port: number;
  metadata: { [key: string]: string };
}
```

---

## Architecture Best Practices

### Separate Ports Pattern
```
Port 8080 → HTTP Server (GET, POST, API endpoints)
Port 8081 → Network Discovery (mDNS/Bonjour)
```

**Why:**
1. Avoids port binding conflicts
2. Clear separation of concerns
3. Easier debugging
4. HTTP server can restart without affecting discovery

---

## Permissions

### Android
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

### iOS
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app needs access to the local network to discover and connect to other devices.</string>

<key>NSBonjourServices</key>
<array>
    <string>_ssspos._tcp</string>
</array>
```

---

## Cross-Platform Compatibility

| Server → Client | Status |
|----------------|--------|
| Android → Android | ✅ Working |
| Android → iOS | ✅ Working |
| iOS → Android | ✅ Working |
| iOS → iOS | ✅ Working |

---

## Troubleshooting

### Services not being discovered

1. Check both devices are on same WiFi network
2. Verify service types match exactly
3. Check firewall/router settings (some block mDNS)
4. Android: Ensure multicast is enabled
5. iOS: Device not in Low Power Mode

### iOS Server not visible to Android

**Fixed in v1.0.0+**

If still experiencing issues:
1. Update to latest version
2. Use separate ports (8080 for HTTP, 8081 for discovery)
3. Check logs for "iOS Servidor LISTO" (iOS) and "NSD_DEBUG" (Android)

### Debugging

**Android:**
```bash
adb logcat | grep NSD_DEBUG
```

**iOS:**
Look for logs with `NSD_LOG:` in Xcode Console

---

## Changelog

### v1.0.0 (Current)
- ✅ Fixed iOS server → Android client discovery
- ✅ Added anti-ghosting IP resolution
- ✅ Improved cross-platform compatibility
- ✅ Enhanced logging for debugging
- ✅ Support for separate discovery/HTTP ports

---

## License

MIT

## Credits

Developed by Alessandry Cruz for Cappitolian projects.