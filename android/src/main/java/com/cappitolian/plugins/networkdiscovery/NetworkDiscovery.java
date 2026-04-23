package com.cappitolian.plugins.networkdiscovery;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.Looper;
import com.getcapacitor.JSObject;
import java.nio.charset.StandardCharsets;
import java.util.Map;

public class NetworkDiscovery {
    // Private properties
    private NsdManager nsdManager;
    private WifiManager.MulticastLock multicastLock;
    private NsdManager.RegistrationListener activeRegistrationListener;
    private NsdManager.DiscoveryListener activeDiscoveryListener;

    public interface Callback {
        void success(JSObject data);

        void error(String msg);
    }

    public NetworkDiscovery(Context context) {
        nsdManager = (NsdManager) context.getSystemService(Context.NSD_SERVICE);

        WifiManager wm = (WifiManager) context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);

        multicastLock = wm.createMulticastLock("SSSPOS_Lock");
        multicastLock.setReferenceCounted(true);
    }

    public void startServer(String name, String type, int port, Map<String, String> metadata, final Callback callback) {
        stopServer(null);

        if (!multicastLock.isHeld())
            multicastLock.acquire();

        // TRICK: Include the IP in the name in case metadata fails on iOS
        String ipForName = (metadata != null && metadata.containsKey("ip")) ? metadata.get("ip") : "";
        String displayName = ipForName.isEmpty() ? name : name + "-" + ipForName;
        NsdServiceInfo serviceInfo = new NsdServiceInfo();

        serviceInfo.setServiceName(displayName);
        serviceInfo.setServiceType(type);
        serviceInfo.setPort(port);

        // IMPORTANT: Set attributes before registering
        if (metadata != null) {
            for (Map.Entry<String, String> entry : metadata.entrySet()) {
                serviceInfo.setAttribute(entry.getKey().toLowerCase(), entry.getValue());
            }
        }

        activeRegistrationListener = new NsdManager.RegistrationListener() {
            @Override
            public void onServiceRegistered(NsdServiceInfo info) {
                callback.success(new JSObject());
            }

            @Override
            public void onRegistrationFailed(NsdServiceInfo info, int err) {
                callback.error("REG_ERR_" + err);
            }

            @Override
            public void onServiceUnregistered(NsdServiceInfo info) {
            }

            @Override
            public void onUnregistrationFailed(NsdServiceInfo info, int err) {
            }
        };

        nsdManager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, activeRegistrationListener);
    }

    public void findServer(String name, String type, int timeout, final Callback callback) {
        stopDiscovery();
        if (!multicastLock.isHeld())
            multicastLock.acquire();

        final String cleanType = type.startsWith("_") ? type : "_" + type;
        final boolean[] finished = { false };

        activeDiscoveryListener = new NsdManager.DiscoveryListener() {
            @Override
            public void onDiscoveryStarted(String s) {
            }

            @Override
            public void onStartDiscoveryFailed(String s, int i) {
                if (!finished[0]) {
                    finished[0] = true;

                    callback.error("START_FAIL");
                }
            }

            @Override
            public void onServiceFound(NsdServiceInfo service) {
                // 1. Log to see what Android is actually seeing before filtering
                System.out.println("NSD_DEBUG: Service found on network: " + service.getServiceName());

                // 2. Strict filter: The name must start with the exact prefix
                if (service.getServiceName().startsWith(name)) {
                    nsdManager.resolveService(service, new NsdManager.ResolveListener() {
                        @Override
                        public void onResolveFailed(NsdServiceInfo nsi, int i) {
                            System.out.println("NSD_DEBUG: Failed to resolve service: " + i);
                        }

                        @Override
                        public void onServiceResolved(NsdServiceInfo resolved) {
                            if (!finished[0]) {
                                String sName = resolved.getServiceName();

                                // --- ANTI-GHOSTING LOGIC ---
                                // Try to extract the IP from the name first (it's the source of truth)
                                String ipFromName = "";

                                if (sName.contains("-")) {
                                    ipFromName = sName.substring(sName.lastIndexOf("-") + 1);
                                }

                                // If the name doesn't have an IP, use the one resolved by the system
                                String resolvedIp = resolved.getHost().getHostAddress();

                                if (resolvedIp.startsWith("/"))
                                    resolvedIp = resolvedIp.substring(1);

                                // Final IP decision
                                String finalIp = (!ipFromName.isEmpty()) ? ipFromName : resolvedIp;

                                // IMPORTANT: If the resolved IP is 0.0.0.0 or empty, ignore this event
                                if (finalIp.equals("0.0.0.0") || finalIp.isEmpty())
                                    return;

                                finished[0] = true;

                                stopDiscovery();

                                JSObject res = new JSObject();
                                JSObject meta = new JSObject();

                                for (Map.Entry<String, byte[]> entry : resolved.getAttributes().entrySet()) {
                                    meta.put(entry.getKey(), new String(entry.getValue(), StandardCharsets.UTF_8));
                                }

                                res.put("ip", finalIp);
                                res.put("port", resolved.getPort());
                                res.put("metadata", meta);

                                System.out.println("NSD_DEBUG: Final IP delivered to Client: " + finalIp);

                                callback.success(res);
                            }
                        }
                    });
                }
            }

            @Override
            public void onStopDiscoveryFailed(String s, int i) {
            }

            @Override
            public void onDiscoveryStopped(String s) {
            }

            @Override
            public void onServiceLost(NsdServiceInfo s) {
            }
        };

        nsdManager.discoverServices(cleanType, NsdManager.PROTOCOL_DNS_SD, activeDiscoveryListener);
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (!finished[0]) {
                finished[0] = true;

                stopDiscovery();

                callback.error("TIMEOUT_ERROR");
            }
        }, timeout);
    }

    public void stopServer(Callback c) {
        if (activeRegistrationListener != null) {
            try {
                nsdManager.unregisterService(activeRegistrationListener);
            } catch (Exception e) {
            }
        }

        activeRegistrationListener = null;

        if (multicastLock.isHeld())
            multicastLock.release();
        if (c != null)
            c.success(new JSObject());
    }

    public void stopDiscovery() {
        if (activeDiscoveryListener != null) {
            try {
                nsdManager.stopServiceDiscovery(activeDiscoveryListener);
                System.out.println("NSD_DEBUG: Discovery stopped.");
            } catch (Exception e) {
                System.out.println("NSD_DEBUG: Error stopping discovery: " + e.getMessage());
            }

            activeDiscoveryListener = null;
        }
        // Release the lock only if the process is completely stopped
        if (multicastLock != null && multicastLock.isHeld()) {
            multicastLock.release();
        }
    }
}