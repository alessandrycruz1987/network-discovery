# @cappitolian/network-discovery

A Capacitor plugin for network service discovery using mDNS/Bonjour. Allows automatic server-client connection without manual IP configuration.

---

## Features

- **Advertise services** on the local network (server mode)
- **Discover services** automatically (client mode)
- Pass custom data via TXT records (like IP addresses, ports, etc.)
- Real-time service found/lost events
- Works on **iOS** (Bonjour) and **Android** (NSD)
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

### Server Mode - Advertise Your Service
```typescript
// Start advertising your server
await NetworkDiscovery.startAdvertising({
  serviceName: 'MyAppServer',
  serviceType: '_http._tcp',  // or '_myapp._tcp' for custom service to avoid conflicts with other services
  port: 8080,
  txtRecord: {
    ip: '192.168.1.100',      // Your server IP
    version: '1.0.0'          // Any custom data
  }
});

console.log('Server is now discoverable on the network');

// Stop advertising when needed
await NetworkDiscovery.stopAdvertising();
```

### Client Mode - Discover Services
```typescript
// Listen for discovered services
NetworkDiscovery.addListener('serviceFound', (service) => {
  console.log('Service discovered:', service);
  console.log('Server IP:', service.txtRecord?.ip);
  console.log('Server Port:', service.port);
  console.log('Server Addresses:', service.addresses);
  
  // Connect to your server
  connectToServer(service.addresses[0], service.port);
});

// Listen for lost services
NetworkDiscovery.addListener('serviceLost', (service) => {
  console.log('Service lost:', service.serviceName);
});

// Start discovery
await NetworkDiscovery.startDiscovery({
  serviceType: '_http._tcp',  // Must match the server's serviceType or '_myapp._tcp' for custom service to avoid conflicts with other services
  domain: 'local.'            // Optional, defaults to 'local.'
});

// Stop discovery when needed
await NetworkDiscovery.stopDiscovery();

// Clean up listeners
await NetworkDiscovery.removeAllListeners();
```

### Complete Example - Auto-Connect Flow

**Server Side:**
```typescript
import { NetworkDiscovery } from '@cappitolian/network-discovery';
import { Network } from '@capacitor/network';

async startServer() {
  // Get device IP
  const ip = await this.getLocalIP();
  
  // Advertise server
  await NetworkDiscovery.startAdvertising({
    serviceName: 'MyAppServer',
    serviceType: '_http._tcp', // Must match the server's serviceType or '_myapp._tcp' for custom service to avoid conflicts with other services
    port: 8080,
    txtRecord: { 
      ip: ip,
      serverName: 'Production Server'
    }
  });
  
  console.log('Server advertising on network');
}

async getLocalIP(): Promise<string> {
  const status = await Network.getStatus();
  // Your IP extraction logic here
  return '192.168.1.100';
}
```

**Client Side:**
```typescript
import { NetworkDiscovery } from '@cappitolian/network-discovery';

async findAndConnectToServer() {
  return new Promise((resolve, reject) => {
    
    // Listen for server
    NetworkDiscovery.addListener('serviceFound', async (service) => {
      if (service.serviceName === 'MyAppServer') {
        console.log('Server found!');
        
        const serverIP = service.txtRecord?.ip || service.addresses[0];
        const serverPort = service.port;
        
        // Stop discovery
        await NetworkDiscovery.stopDiscovery();
        await NetworkDiscovery.removeAllListeners();
        
        // Connect to server
        resolve({ ip: serverIP, port: serverPort });
      }
    });
    
    // Start discovery
    NetworkDiscovery.startDiscovery({
      serviceType: '_http._tcp' // Must match the server's serviceType or '_myapp._tcp' for custom service to avoid conflicts with other services
    });
    
    // Timeout after 10 seconds
    setTimeout(() => {
      reject(new Error('Server not found'));
    }, 10000);
  });
}

// Usage
async onLoginClick() {
  try {
    const server = await this.findAndConnectToServer();
    console.log(`Connecting to ${server.ip}:${server.port}`);
    // Your connection logic here
  } catch (error) {
    console.error('Could not find server:', error);
  }
}
```

---

## API Reference

### Methods

#### `startAdvertising(options: AdvertisingOptions)`

Publishes a service on the local network.

**Parameters:**
- `serviceName` (string): Name of your service (e.g., "MyAppServer")
- `serviceType` (string): Service type (e.g., "_http._tcp", "_myapp._tcp")
- `port` (number): Port number your server is listening on
- `txtRecord` (object, optional): Key-value pairs to broadcast (e.g., IP, version)

**Returns:** `Promise<{ success: boolean }>`

---

#### `stopAdvertising()`

Stops advertising the service.

**Returns:** `Promise<{ success: boolean }>`

---

#### `startDiscovery(options: DiscoveryOptions)`

Starts searching for services on the local network.

**Parameters:**
- `serviceType` (string): Type of service to search for (must match server's type)
- `domain` (string, optional): Domain to search in (default: "local.")

**Returns:** `Promise<void>`

---

#### `stopDiscovery()`

Stops the service discovery.

**Returns:** `Promise<{ success: boolean }>`

---

### Events

#### `serviceFound`

Fired when a service is discovered.

**Payload:**
```typescript
{
  serviceName: string;
  serviceType: string;
  domain: string;
  hostName: string;
  port: number;
  addresses: string[];        // Array of IP addresses
  txtRecord?: {               // Custom data from server
    [key: string]: string;
  };
}
```

---

#### `serviceLost`

Fired when a previously discovered service is no longer available.

**Payload:**
```typescript
{
  serviceName: string;
  serviceType: string;
}
```

---

## Service Type Format

Service types must follow the format: `_name._protocol`

**Common examples:**
- `_http._tcp` - HTTP service
- `_https._tcp` - HTTPS service
- `_myapp._tcp` - Custom app service
- `_ssh._tcp` - SSH service

**Recommended for apps:** Use a custom service type like `_myapp._tcp` to avoid conflicts with other services.

---

## Permissions

### Android

Add to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

### iOS

No additional permissions required. Bonjour is enabled by default.

Optionally, add to `Info.plist` to declare your service:
```xml
<key>NSBonjourServices</key>
<array>
    <string>_myapp._tcp</string>
</array>
```

---

## Platforms

- **iOS** (Bonjour/NetService)
- **Android** (Network Service Discovery)
- **Web** (Not implemented - throws unimplemented error)

---

## Requirements

- [Capacitor 7+](https://capacitorjs.com/)
- [Ionic 8+](https://ionicframework.com/) (optional, but tested)
- iOS 12.0+
- Android API 16+ (Android 4.1+)

---

## Troubleshooting

### Services not being discovered

1. **Check both devices are on the same WiFi network**
2. **Verify service types match** exactly between server and client
3. **Check firewall settings** - some networks block mDNS
4. **Android:** Ensure multicast is enabled on your network
5. **iOS:** Make sure device is not in Low Power Mode

### Server not advertising

1. **Verify port is not in use** by another service
2. **Check network permissions** are granted
3. **Restart the app** after installing the plugin

### General debugging

Enable verbose logging:
```typescript
// Check plugin is loaded
console.log('Plugin available:', NetworkDiscovery);

// Log all events
NetworkDiscovery.addListener('serviceFound', (s) => console.log('Found:', s));
NetworkDiscovery.addListener('serviceLost', (s) => console.log('Lost:', s));
```

---

## Use Cases

- **Auto-connect apps** - Client automatically finds and connects to server
- **Local multiplayer games** - Discover game hosts on LAN
- **IoT device discovery** - Find smart devices without configuration
- **File sharing apps** - Discover peers for file transfer
- **Remote control apps** - Find controllable devices automatically

---

## License

MIT

---

## Support

If you encounter any issues or have feature requests, please open an issue on the [GitHub repository](https://github.com/alessandrycruz1987/network-discovery).

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## Credits

Created for use with Capacitor 7 and Ionic 8 applications requiring automatic network service discovery.