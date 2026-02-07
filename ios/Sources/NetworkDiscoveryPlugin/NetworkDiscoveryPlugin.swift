import Foundation
import Capacitor

@objc(NetworkDiscoveryPlugin)
public class NetworkDiscoveryPlugin: CAPPlugin, NetworkDiscoveryDelegate {
    private var implementation: NetworkDiscovery?
    
    override public func load() {
        implementation = NetworkDiscovery()
        implementation?.delegate = self
    }
    
    @objc func startAdvertising(_ call: CAPPluginCall) {
        guard let serviceName = call.getString("serviceName"),
              let serviceType = call.getString("serviceType"),
              let port = call.getInt("port") else {
            call.reject("Missing required parameters")
            return
        }
        
        let txtRecord = call.getObject("txtRecord") as? [String: String]
        
        implementation?.startAdvertising(
            serviceName: serviceName,
            serviceType: serviceType,
            port: port,
            txtRecord: txtRecord
        )
        
        call.resolve(["success": true])
    }
    
    @objc func stopAdvertising(_ call: CAPPluginCall) {
        implementation?.stopAdvertising()
        call.resolve(["success": true])
    }
    
    @objc func startDiscovery(_ call: CAPPluginCall) {
        guard let serviceType = call.getString("serviceType") else {
            call.reject("Missing serviceType parameter")
            return
        }
        
        let domain = call.getString("domain") ?? "local."
        
        implementation?.startDiscovery(serviceType: serviceType, domain: domain)
        call.resolve()
    }
    
    @objc func stopDiscovery(_ call: CAPPluginCall) {
        implementation?.stopDiscovery()
        call.resolve(["success": true])
    }
    
    // MARK: - NetworkDiscoveryDelegate
    public func advertisingDidStart() {
        print("Advertising started successfully")
    }
    
    public func advertisingDidFail(error: String) {
        print("Advertising failed: \(error)")
    }
    
    public func serviceFound(serviceData: [String : Any]) {
        notifyListeners("serviceFound", data: serviceData)
    }
    
    public func serviceLost(serviceData: [String : Any]) {
        notifyListeners("serviceLost", data: serviceData)
    }
    
    public func discoveryDidFail(error: String) {
        print("Discovery failed: \(error)")
    }
}