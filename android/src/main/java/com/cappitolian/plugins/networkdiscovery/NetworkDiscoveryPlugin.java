package com.cappitolian.plugins.networkdiscovery;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

@CapacitorPlugin(name = "NetworkDiscovery")
public class NetworkDiscoveryPlugin extends Plugin {
    private NetworkDiscovery implementation;

    @Override
    public void load() {
        implementation = new NetworkDiscovery(getContext());
    }

    @PluginMethod
    public void startServer(PluginCall call) {
        String name = call.getString("serviceName");
        String type = call.getString("serviceType");
        Integer port = call.getInt("port", 8081);
        JSObject metaJS = call.getObject("metadata");

        Map<String, String> metadata = new HashMap<>();
        if (metaJS != null) {
            Iterator<String> keys = metaJS.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                metadata.put(key, metaJS.getString(key));
            }
        }

        implementation.startServer(name, type, port, metadata, new NetworkDiscovery.Callback() {
            @Override public void success(JSObject data) { call.resolve(data); }
            @Override public void error(String msg) { call.reject(msg); }
        });
    }

    @PluginMethod
    public void stopServer(PluginCall call) {
        implementation.stopServer(new NetworkDiscovery.Callback() {
            @Override public void success(JSObject data) { call.resolve(data); }
            @Override public void error(String msg) { call.reject(msg); }
        });
    }

    @PluginMethod
    public void findServer(PluginCall call) {
        String name = call.getString("serviceName");
        String type = call.getString("serviceType");
        Integer timeout = call.getInt("timeout", 10000);

        implementation.findServer(name, type, timeout, new NetworkDiscovery.Callback() {
            @Override public void success(JSObject data) { call.resolve(data); }
            @Override public void error(String msg) { call.reject(msg); }
        });
    }
}