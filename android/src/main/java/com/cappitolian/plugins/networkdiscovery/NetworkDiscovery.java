package com.cappitolian.plugins.networkdiscovery;

import com.getcapacitor.Logger;

public class NetworkDiscovery {

    public String echo(String value) {
        Logger.info("Echo", value);
        return value;
    }
}
