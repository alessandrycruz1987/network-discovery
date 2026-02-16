import Foundation
import Capacitor

@objc(NetworkDiscoveryPlugin)
public class NetworkDiscoveryPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "NetworkDiscoveryPlugin"
    public let jsName = "NetworkDiscovery"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "startServer", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopServer", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "findServer", returnType: CAPPluginReturnPromise)
    ]

    private let implementation = NetworkDiscovery()

    @objc func startServer(_ call: CAPPluginCall) {
        guard let name = call.getString("serviceName"),
              let type = call.getString("serviceType"),
              let port = call.getInt("port") else { return call.reject("Faltan parámetros") }
        
        let metadata = call.getObject("metadata") as? [String: String] ?? [:]
        do {
            try implementation.startPublishing(name: name, type: type, port: port, metadata: metadata)
            call.resolve()
        } catch { call.reject(error.localizedDescription) }
    }

    @objc func stopServer(_ call: CAPPluginCall) {
        implementation.stopServer()
        call.resolve()
    }

    @objc func findServer(_ call: CAPPluginCall) {
        guard let name = call.getString("serviceName"),
              let type = call.getString("serviceType") else { return call.reject("Faltan parámetros") }
        
        let timeout = Double(call.getInt("timeout") ?? 10000) / 1000.0
        implementation.findService(name: name, type: type, timeout: timeout) { result in
            if let data = result { call.resolve(data) } 
            else { call.reject("TIMEOUT_ERROR") }
        }
    }
}