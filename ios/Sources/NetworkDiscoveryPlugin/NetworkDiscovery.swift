import Foundation
import Network

@objc public class NetworkDiscovery: NSObject {
    // Private properties
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnections: [NWConnection] = []
    
    // Timer to handle the "Silence" period (Quiescence)
    private var silenceTimer: DispatchWorkItem?
    private let quiescenceDelay: TimeInterval = 3

    @objc public func startPublishing(name: String, type: String, port: Int, metadata: [String: String]) throws {
        stopServer()

        let nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))
        let cleanType = type.contains("_") ? type : "_\(type)._tcp"
        
        // --- SYNC WITH ANDROID: Inject Timestamp ---
        var finalMetadata = metadata
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

        finalMetadata["ts"] = String(timestamp)
        
        let ipForName = finalMetadata["ip"] ?? ""
        let displayName = ipForName.isEmpty ? name : "\(name)-\(ipForName)"
        let mappedMetadata = finalMetadata.mapValues { $0.data(using: .utf8)! }
        let txtData = NetService.data(fromTXTRecord: mappedMetadata)
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
        
        listener?.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)

            self?.activeConnections.append(connection)
            
            connection.receiveMessage { _, _, _, error in
                if error != nil {
                    connection.cancel()
                    self?.activeConnections.removeAll { $0 === connection }
                }
            }
        }
        
        listener?.start(queue: .main)
    }

    @objc public func findService(name: String, type: String, timeout: TimeInterval, completion: @escaping ([String: Any]?) -> Void) {
        stopDiscovery()

        let cleanType = type.contains("_") ? type : "_\(type)._tcp"
        
        let params = NWParameters()

        params.includePeerToPeer = true
        
        let browser = NWBrowser(for: .bonjour(type: cleanType, domain: nil), using: params)

        self.browser = browser

        var finished = false
        
        // --- BEST CANDIDATE TRACKING ---
        var bestTimestamp: Int64 = -1
        var bestResult: [String: Any]? = nil

        // Internal function to deliver the winner
        let deliverWinner = { [weak self] in
            if !finished {
                finished = true

                self?.stopDiscovery()

                if let winner = bestResult {
                    print("NSD_LOG: Delivering best candidate (Quiescence reached)")
                    completion(winner)
                } else {
                    completion(nil)
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            
            var foundNewCandidate = false
            
            for result in results {
                if case let .service(foundName, _, _, _) = result.endpoint, foundName.contains(name) {
                    
                    var meta: [String: String] = [:]
                    var currentTs: Int64 = -1

                    if case let .bonjour(txt) = result.metadata {
                        for (k, v) in txt.dictionary {
                            if let dataValue = v as? Data, let valString = String(data: dataValue, encoding: .utf8) {
                                meta[k] = valString

                                if k == "ts" { currentTs = Int64(valString) ?? -1 }
                            }
                        }
                    }
                    
                    // --- REPLACEMENT LOGIC (King of the Hill) ---
                    if currentTs > bestTimestamp {
                        bestTimestamp = currentTs
                        
                        var ip = meta["ip"] ?? ""

                        if (ip.isEmpty || ip == "0.0.0.0") && foundName.contains("-") {
                            ip = foundName.components(separatedBy: "-").last ?? ""
                        }

                        if ip.isEmpty || ip == "0.0.0.0" {
                            if case let .hostPort(host, _) = result.endpoint {
                                ip = "\(host)".components(separatedBy: "%").first ?? "\(host)"
                            }
                        }

                        bestResult = ["ip": ip, "port": 8081, "metadata": meta]
                        foundNewCandidate = true

                        print("NSD_LOG: New best candidate: \(ip) with ts: \(currentTs)")
                    }
                }
            }
            
            // --- QUIESCENCE TIMER LOGIC ---
            if foundNewCandidate {
                self.silenceTimer?.cancel()

                let workItem = DispatchWorkItem { deliverWinner() }
                
                self.silenceTimer = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + self.quiescenceDelay, execute: workItem)
            }
        }
        
        browser.start(queue: .main)

        // --- HARD TIMEOUT SAFETY ---
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            if !finished {
                print("NSD_LOG: Hard timeout reached")
                deliverWinner()
            }
        }
    }

    @objc public func stopDiscovery() {
        silenceTimer?.cancel()
        silenceTimer = nil
        browser?.cancel()
        browser = nil
        print("NSD_LOG: iOS Browser stopped")
    }

    @objc public func stopServer() {
        activeConnections.forEach { $0.cancel() }
        activeConnections.removeAll()
        listener?.cancel()
        listener = nil
    }
}