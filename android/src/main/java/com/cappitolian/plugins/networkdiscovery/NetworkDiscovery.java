package com.cappitolian.plugins.networkdiscovery;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.Looper;
import com.getcapacitor.JSObject;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

public class NetworkDiscovery {
    // Private properties
    private NsdManager nsdManager;
    private WifiManager.MulticastLock multicastLock;
    private NsdManager.RegistrationListener activeRegistrationListener;
    private NsdManager.DiscoveryListener activeDiscoveryListener;

    // Internal class to store discovered service info for later selection
    private static class DiscoveredService {
        String ip;
        int port;
        JSObject metadata;
        long timestamp;

        DiscoveredService(String ip, int port, JSObject metadata, long timestamp) {
            this.ip = ip;
            this.port = port;
            this.metadata = metadata;
            this.timestamp = timestamp;
        }
    }

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

        // Ensure metadata is mutable and inject current timestamp
        Map<String, String> finalMetadata;

        if (metadata == null) {
            finalMetadata = new HashMap<>();
        } else {
            finalMetadata = new HashMap<>(metadata);
        }

        finalMetadata.put("timestamp", String.valueOf(System.currentTimeMillis()));

        String ipForName = (finalMetadata.containsKey("ip")) ? finalMetadata.get("ip") : "";
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
            public void onServiceUnregistered(NsdServiceInfo info) {}
            @Override
            public void onUnregistrationFailed(NsdServiceInfo info, int err) {}
        };

        nsdManager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, activeRegistrationListener);
    }

    public void findServer(String name, String type, int timeout, final Callback callback) {
        stopDiscovery();

        if (!multicastLock.isHeld())
            multicastLock.acquire();

        final String cleanType = type.startsWith("_") ? type : "_" + type;
        final AtomicBoolean finished = new AtomicBoolean(false);
        final List<DiscoveredService> discoveredServices = Collections.synchronizedList(new ArrayList<>());
        final Handler mainHandler = new Handler(Looper.getMainLooper());

        // General timeout: after timeout, pick the service with the highest timestamp
        mainHandler.postDelayed(() -> {
            if (!finished.getAndSet(true)) {
                stopDiscovery();
                selectBestService(discoveredServices, callback);
            }
        }, timeout);

        activeDiscoveryListener = new NsdManager.DiscoveryListener() {
            @Override
            public void onDiscoveryStarted(String s) {}

            @Override
            public void onStartDiscoveryFailed(String s, int i) {
                if (!finished.getAndSet(true)) {
                    callback.error("START_FAIL");
                }
            }

            @Override
            public void onServiceFound(NsdServiceInfo service) {
                if (service.getServiceName().startsWith(name)) {
                    nsdManager.resolveService(service, new NsdManager.ResolveListener() {
                        @Override
                        public void onResolveFailed(NsdServiceInfo nsi, int i) {}

                        @Override
                        public void onServiceResolved(NsdServiceInfo resolved) {
                            if (finished.get()) return;

                            String sName = resolved.getServiceName();

                            String ipFromName = "";
                            if (sName.contains("-")) {
                                ipFromName = sName.substring(sName.lastIndexOf("-") + 1);
                            }

                            String resolvedIp = resolved.getHost().getHostAddress();

                            if (resolvedIp.startsWith("/"))
                                resolvedIp = resolvedIp.substring(1);

                            String finalIp = (!ipFromName.isEmpty()) ? ipFromName : resolvedIp;

                            if (finalIp.equals("0.0.0.0") || finalIp.isEmpty())
                                return;

                            int port = resolved.getPort();

                            // Extract timestamp from attributes (default 0 if missing)
                            long timestamp = 0L;
                            Map<String, byte[]> attributes = resolved.getAttributes();

                            if (attributes.containsKey("timestamp")) {
                                try {
                                    timestamp = Long.parseLong(new String(attributes.get("timestamp"), StandardCharsets.UTF_8));
                                } catch (NumberFormatException e) {
                                    timestamp = 0L;
                                }
                            }

                            JSObject meta = new JSObject();

                            for (Map.Entry<String, byte[]> entry : attributes.entrySet()) {
                                meta.put(entry.getKey(), new String(entry.getValue(), StandardCharsets.UTF_8));
                            }

                            discoveredServices.add(new DiscoveredService(finalIp, port, meta, timestamp));
                        }
                    });
                }
            }

            @Override
            public void onServiceLost(NsdServiceInfo s) {}
            @Override
            public void onStopDiscoveryFailed(String s, int i) {}
            @Override
            public void onDiscoveryStopped(String s) {}
        };

        nsdManager.discoverServices(cleanType, NsdManager.PROTOCOL_DNS_SD, activeDiscoveryListener);
    }

    public void stopServer(Callback c) {
        if (activeRegistrationListener != null) {
            try {
                nsdManager.unregisterService(activeRegistrationListener);
            } catch (Exception e) {}
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
            } catch (Exception e) {}

            activeDiscoveryListener = null;
        }

        if (multicastLock != null && multicastLock.isHeld()) {
            multicastLock.release();
        }
    }

    private void selectBestService(List<DiscoveredService> services, Callback callback) {
        if (services.isEmpty()) {
            callback.error("TIMEOUT_ERROR");

            return;
        }

        // Pick the service with the highest timestamp (most recent)
        DiscoveredService best = Collections.max(services, new Comparator<DiscoveredService>() {
            @Override
            public int compare(DiscoveredService o1, DiscoveredService o2) {
                return Long.compare(o1.timestamp, o2.timestamp);
            }
        });

        JSObject result = new JSObject();
        result.put("ip", best.ip);
        result.put("port", best.port);
        result.put("metadata", best.metadata);
        callback.success(result);
    }
}