package com.cappitolian.plugins.networkdiscovery;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "NetworkDiscovery")
public class NetworkDiscoveryPlugin extends Plugin {
    private NetworkDiscovery implementation;

    @Override
    public void load() {
        implementation = new NetworkDiscovery(this, getContext());
    }

    @PluginMethod
    public void startAdvertising(PluginCall call) {
        String serviceName = call.getString("serviceName");
        String serviceType = call.getString("serviceType");
        Integer port = call.getInt("port");
        JSObject txtRecord = call.getObject("txtRecord");

        if (serviceName == null || serviceType == null || port == null) {
            call.reject("Missing required parameters");
            return;
        }

        implementation.startAdvertising(
            serviceName,
            serviceType,
            port,
            txtRecord,
            new NetworkDiscovery.AdvertisingCallback() {
                @Override
                public void onSuccess() {
                    JSObject ret = new JSObject();
                    ret.put("success", true);
                    call.resolve(ret);
                }

                @Override
                public void onError(String error) {
                    call.reject(error);
                }
            }
        );
    }

    @PluginMethod
    public void stopAdvertising(PluginCall call) {
        implementation.stopAdvertising(new NetworkDiscovery.StopCallback() {
            @Override
            public void onSuccess() {
                JSObject ret = new JSObject();
                ret.put("success", true);
                call.resolve(ret);
            }

            @Override
            public void onError(String error) {
                call.reject(error);
            }
        });
    }

    @PluginMethod
    public void startDiscovery(PluginCall call) {
        String serviceType = call.getString("serviceType");

        if (serviceType == null) {
            call.reject("Missing serviceType parameter");
            return;
        }

        implementation.startDiscovery(serviceType, new NetworkDiscovery.DiscoveryCallback() {
            @Override
            public void onDiscoveryStarted() {
                call.resolve();
            }

            @Override
            public void onServiceFound(JSObject service) {
                notifyListeners("serviceFound", service);
            }

            @Override
            public void onServiceLost(JSObject service) {
                notifyListeners("serviceLost", service);
            }

            @Override
            public void onError(String error) {
                call.reject(error);
            }
        });
    }

    @PluginMethod
    public void stopDiscovery(PluginCall call) {
        implementation.stopDiscovery(new NetworkDiscovery.StopCallback() {
            @Override
            public void onSuccess() {
                JSObject ret = new JSObject();
                ret.put("success", true);
                call.resolve(ret);
            }

            @Override
            public void onError(String error) {
                call.reject(error);
            }
        });
    }
}