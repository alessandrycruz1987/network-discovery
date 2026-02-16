import Foundation
import Network

@objc public class NetworkDiscovery: NSObject {
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
        
        // --- CONFIGURACIÓN MEJORADA PARA COMPATIBILIDAD CROSS-PLATFORM ---
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        params.allowLocalEndpointReuse = true // Permite reutilización del puerto
        params.acceptLocalOnly = false // Acepta conexiones de toda la red local
        
        // Configuración adicional para que Android pueda resolver
        if let tcpOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            tcpOptions.version = .any // IPv4 e IPv6
        }
        
        let service = NWListener.Service(name: displayName, type: cleanType, domain: nil, txtRecord: txtData)
        
        listener = try NWListener(using: params, on: nwPort)
        listener?.service = service
        
        // --- HANDLER CRÍTICO: Aceptar conexiones entrantes ---
        listener?.newConnectionHandler = { [weak self] connection in
            print("NSD_LOG: iOS recibió conexión de: \(connection.endpoint)")
            
            // Iniciar la conexión para que Android pueda resolver el servicio
            connection.start(queue: .main)
            self?.activeConnections.append(connection)
            
            // Configurar handlers básicos
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    print("NSD_LOG: Conexión establecida con Android")
                }
            }
            
            // Limpieza automática cuando la conexión termine
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
                    print("NSD_LOG: ✅ iOS Servidor LISTO en puerto \(port): \(displayName)")
                }
            case .failed(let error):
                print("NSD_LOG: ❌ iOS Servidor falló: \(error)")
            case .waiting(let error):
                print("NSD_LOG: ⏳ iOS Servidor esperando: \(error)")
            default:
                break
            }
        }
        
        listener?.start(queue: .main)
        
        // Pequeño delay para asegurar que el servicio esté completamente publicado
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("NSD_LOG: Servicio iOS completamente inicializado")
        }
    }

    @objc public func findService(name: String, type: String, timeout: TimeInterval, completion: @escaping ([String: Any]?) -> Void) {
        stopDiscovery()
        let cleanType = type.contains("_") ? type : "_\(type)._tcp"
        
        // Configuración mejorada para el browser
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
                        
                        print("NSD_LOG: iOS Cliente encontró servicio: \(foundName)")
                        
                        var meta: [String: String] = [:]
                        if case let .bonjour(txt) = result.metadata {
                            for (k, v) in txt.dictionary {
                                if let dataValue = v as? Data {
                                    meta[k] = String(data: dataValue, encoding: .utf8) ?? ""
                                }
                            }
                        }
                        
                        // --- LÓGICA DE EXTRACCIÓN ROBUSTA ---
                        var ip = meta["ip"] ?? ""
                        
                        if (ip.isEmpty || ip == "0.0.0.0") && foundName.contains("-") {
                            ip = foundName.components(separatedBy: "-").last ?? ""
                        }
                        
                        if ip.isEmpty || ip == "0.0.0.0" {
                            if case let .hostPort(host, _) = result.endpoint {
                                ip = "\(host)".components(separatedBy: "%").first ?? "\(host)"
                            }
                        }

                        print("NSD_LOG: IP extraída: \(ip)")
                        
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
                print("NSD_LOG: iOS Browser listo para buscar")
            case .failed(let error):
                print("NSD_LOG: iOS Browser falló: \(error)")
            default:
                break
            }
        }
        
        browser.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            if !finished {
                finished = true
                print("NSD_LOG: iOS Búsqueda timeout")
                self?.stopDiscovery()
                completion(nil)
            }
        }
    }

    @objc public func stopServer() {
        // Limpiar todas las conexiones activas
        activeConnections.forEach { $0.cancel() }
        activeConnections.removeAll()
        
        listener?.cancel()
        listener = nil
        print("NSD_LOG: iOS Servidor detenido")
    }
    
    @objc public func stopDiscovery() {
        browser?.cancel()
        browser = nil
    }
}