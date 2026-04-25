import Foundation
import Network

@objc public class NetworkDiscovery: NSObject {
    // Private properties
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnections: [NWConnection] = []

    @objc public func startPublishing(name: String, type: String, port: Int, metadata: [String: String]) throws {
        stopServer()

        let nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))
        let cleanType = type.contains("_") ? type : "_\(type)._tcp"
        let ipForName = metadata["ip"] ?? ""
        let displayName = ipForName.isEmpty ? name : "\(name)-\(ipForName)"
        let mappedMetadata = metadata.mapValues { $0.data(using: .utf8)! }
        let txtData = NetService.data(fromTXTRecord: mappedMetadata)
        
        // --- IMPROVED CONFIGURATION FOR CROSS-PLATFORM COMPATIBILITY ---
        let params = NWParameters.tcp

        params.includePeerToPeer = true
        params.allowLocalEndpointReuse = true // Allows port reuse
        params.acceptLocalOnly = false // Accepts connections from the entire local network
        
        // Additional configuration to ensure Android can resolve the service
        if let tcpOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            tcpOptions.version = .any // IPv4 or IPv6
        }
        
        let service = NWListener.Service(name: displayName, type: cleanType, domain: nil, txtRecord: txtData)
        
        listener = try NWListener(using: params, on: nwPort)

        listener?.service = service
        
        // --- CRITICAL HANDLER: Accept incoming connections ---
        listener?.newConnectionHandler = { [weak self] connection in
            print("NSD_LOG: iOS received connection from: \(connection.endpoint)")
            
            // Start the connection so that Android can resolve the service
            connection.start(queue: .main)
            self?.activeConnections.append(connection)
            
            // Configure basic handlers
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    print("NSD_LOG: Connection established with Android")
                }
            }
            
            // Automatic cleanup when the connection ends
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
        
        // Improved configuration for the browser
        let params = NWParameters()

        params.includePeerToPeer = true
        
        let browser = NWBrowser(for: .bonjour(type: cleanType, domain: nil), using: params)

        self.browser = browser

        var finished = false

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                if case let .service(foundName, _, _, _) = result.endpoint, foundName.contains(name) {
                    if !finished {
                        finished = true
                        
                        print("NSD_LOG: iOS Client found service: \(foundName)")
                        
                        var meta: [String: String] = [:]

                        if case let .bonjour(txt) = result.metadata {
                            for (k, v) in txt.dictionary {
                                if let dataValue = v as? Data {
                                    meta[k] = String(data: dataValue, encoding: .utf8) ?? ""
                                }
                            }
                        }
                        
                        // --- ROBUST EXTRACTION LOGIC ---
                        var ip = meta["ip"] ?? ""
                        
                        if (ip.isEmpty || ip == "0.0.0.0") && foundName.contains("-") {
                            ip = foundName.components(separatedBy: "-").last ?? ""
                        }
                        
                        if ip.isEmpty || ip == "0.0.0.0" {
                            if case let .hostPort(host, _) = result.endpoint {
                                ip = "\(host)".components(separatedBy: "%").first ?? "\(host)"
                            }
                        }

                        print("NSD_LOG: Extracted IP: \(ip)")
                        
                        self?.stopDiscovery()

                        completion(["ip": ip, "port": 8081, "metadata": meta])
                    }
                    
                    return
                }
            }
        }
        
        browser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("NSD_LOG: iOS Browser ready to search")
            case .failed(let error):
                print("NSD_LOG: iOS Browser failed: \(error)")
            default:
                break
            }
        }
        
        browser.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            if !finished {
                finished = true

                print("NSD_LOG: iOS Browser timeout")

                self?.stopDiscovery()

                completion(nil)
            }
        }
    }

    @objc public func stopServer() {
        // Clear all active connections
        activeConnections.forEach { $0.cancel() }
        activeConnections.removeAll()
        
        listener?.cancel()
        listener = nil

        print("NSD_LOG: iOS Discovery stopped")
    }
    
    @objc public func stopDiscovery() {
        browser?.cancel()
        browser = nil

        print("NSD_LOG: iOS Discovery stopped")
    }
}