package com.cappitolian.plugins.networkdiscovery;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.util.Log;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;

import org.json.JSONArray;
import org.json.JSONException;

import java.net.InetAddress;
import java.util.Map;
import java.util.Iterator;

public class NetworkDiscovery {
    private static final String TAG = "NetworkDiscovery";
    private NsdManager nsdManager;
    private NsdManager.RegistrationListener registrationListener;
    private NsdManager.DiscoveryListener discoveryListener;
    private NsdServiceInfo serviceInfo;
    private Plugin plugin;

    public NetworkDiscovery(Plugin plugin, Context context) {
        this.plugin = plugin;
        this.nsdManager = (NsdManager) context.getSystemService(Context.NSD_SERVICE);
    }

    public void startAdvertising(
        String serviceName,
        String serviceType,
        int port,
        JSObject txtRecord,
        AdvertisingCallback callback
    ) {
        serviceInfo = new NsdServiceInfo();
        serviceInfo.setServiceName(serviceName);
        serviceInfo.setServiceType(serviceType);
        serviceInfo.setPort(port);

        // Agregar TXT records
        if (txtRecord != null) {
            Iterator<String> keys = txtRecord.keys();
            while (keys.hasNext()) {
            String key = keys.next();
                try {
                    String value = txtRecord.getString(key);
                    serviceInfo.setAttribute(key, value);
                } catch (Exception e) {
                    Log.e(TAG, "Error setting attribute: " + key, e);
                }
            }
        }

        registrationListener = new NsdManager.RegistrationListener() {
            @Override
            public void onRegistrationFailed(NsdServiceInfo serviceInfo, int errorCode) {
                Log.e(TAG, "Service registration failed: " + errorCode);
                callback.onError("Registration failed with error code: " + errorCode);
            }

            @Override
            public void onUnregistrationFailed(NsdServiceInfo serviceInfo, int errorCode) {
                Log.e(TAG, "Service unregistration failed: " + errorCode);
            }

            @Override
            public void onServiceRegistered(NsdServiceInfo serviceInfo) {
                Log.d(TAG, "Service registered: " + serviceInfo.getServiceName());
                callback.onSuccess();
            }

            @Override
            public void onServiceUnregistered(NsdServiceInfo serviceInfo) {
                Log.d(TAG, "Service unregistered");
            }
        };

        nsdManager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener);
    }

    public void stopAdvertising(StopCallback callback) {
        if (registrationListener != null) {
            try {
                nsdManager.unregisterService(registrationListener);
                registrationListener = null;
                callback.onSuccess();
            } catch (Exception e) {
                callback.onError("Error stopping advertising: " + e.getMessage());
            }
        } else {
            callback.onError("No active advertising to stop");
        }
    }

    public void startDiscovery(String serviceType, DiscoveryCallback callback) {
        discoveryListener = new NsdManager.DiscoveryListener() {
            @Override
            public void onStartDiscoveryFailed(String serviceType, int errorCode) {
                Log.e(TAG, "Discovery start failed: " + errorCode);
                nsdManager.stopServiceDiscovery(this);
                callback.onError("Discovery failed with error code: " + errorCode);
            }

            @Override
            public void onStopDiscoveryFailed(String serviceType, int errorCode) {
                Log.e(TAG, "Discovery stop failed: " + errorCode);
            }

            @Override
            public void onDiscoveryStarted(String serviceType) {
                Log.d(TAG, "Service discovery started");
                callback.onDiscoveryStarted();
            }

            @Override
            public void onDiscoveryStopped(String serviceType) {
                Log.d(TAG, "Service discovery stopped");
            }

            @Override
            public void onServiceFound(NsdServiceInfo service) {
                Log.d(TAG, "Service found: " + service.getServiceName());
                
                nsdManager.resolveService(service, new NsdManager.ResolveListener() {
                    @Override
                    public void onResolveFailed(NsdServiceInfo serviceInfo, int errorCode) {
                        Log.e(TAG, "Resolve failed: " + errorCode);
                    }

                    @Override
                    public void onServiceResolved(NsdServiceInfo serviceInfo) {
                        Log.d(TAG, "Service resolved: " + serviceInfo);
                        
                        JSObject serviceData = buildServiceObject(serviceInfo);
                        callback.onServiceFound(serviceData);
                    }
                });
            }

            @Override
            public void onServiceLost(NsdServiceInfo service) {
                Log.d(TAG, "Service lost: " + service.getServiceName());
                
                JSObject serviceData = new JSObject();
                serviceData.put("serviceName", service.getServiceName());
                serviceData.put("serviceType", service.getServiceType());
                
                callback.onServiceLost(serviceData);
            }
        };

        nsdManager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, discoveryListener);
    }

    public void stopDiscovery(StopCallback callback) {
        if (discoveryListener != null) {
            try {
                nsdManager.stopServiceDiscovery(discoveryListener);
                discoveryListener = null;
                callback.onSuccess();
            } catch (Exception e) {
                callback.onError("Error stopping discovery: " + e.getMessage());
            }
        } else {
            callback.onError("No active discovery to stop");
        }
    }

    private JSObject buildServiceObject(NsdServiceInfo serviceInfo) {
        JSObject serviceData = new JSObject();
        serviceData.put("serviceName", serviceInfo.getServiceName());
        serviceData.put("serviceType", serviceInfo.getServiceType());
        serviceData.put("hostName", serviceInfo.getHost() != null ? serviceInfo.getHost().getHostName() : "");
        serviceData.put("port", serviceInfo.getPort());
        
        // Agregar direcciones IP
        InetAddress host = serviceInfo.getHost();
        if (host != null) {
            try {
                JSONArray addresses = new JSONArray();
                addresses.put(host.getHostAddress());
                serviceData.put("addresses", addresses);
            } catch (JSONException e) {
                Log.e(TAG, "Error adding addresses", e);
            }
        }
        
        // Agregar TXT records
        Map<String, byte[]> attributes = serviceInfo.getAttributes();
        if (attributes != null && !attributes.isEmpty()) {
            JSObject txtRecordObj = new JSObject();
            for (Map.Entry<String, byte[]> entry : attributes.entrySet()) {
                txtRecordObj.put(entry.getKey(), new String(entry.getValue()));
            }
            serviceData.put("txtRecord", txtRecordObj);
        }
        
        return serviceData;
    }

    // Callbacks interfaces
    public interface AdvertisingCallback {
        void onSuccess();
        void onError(String error);
    }

    public interface StopCallback {
        void onSuccess();
        void onError(String error);
    }

    public interface DiscoveryCallback {
        void onDiscoveryStarted();
        void onServiceFound(JSObject service);
        void onServiceLost(JSObject service);
        void onError(String error);
    }
}