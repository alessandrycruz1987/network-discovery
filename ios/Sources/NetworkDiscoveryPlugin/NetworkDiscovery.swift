import Foundation

@objc public class NetworkDiscovery: NSObject {
    private var netService: NetService?
    private var netServiceBrowser: NetServiceBrowser?
    private var discoveredServices: [NetService] = []
    
    weak var delegate: NetworkDiscoveryDelegate?
    
    @objc public func startAdvertising(
        serviceName: String,
        serviceType: String,
        port: Int,
        txtRecord: [String: String]?
    ) {
        netService = NetService(domain: "local.", type: serviceType, name: serviceName, port: Int32(port))
        
        // Configurar TXT record
        if let txtRecord = txtRecord, !txtRecord.isEmpty {
            var txtData: [String: Data] = [:]
            for (key, value) in txtRecord {
                txtData[key] = value.data(using: .utf8)
            }
            let txtRecordData = NetService.data(fromTXTRecord: txtData)
            netService?.setTXTRecord(txtRecordData)
        }
        
        netService?.delegate = self
        netService?.publish()
    }
    
    @objc public func stopAdvertising() {
        netService?.stop()
        netService = nil
    }
    
    @objc public func startDiscovery(serviceType: String, domain: String = "local.") {
        netServiceBrowser = NetServiceBrowser()
        netServiceBrowser?.delegate = self
        netServiceBrowser?.searchForServices(ofType: serviceType, inDomain: domain)
    }
    
    @objc public func stopDiscovery() {
        netServiceBrowser?.stop()
        netServiceBrowser = nil
        discoveredServices.removeAll()
    }
}

// MARK: - NetServiceDelegate
extension NetworkDiscovery: NetServiceDelegate {
    public func netServiceDidPublish(_ sender: NetService) {
        print("Service published: \(sender.name)")
        delegate?.advertisingDidStart()
    }
    
    public func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("Service did not publish: \(errorDict)")
        let errorCode = errorDict[NetService.errorCode]?.intValue ?? -1
        delegate?.advertisingDidFail(error: "Failed to publish service. Error code: \(errorCode)")
    }
}

// MARK: - NetServiceBrowserDelegate
extension NetworkDiscovery: NetServiceBrowserDelegate {
    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        print("Service discovery stopped")
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        print("Service discovery failed: \(errorDict)")
        let errorCode = errorDict[NetService.errorCode]?.intValue ?? -1
        delegate?.discoveryDidFail(error: "Discovery failed. Error code: \(errorCode)")
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("Service found: \(service.name)")
        discoveredServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        print("Service lost: \(service.name)")
        
        let serviceData: [String: Any] = [
            "serviceName": service.name,
            "serviceType": service.type
        ]
        
        delegate?.serviceLost(serviceData: serviceData)
        
        if let index = discoveredServices.firstIndex(of: service) {
            discoveredServices.remove(at: index)
        }
    }
    
    public func netServiceDidResolveAddress(_ sender: NetService) {
        print("Service resolved: \(sender.name)")
        
        var addresses: [String] = []
        
        if let addressesData = sender.addresses {
            for addressData in addressesData {
                let address = addressData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> String? in
                    guard let baseAddress = pointer.baseAddress else { return nil }
                    let data = baseAddress.assumingMemoryBound(to: sockaddr.self)
                    
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(data, socklen_t(addressData.count), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        return String(cString: hostname)
                    }
                    return nil
                }
                
                if let addr = address {
                    addresses.append(addr)
                }
            }
        }
        
        var serviceData: [String: Any] = [
            "serviceName": sender.name,
            "serviceType": sender.type,
            "domain": sender.domain,
            "hostName": sender.hostName ?? "",
            "port": sender.port,
            "addresses": addresses
        ]
        
        // Agregar TXT record
        if let txtData = sender.txtRecordData() {
            let txtRecord = NetService.dictionary(fromTXTRecord: txtData)
            var txtRecordDict: [String: String] = [:]
            for (key, value) in txtRecord {
                if let strValue = String(data: value, encoding: .utf8) {
                    txtRecordDict[key] = strValue
                }
            }
            serviceData["txtRecord"] = txtRecordDict
        }
        
        delegate?.serviceFound(serviceData: serviceData)
    }
    
    public func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("Service did not resolve: \(errorDict)")
    }
}

// MARK: - Delegate Protocol
@objc public protocol NetworkDiscoveryDelegate: AnyObject {
    func advertisingDidStart()
    func advertisingDidFail(error: String)
    func serviceFound(serviceData: [String: Any])
    func serviceLost(serviceData: [String: Any])
    func discoveryDidFail(error: String)
}