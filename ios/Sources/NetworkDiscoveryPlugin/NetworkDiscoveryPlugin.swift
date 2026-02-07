import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(NetworkDiscoveryPlugin)
public class NetworkDiscoveryPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "NetworkDiscoveryPlugin"
    public let jsName = "NetworkDiscovery"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "echo", returnType: CAPPluginReturnPromise)
    ]
    private let implementation = NetworkDiscovery()

    @objc func echo(_ call: CAPPluginCall) {
        let value = call.getString("value") ?? ""
        call.resolve([
            "value": implementation.echo(value)
        ])
    }
}
