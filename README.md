# @cappitolian/network-discovery

A Capacitor plugin for network service discovery using mDNS/Bonjour. Allows automatic server-client connection without manual IP configuration.

---

## Features

- **Publish services** on the local network (server mode)
- **Discover services** automatically (client mode)
- Pass custom metadata via TXT records (like HTTP port, version, etc.)
- Anti-ghosting IP resolution: IP embedded in service name as fallback
- Timestamp-based selection: always resolves to the **most recently registered** service
- Works on **iOS** (Bonjour / NWListener + NWBrowser) and **Android** (NSD + MulticastLock)
- Cross-platform compatible: iOS ↔ Android in both directions
- Tested with **Capacitor 7** and **Ionic 8**

---

## Installation

```bash
npm install @cappitolian/network-discovery
npx cap sync
```

---

## Native Configuration

### Android — `AndroidManifest.xml`

Add the following permissions (Network Discovery only — does **not** include HTTP server permissions):

```xml
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

### iOS — `Info.plist`

```xml
<!-- Required for local network access prompt -->
<key>NSLocalNetworkUsageDescription</key>
<string>This app needs access to the local network to discover and connect to other devices.</string>

<!-- Required for mDNS/Bonjour discovery -->
<key>NSBonjourServices</key>
<array>
    <string>_ssspos._tcp</string>
</array>
```

> **Note:** `NSAppTransportSecurity` settings (`NSAllowsLocalNetworking`, `NSAllowsArbitraryLoads`) belong to your **HTTP server plugin**, not to this plugin.

---

## Usage

### Import

```typescript
import { NetworkDiscovery } from '@cappitolian/network-discovery';
```

### Server Mode — Publish Your Service

```typescript
await NetworkDiscovery.startServer({
  serviceName: 'SSSPOSServer',
  serviceType: '_ssspos._tcp',
  port: 8081,                    // Discovery port (NWListener / NSD)
  ip: '192.168.1.100',           // Your server IP (embedded in service name)
  metadata: {
    httpPort: '8080',            // Your actual HTTP server port
    version: '1.0.0',
    deviceName: 'Main Server'
  }
});

// Stop publishing when needed
await NetworkDiscovery.stopServer();
```

> **Internals:** The plugin injects a `timestamp` key automatically into the TXT record metadata. The service is registered as `{serviceName}-{ip}` (e.g. `SSSPOSServer-192.168.1.100`) to enable IP fallback resolution on the client side.

### Client Mode — Discover Services

```typescript
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

  const httpUrl = `http://${result.ip}:${result.metadata.httpPort}`;
} else {
  console.log('Server not found within timeout');
}
```

> **Internals:** The client collects **all** matching services found during the timeout window and returns the one with the **highest `timestamp`** (most recently published). This prevents resolving stale/ghost services.

---

## API Reference

### `startServer(options: StartServerOptions): Promise<void>`

Publishes a service on the local network.

```typescript
{
  serviceName: string;    // Name of your service (e.g. "SSSPOSServer")
  serviceType: string;    // mDNS service type (e.g. "_ssspos._tcp")
  port: number;           // Discovery port for NWListener / NSD
  ip: string;             // Server IP — embedded in the service name as anti-ghosting fallback
  metadata?: {            // Optional TXT record key-value pairs
    [key: string]: string;
  };
}
```

> A `timestamp` key is always injected automatically — do not set it manually.

---

### `stopServer(): Promise<void>`

Stops publishing the service and releases the MulticastLock (Android) / cancels NWListener connections (iOS).

---

### `findServer(options: FindServerOptions): Promise<FoundServer | null>`

Searches for a service on the local network during the timeout window.

```typescript
// Options
{
  serviceName: string;    // Must match the prefix used in startServer
  serviceType: string;
  timeout?: number;       // Default: 10000ms
}

// Result
{
  ip: string;
  port: number;
  metadata: { [key: string]: string };  // Includes all TXT record fields + timestamp
}
```

Returns `null` if no service is found before the timeout.

---

## Architecture Best Practices

### Separate Ports Pattern

```
Port 8080 → HTTP Server  (Swifter / NanoHttpd)   — GET, POST, API endpoints
Port 8081 → Discovery    (NWListener / NSD)       — mDNS/Bonjour registration
```

**Why separate ports:**
- Avoids port binding conflicts between the HTTP server and the discovery listener
- Clear separation of concerns between plugins
- HTTP server can restart independently without dropping discovery
- Easier to debug each layer in isolation

---

## IP Resolution Strategy

The plugin uses a layered fallback to resolve the server IP on the client:

| Priority | Source | Notes |
|----------|--------|-------|
| 1st | `ip` key in TXT record metadata | Most reliable if set |
| 2nd | Service name suffix (`{name}-{ip}`) | Anti-ghosting fallback |
| 3rd | `getHostAddress()` / `getIPAddress()` (en0) | OS-resolved, may return 0.0.0.0 on Android |

Services resolving to `0.0.0.0` or empty are silently discarded.

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

1. Both devices must be on the **same WiFi network**
2. Service types must match exactly (e.g. `_ssspos._tcp`)
3. Some routers block mDNS — check firewall / AP isolation settings
4. Android: MulticastLock is acquired automatically; verify permissions in manifest
5. iOS: Device must not be in Low Power Mode

### iOS Server not visible to Android

**Fixed in v1.0.0+**

If still experiencing issues:
1. Update to the latest version
2. Use separate ports (8080 for HTTP, 8081 for discovery)
3. Ensure `ip` is passed to `startServer` — required for the anti-ghosting service name embedding

### Debugging

**Android:**
```bash
adb logcat | grep NSD_DEBUG
```

**iOS:**
Look for `NSD_LOG:` prefixed entries in the Xcode Console.

---

## Changelog

### v1.0.0 (Current)

- ✅ Fixed iOS server → Android client discovery
- ✅ Added anti-ghosting IP resolution (IP embedded in service name)
- ✅ Added timestamp-based service selection (resolves most recent, not first found)
- ✅ Improved cross-platform compatibility (NWListener + NWBrowser on iOS)
- ✅ Enhanced logging (`NSD_LOG:` on iOS, `NSD_DEBUG` on Android)
- ✅ Support for separate discovery / HTTP ports

---

## License

MIT

## Credits

Developed by Alessandry Cruz for Cappitolian projects.