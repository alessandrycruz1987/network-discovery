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
import java.util.HashMap;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;

public class NetworkDiscovery {
    // Private properties
    private NsdManager nsdManager;
    private WifiManager.MulticastLock multicastLock;
    private NsdManager.RegistrationListener activeRegistrationListener;
    private NsdManager.DiscoveryListener activeDiscoveryListener;

    // Private static properties
    // Use a short delay to assume discovery is "done" after the last response
    private static final int QUIESCENCE_DELAY_MS = 3000;

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

        // Create a copy to handle ImmutableMap cases from the JS bridge
        Map<String, String> finalMetadata = (metadata != null) ? new HashMap<>(metadata) : new HashMap<>();

        // Inject current timestamp to identify the freshest instance
        long timestamp = System.currentTimeMillis();

        finalMetadata.put("ts", String.valueOf(timestamp));

        String ipForName = finalMetadata.containsKey("ip") ? finalMetadata.get("ip") : "";
        String displayName = ipForName.isEmpty() ? name : name + "-" + ipForName;
        NsdServiceInfo serviceInfo = new NsdServiceInfo();

        serviceInfo.setServiceName(displayName);
        serviceInfo.setServiceType(type);
        serviceInfo.setPort(port);

        for (Map.Entry<String, String> entry : finalMetadata.entrySet()) {
            serviceInfo.setAttribute(entry.getKey().toLowerCase(), entry.getValue());
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
        final Handler mainHandler = new Handler(Looper.getMainLooper());

        // Tracking for the freshest service found
        final AtomicLong bestTimestamp = new AtomicLong(-1);
        final AtomicReference<JSObject> bestResult = new AtomicReference<>(null);

        // This Runnable will return the result when the network goes quiet
        final Runnable deliverBestResult = new Runnable() {
            @Override
            public void run() {
                if (!finished[0]) {
                    finished[0] = true;

                    stopDiscovery();

                    JSObject winner = bestResult.get();

                    if (winner != null) {
                        System.out.println("NSD_DEBUG: Network quiet. Delivering best candidate.");

                        callback.success(winner);
                    } else {
                        callback.error("TIMEOUT_ERROR");
                    }
                }
            }
        };

        activeDiscoveryListener = new NsdManager.DiscoveryListener() {
            @Override
            public void onDiscoveryStarted(String s) {
            }

            @Override
            public void onStartDiscoveryFailed(String s, int i) {
                if (!finished[0]) {
                    finished[0] = true;

                    mainHandler.removeCallbacks(deliverBestResult);

                    callback.error("START_FAIL");
                }
            }

            @Override
            public void onServiceFound(NsdServiceInfo service) {
                if (service.getServiceName().startsWith(name)) {
                    nsdManager.resolveService(service, new NsdManager.ResolveListener() {
                        @Override
                        public void onResolveFailed(NsdServiceInfo nsi, int i) {
                        }

                        @Override
                        public void onServiceResolved(NsdServiceInfo resolved) {
                            if (finished[0])
                                return;

                            // Extract IP and Metadata
                            String sName = resolved.getServiceName();
                            String ipFromName = sName.contains("-") ? sName.substring(sName.lastIndexOf("-") + 1) : "";
                            String resolvedIp = resolved.getHost().getHostAddress();
                            if (resolvedIp.startsWith("/"))
                                resolvedIp = resolvedIp.substring(1);
                            String finalIp = (!ipFromName.isEmpty()) ? ipFromName : resolvedIp;

                            if (finalIp.equals("0.0.0.0") || finalIp.isEmpty())
                                return;

                            // Parse timestamp for comparison
                            long currentTs = -1;
                            Map<String, byte[]> attributes = resolved.getAttributes();

                            if (attributes.containsKey("ts")) {
                                try {
                                    currentTs = Long
                                            .parseLong(new String(attributes.get("ts"), StandardCharsets.UTF_8));
                                } catch (Exception e) {
                                    currentTs = 0;
                                }
                            }

                            // Build JSON result
                            JSObject res = new JSObject();
                            JSObject meta = new JSObject();

                            for (Map.Entry<String, byte[]> entry : attributes.entrySet()) {
                                meta.put(entry.getKey(), new String(entry.getValue(), StandardCharsets.UTF_8));
                            }

                            res.put("ip", finalIp);
                            res.put("port", resolved.getPort());
                            res.put("metadata", meta);

                            // Thread-safe candidate update
                            synchronized (bestTimestamp) {
                                if (currentTs > bestTimestamp.get()) {
                                    bestTimestamp.set(currentTs);
                                    bestResult.set(res);

                                    // Reset the "Silence Timer" every time a valid service is resolved.
                                    // This prevents burning the full timeout if we've already found everything.
                                    mainHandler.removeCallbacks(deliverBestResult);
                                    mainHandler.postDelayed(deliverBestResult, QUIESCENCE_DELAY_MS);
                                }
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

        // Safety hard-timeout: If the network is noisy, we don't wait forever
        mainHandler.postDelayed(deliverBestResult, timeout);
    }

    public void stopServer(Callback c) {
        if (activeRegistrationListener != null) {
            try {
                nsdManager.unregisterService(activeRegistrationListener);
            } catch (Exception e) {
            }

            activeRegistrationListener = null;
        }

        if (multicastLock != null && multicastLock.isHeld())
            multicastLock.release();

        if (c != null)
            c.success(new JSObject());
    }

    public void stopDiscovery() {
        if (activeDiscoveryListener != null) {
            try {
                nsdManager.stopServiceDiscovery(activeDiscoveryListener);
            } catch (Exception e) {
                System.out.println("NSD_DEBUG: Error stopping discovery: " + e.getMessage());
            }
            activeDiscoveryListener = null;
        }

        if (multicastLock != null && multicastLock.isHeld())
            multicastLock.release();
    }
}