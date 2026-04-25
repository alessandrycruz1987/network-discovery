import Foundation
import Network

@objc public class NetworkDiscovery: NSObject {
    // Internal struct to store discovered service info (matching Android's DiscoveredService)
    private struct DiscoveredService {
        let ip: String
        let port: Int
        let metadata: [String: Any]
        let timestamp: Int64
        
        init(ip: String, port: Int, metadata: [String: Any], timestamp: Int64) {
            self.ip = ip
            self.port = port
            self.metadata = metadata
            self.timestamp = timestamp
        }
    }
    
    // Private properties
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnections: [NWConnection] = []
    private var discoveredServices: [DiscoveredService] = []
    private var isDiscovering = false
    private var discoveryWorkItem: DispatchWorkItem?
        
    @objc public func startPublishing(name: String, type: String, port: Int, metadata: [String: String]) throws {
        stopServer()
        
        let nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))
        let cleanType = type.contains("_") ? type : "_\(type)._tcp"
        
        // Create mutable metadata with timestamp (matching Android behavior)
        var mutableMetadata = metadata
        
        // Always inject current timestamp (matching Android behavior)
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        mutableMetadata["timestamp"] = timestamp
        
        let ipForName = mutableMetadata["ip"] ?? ""
        let displayName = ipForName.isEmpty ? name : "\(name)-\(ipForName)"
        
        // Convert metadata to TXT record format
        let mappedMetadata = mutableMetadata.mapValues { $0.data(using: .utf8)! }
        let txtData = NetService.data(fromTXTRecord: mappedMetadata)
        
        // Configure parameters for cross-platform compatibility
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        params.allowLocalEndpointReuse = true
        params.acceptLocalOnly = false
        
        if let tcpOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            tcpOptions.version = .any
        }
        
        let service = NWListener.Service(name: displayName, type: cleanType, domain: nil, txtRecord: txtData)
        
        listener = try NWListener(using: params, on: nwPort)
        listener?.service = service
        
        // Handle incoming connections (needed for Android to resolve)
        listener?.newConnectionHandler = { [weak self] connection in
            print("NSD_LOG: iOS received connection from: \(connection.endpoint)")
            
            connection.start(queue: .main)
            self?.activeConnections.append(connection)
            
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    print("NSD_LOG: Connection established with Android")
                }
            }
            
            connection.receiveMessage { _, _, _, error in
                if error != nil {
                    connection.cancel()
                    self?.activeConnections.removeAll { $0 === connection }
                }
            }
        }
        
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let port = self.listener?.port {
                    print("NSD_LOG: iOS Discovery READY on port \(port): \(displayName)")
                }
            case .failed(let error):
                print("NSD_LOG: ❌ iOS Discovery failed: \(error)")
            case .waiting(let error):
                print("NSD_LOG: ⏳ iOS Discovery waiting: \(error)")
            default:
                break
            }
        }
        
        listener?.start(queue: .main)
        
        // Small delay to ensure the service is fully published
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("NSD_LOG: iOS Discovery fully initialized")
        }
    }
        
    @objc public func findService(name: String, type: String, timeout: TimeInterval, completion: @escaping ([String: Any]?) -> Void) {
        stopDiscovery()
        
        let cleanType = type.contains("_") ? type : "_\(type)._tcp"

        discoveredServices.removeAll()
        isDiscovering = true
        
        // Configure browser parameters
        let params = NWParameters()
        params.includePeerToPeer = true
        
        let browser = NWBrowser(for: .bonjour(type: cleanType, domain: nil), using: params)
        self.browser = browser
        
        // Set up timeout (matching Android's Handler.postDelayed)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isDiscovering else { return }

            self.isDiscovering = false
            
            print("NSD_LOG: iOS Browser timeout")

            self.stopDiscovery()
            
            // Select best service based on highest timestamp (matching Android's selectBestService)
            self.selectBestService(completion: completion)
        }

        discoveryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
        
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self, self.isDiscovering else { return }
            
            for result in results {
                if case let .service(foundName, _, _, _) = result.endpoint {
                    // Check if service name starts with our target name (matching Android behavior)
                    guard foundName.hasPrefix(name) else { continue }
                    
                    print("NSD_LOG: iOS Client found service: \(foundName)")
                    
                    var meta: [String: String] = [:]
                    
                    // Extract TXT record metadata
                    if case let .bonjour(txt) = result.metadata {
                        for (key, value) in txt.dictionary {
                            if let dataValue = value as? Data {
                                meta[key] = String(data: dataValue, encoding: .utf8) ?? ""
                            }
                        }
                    }
                    
                    // Extract IP address (matching Android's robust extraction logic)
                    var ip = meta["ip"] ?? ""
                    
                    // Try to extract IP from service name
                    if (ip.isEmpty || ip == "0.0.0.0") && foundName.contains("-") {
                        ip = foundName.components(separatedBy: "-").last ?? ""
                    }
                    
                    // Try to extract from endpoint or get local IP
                    if ip.isEmpty || ip == "0.0.0.0" {
                        ip = self.getIPAddress() ?? ""
                    }
                    
                    if ip.isEmpty || ip == "0.0.0.0" {
                        continue
                    }
                    
                    print("NSD_LOG: Extracted IP: \(ip)")
                    
                    // Try to extract port from metadata
                    var port = 8081 // default port

                    if let portStr = meta["port"], let extractedPort = Int(portStr) {
                        port = extractedPort
                    }
                    
                    // Extract timestamp (matching Android behavior)
                    var timestamp: Int64 = 0

                    if let timestampStr = meta["timestamp"] {
                        timestamp = Int64(timestampStr) ?? 0
                    }
                    
                    // Create DiscoveredService object
                    let service = DiscoveredService(
                        ip: ip,
                        port: port,
                        metadata: meta,
                        timestamp: timestamp
                    )
                    
                    self.discoveredServices.append(service)
                }
            }
        }
        
        browser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("NSD_LOG: iOS Browser ready to search")
            case .failed(let error):
                print("NSD_LOG: iOS Browser failed: \(error)")

                if self.isDiscovering {
                    self.isDiscovering = false

                    self.stopDiscovery()

                    completion(nil)
                }
            default:
                break
            }
        }
        
        browser.start(queue: .main)
    }
        
    @objc public func stopServer() {
        // Cancel all active connections
        activeConnections.forEach { $0.cancel() }
        activeConnections.removeAll()
        
        // Cancel listener
        listener?.cancel()
        listener = nil
        
        print("NSD_LOG: iOS Discovery stopped")
    }
    
    @objc public func stopDiscovery() {
        // Cancel timeout work item
        discoveryWorkItem?.cancel()
        discoveryWorkItem = nil
        
        // Cancel browser
        browser?.cancel()
        browser = nil
        
        isDiscovering = false
        
        print("NSD_LOG: iOS Discovery stopped")
    }
        
    // Select best service based on highest timestamp (matching Android's selectBestService)
    private func selectBestService(completion: @escaping ([String: Any]?) -> Void) {
        if discoveredServices.isEmpty {
            completion(nil)

            return
        }
        
        // Find service with highest timestamp
        guard let bestService = discoveredServices.max(by: { $0.timestamp < $1.timestamp }) else {
            completion(nil)

            return
        }
        
        let result: [String: Any] = [
            "ip": bestService.ip,
            "port": bestService.port,
            "metadata": bestService.metadata
        ]
        
        completion(result)
    }
    
    // Helper to get device IP address
    private func getIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr

            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                guard let interface = ptr?.pointee else { continue }

                let addrFamily = interface.ifa_addr.pointee.sa_family
                
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)

                    if name == "en0" { // WiFi interface
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, socklen_t(0), NI_NUMERICHOST)

                        address = String(cString: hostname)
                    }
                }
            }

            freeifaddrs(ifaddr)
        }
        
        return address
    }
}