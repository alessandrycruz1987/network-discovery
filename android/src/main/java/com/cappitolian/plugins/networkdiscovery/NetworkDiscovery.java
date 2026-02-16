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
        if (!multicastLock.isHeld()) multicastLock.acquire();

        // TRUCO: Incluimos la IP en el nombre por si los metadatos fallan en iOS
        String ipForName = (metadata != null && metadata.containsKey("ip")) ? metadata.get("ip") : "";
        String displayName = ipForName.isEmpty() ? name : name + "-" + ipForName;

        NsdServiceInfo serviceInfo = new NsdServiceInfo();
        serviceInfo.setServiceName(displayName);
        serviceInfo.setServiceType(type);
        serviceInfo.setPort(port);

        // IMPORTANTE: Atributos antes de registrar
        if (metadata != null) {
            for (Map.Entry<String, String> entry : metadata.entrySet()) {
                serviceInfo.setAttribute(entry.getKey().toLowerCase(), entry.getValue());
            }
        }

        activeRegistrationListener = new NsdManager.RegistrationListener() {
            @Override public void onServiceRegistered(NsdServiceInfo info) { callback.success(new JSObject()); }
            @Override public void onRegistrationFailed(NsdServiceInfo info, int err) { callback.error("REG_ERR_" + err); }
            @Override public void onServiceUnregistered(NsdServiceInfo info) {}
            @Override public void onUnregistrationFailed(NsdServiceInfo info, int err) {}
        };

        nsdManager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, activeRegistrationListener);
    }

    public void findServer(String name, String type, int timeout, final Callback callback) {
        stopDiscovery();
        if (!multicastLock.isHeld()) multicastLock.acquire();

        final String cleanType = type.startsWith("_") ? type : "_" + type;
        final boolean[] finished = {false};

        activeDiscoveryListener = new NsdManager.DiscoveryListener() {
            @Override public void onDiscoveryStarted(String s) {}
            @Override public void onStartDiscoveryFailed(String s, int i) { if(!finished[0]){ finished[0]=true; callback.error("START_FAIL"); } }
            @Override
            public void onServiceFound(NsdServiceInfo service) {
                // 1. Log para ver qué está viendo Android realmente antes de filtrar
                System.out.println("NSD_DEBUG: Servicio encontrado en red: " + service.getServiceName());

                // 2. Filtro estricto: El nombre debe empezar con el prefijo exacto
                if (service.getServiceName().startsWith(name)) {
                    nsdManager.resolveService(service, new NsdManager.ResolveListener() {
                        @Override public void onResolveFailed(NsdServiceInfo nsi, int i) {
                            System.out.println("NSD_DEBUG: Fallo al resolver servicio: " + i);
                        }

                        @Override
                        public void onServiceResolved(NsdServiceInfo resolved) {
                            if (!finished[0]) {
                                String sName = resolved.getServiceName();
                                
                                // --- LÓGICA ANTI-GHOSTING ---
                                // Intentamos sacar la IP del nombre primero (es la fuente de verdad)
                                String ipFromName = "";
                                if (sName.contains("-")) {
                                    ipFromName = sName.substring(sName.lastIndexOf("-") + 1);
                                }

                                // Si el nombre no tiene IP, usamos la resuelta por el sistema
                                String resolvedIp = resolved.getHost().getHostAddress();
                                if (resolvedIp.startsWith("/")) resolvedIp = resolvedIp.substring(1);

                                // Decisión final de IP
                                String finalIp = (!ipFromName.isEmpty()) ? ipFromName : resolvedIp;

                                // IMPORTANTE: Si la IP resuelta es 0.0.0.0 o vacía, ignoramos este evento
                                if (finalIp.equals("0.0.0.0") || finalIp.isEmpty()) return;

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
                                
                                System.out.println("NSD_DEBUG: IP Final entregada al Cliente: " + finalIp);
                                callback.success(res);
                            }
                        }
                    });
                }
            }
            @Override public void onStopDiscoveryFailed(String s, int i) {}
            @Override public void onDiscoveryStopped(String s) {}
            @Override public void onServiceLost(NsdServiceInfo s) {}
        };

        nsdManager.discoverServices(cleanType, NsdManager.PROTOCOL_DNS_SD, activeDiscoveryListener);
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (!finished[0]) { finished[0]=true; stopDiscovery(); callback.error("TIMEOUT_ERROR"); }
        }, timeout);
    }

    public void stopServer(Callback c) {
        if (activeRegistrationListener != null) { try { nsdManager.unregisterService(activeRegistrationListener); } catch (Exception e) {} }
        activeRegistrationListener = null;
        if (multicastLock.isHeld()) multicastLock.release();
        if (c != null) c.success(new JSObject());
    }

    public void stopDiscovery() {
        if (activeDiscoveryListener != null) {
            try {
                nsdManager.stopServiceDiscovery(activeDiscoveryListener);
                System.out.println("NSD_DEBUG: Discovery detenido.");
            } catch (Exception e) {
                System.out.println("NSD_DEBUG: Error al detener discovery: " + e.getMessage());
            }
            activeDiscoveryListener = null;
        }
        // Liberamos el lock solo si se detiene por completo el proceso
        if (multicastLock != null && multicastLock.isHeld()) {
            multicastLock.release();
        }
    }
}