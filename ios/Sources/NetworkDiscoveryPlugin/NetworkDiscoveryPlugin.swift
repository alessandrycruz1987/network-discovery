import Foundation
import Capacitor

@objc(NetworkDiscoveryPlugin)
public class NetworkDiscoveryPlugin: CAPPlugin, CAPBridgedPlugin, NetworkDiscoveryDelegate {
    
    // MARK: - CAPBridgedPlugin Properties
    public let identifier = "NetworkDiscoveryPlugin"
    public let jsName = "NetworkDiscovery"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "startAdvertising", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopAdvertising", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startDiscovery", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopDiscovery", returnType: CAPPluginReturnPromise)
    ]
    
    // MARK: - Properties
    private var implementation: NetworkDiscovery?
    
    // MARK: - Lifecycle
    public override func load() {
        print("✅ NetworkDiscoveryPlugin: Plugin loaded")
        implementation = NetworkDiscovery()
        implementation?.delegate = self
    }
    
    // MARK: - Plugin Methods
    @objc func startAdvertising(_ call: CAPPluginCall) {
        print("📞 NetworkDiscoveryPlugin: startAdvertising() called")
        
        guard let serviceName = call.getString("serviceName"),
              let serviceType = call.getString("serviceType"),
              let port = call.getInt("port") else {
            call.reject("Missing required parameters")
            return
        }
        
        let txtRecord = call.getObject("txtRecord") as? [String: String]
        
        print("📡 NetworkDiscoveryPlugin: Starting advertising - \(serviceName)")
        
        implementation?.startAdvertising(
            serviceName: serviceName,
            serviceType: serviceType,
            port: port,
            txtRecord: txtRecord
        )
        
        call.resolve(["success": true])
    }
    
    @objc func stopAdvertising(_ call: CAPPluginCall) {
        print("📞 NetworkDiscoveryPlugin: stopAdvertising() called")
        implementation?.stopAdvertising()
        call.resolve(["success": true])
    }
    
    @objc func startDiscovery(_ call: CAPPluginCall) {
        print("📞 NetworkDiscoveryPlugin: startDiscovery() called")
        
        guard let serviceType = call.getString("serviceType") else {
            call.reject("Missing serviceType parameter")
            return
        }
        
        let domain = call.getString("domain") ?? "local."
        
        print("🔍 NetworkDiscoveryPlugin: Starting discovery for \(serviceType)")
        
        implementation?.startDiscovery(serviceType: serviceType, domain: domain)
        call.resolve()
    }
    
    @objc func stopDiscovery(_ call: CAPPluginCall) {
        print("📞 NetworkDiscoveryPlugin: stopDiscovery() called")
        implementation?.stopDiscovery()
        call.resolve(["success": true])
    }
    
    // MARK: - NetworkDiscoveryDelegate
    public func advertisingDidStart() {
        print("✅ NetworkDiscoveryPlugin: Advertising started successfully")
    }
    
    public func advertisingDidFail(error: String) {
        print("❌ NetworkDiscoveryPlugin: Advertising failed - \(error)")
    }
    
    public func serviceFound(serviceData: [String : Any]) {
        print("📨 NetworkDiscoveryPlugin: Service found, notifying listeners")
        print("   Service data: \(serviceData)")
        notifyListeners("serviceFound", data: serviceData)
    }
    
    public func serviceLost(serviceData: [String : Any]) {
        print("📨 NetworkDiscoveryPlugin: Service lost, notifying listeners")
        print("   Service data: \(serviceData)")
        notifyListeners("serviceLost", data: serviceData)
    }
    
    public func discoveryDidFail(error: String) {
        print("❌ NetworkDiscoveryPlugin: Discovery failed - \(error)")
    }
}