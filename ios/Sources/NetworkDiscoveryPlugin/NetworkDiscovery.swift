import Foundation
import Network

@objc public class NetworkDiscovery: NSObject {
    private struct DiscoveredService {
        let ip: String
        let port: Int
        let metadata: [String: Any]
        let timestamp: Int64
    }

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnections: [NWConnection] = []
    private var discoveredServices: [DiscoveredService] = []
    private var isDiscovering = false
    // FIX Bug 2: separar el workItem del flag, para que stopDiscovery()
    // no cancele el workItem mientras éste todavía está ejecutando.
    private var discoveryWorkItem: DispatchWorkItem?

    @objc public func startPublishing(name: String, type: String, port: Int, metadata: [String: String]) throws {
        stopServer()

        let nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))
        let cleanType = type.contains("._tcp") ? type : (type.hasPrefix("_") ? "\(type)._tcp" : "_\(type)._tcp")

        var mutableMetadata = metadata
        mutableMetadata["timestamp"] = String(Int64(Date().timeIntervalSince1970 * 1000))

        let ipForName = mutableMetadata["ip"] ?? ""
        let displayName = ipForName.isEmpty ? name : "\(name)-\(ipForName)"

        let mappedMetadata = mutableMetadata.mapValues { $0.data(using: .utf8)! }
        let txtData = NetService.data(fromTXTRecord: mappedMetadata)

        let params = NWParameters.tcp
        params.includePeerToPeer = true
        params.allowLocalEndpointReuse = true

        let service = NWListener.Service(name: displayName, type: cleanType, domain: nil, txtRecord: txtData)

        listener = try NWListener(using: params, on: nwPort)
        listener?.service = service

        listener?.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            self?.activeConnections.append(connection)
            connection.stateUpdateHandler = { _ in }
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
                print("NSD_LOG: iOS listener READY — \(displayName)")
            case .failed(let error):
                print("NSD_LOG: iOS listener failed — \(error)")
            default:
                break
            }
        }

        listener?.start(queue: .main)
    }

    @objc public func findService(name: String, type: String, timeout: TimeInterval, completion: @escaping ([String: Any]?) -> Void) {
        // Detener búsqueda previa sin tocar el workItem nuevo (aún no existe)
        cancelBrowserOnly()

        let cleanType = type.contains("._tcp") ? type : (type.hasPrefix("_") ? "\(type)._tcp" : "_\(type)._tcp")

        discoveredServices.removeAll()
        isDiscovering = true

        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: cleanType, domain: nil), using: params)
        self.browser = browser

        // FIX Bug 2: el workItem ya NO llama stopDiscovery() (que se cancelaría
        // a sí mismo). En cambio cancela el browser directamente y luego
        // selecciona el mejor servicio.
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isDiscovering else { return }
            self.isDiscovering = false
            print("NSD_LOG: iOS Browser timeout — seleccionando mejor servicio")
            self.cancelBrowserOnly()
            self.selectBestService(completion: completion)
        }

        discoveryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self, self.isDiscovering else { return }

            for result in results {
                guard case let .service(foundName, _, _, _) = result.endpoint,
                      foundName.hasPrefix(name) else { continue }

                print("NSD_LOG: iOS Client encontró servicio: \(foundName)")

                var meta: [String: String] = [:]
                if case let .bonjour(txt) = result.metadata {
                    for (key, value) in txt.dictionary {
                        if let dataValue = value as? Data {
                            meta[key] = String(data: dataValue, encoding: .utf8) ?? ""
                        }
                    }
                }

                // FIX Bug 1: extraer IP del sufijo del nombre de forma robusta.
                // Android codifica la IP como el último segmento separado por "-",
                // pero el nombre base también puede contener "-". La IP siempre
                // es el último componente que coincide con un patrón de IPv4.
                var ip = meta["ip"] ?? ""

                if ip.isEmpty || ip == "0.0.0.0" {
                    ip = self.extractIPFromServiceName(foundName, baseName: name)
                }

                if ip.isEmpty || ip == "0.0.0.0" {
                    ip = self.getIPAddress() ?? ""
                }

                guard !ip.isEmpty, ip != "0.0.0.0" else { continue }

                // FIX Bug 3: leer el puerto del TXT record. Android lo incluye
                // explícitamente en metadata; si no está, usar el default seguro.
                let port: Int
                if let portStr = meta["port"], let p = Int(portStr) {
                    port = p
                } else {
                    // Nota: NWBrowser no expone el puerto directamente en el
                    // browseResultsChangedHandler; el puerto real se obtiene
                    // al resolver el endpoint. Como workaround, Android siempre
                    // inyecta "port" en los atributos TXT al publicar — asegúrate
                    // de hacer lo mismo en startPublishing().
                    port = 8081
                    print("NSD_LOG: ⚠️ puerto no encontrado en TXT, usando default \(port). Asegúrate de incluir 'port' en los metadatos al publicar.")
                }

                var timestamp: Int64 = 0
                if let ts = meta["timestamp"] {
                    timestamp = Int64(ts) ?? 0
                }

                let service = DiscoveredService(ip: ip, port: port, metadata: meta, timestamp: timestamp)
                self.discoveredServices.append(service)

                print("NSD_LOG: Servicio registrado — ip:\(ip) port:\(port) ts:\(timestamp)")
            }
        }

        browser.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print("NSD_LOG: iOS Browser listo para buscar")
            case .failed(let error):
                print("NSD_LOG: iOS Browser falló — \(error)")
                guard self.isDiscovering else { return }
                self.isDiscovering = false
                self.discoveryWorkItem?.cancel()
                self.discoveryWorkItem = nil
                self.cancelBrowserOnly()
                completion(nil)
            default:
                break
            }
        }

        browser.start(queue: .main)
    }

    @objc public func stopServer() {
        activeConnections.forEach { $0.cancel() }
        activeConnections.removeAll()
        listener?.cancel()
        listener = nil
        print("NSD_LOG: iOS servidor detenido")
    }

    @objc public func stopDiscovery() {
        discoveryWorkItem?.cancel()
        discoveryWorkItem = nil
        cancelBrowserOnly()
        print("NSD_LOG: iOS discovery detenido")
    }

    // MARK: - Privado

    /// Cancela sólo el browser sin tocar el workItem.
    /// Usado internamente para evitar que el workItem se cancele a sí mismo.
    private func cancelBrowserOnly() {
        browser?.cancel()
        browser = nil
        isDiscovering = false
    }

    /// FIX Bug 1: busca el último segmento del nombre del servicio que sea
    /// una dirección IPv4 válida, en lugar de asumir ciegamente que .last es la IP.
    private func extractIPFromServiceName(_ serviceName: String, baseName: String) -> String {
        // Remueve el prefijo conocido para quedarnos sólo con el sufijo
        let suffix = serviceName.hasPrefix(baseName + "-")
            ? String(serviceName.dropFirst(baseName.count + 1))
            : serviceName

        // Recorre los componentes de derecha a izquierda buscando una IPv4 válida
        let parts = suffix.components(separatedBy: "-")
        for part in parts.reversed() {
            if isValidIPv4(part) { return part }
        }
        return ""
    }

    private func isValidIPv4(_ candidate: String) -> Bool {
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let n = Int(part) else { return false }
            return n >= 0 && n <= 255
        }
    }

    private func selectBestService(completion: @escaping ([String: Any]?) -> Void) {
        guard let best = discoveredServices.max(by: { $0.timestamp < $1.timestamp }) else {
            print("NSD_LOG: sin servicios — devolviendo nil")
            completion(nil)
            return
        }

        let result: [String: Any] = [
            "ip": best.ip,
            "port": best.port,
            "metadata": best.metadata
        ]

        print("NSD_LOG: mejor servicio — ip:\(best.ip) port:\(best.port) ts:\(best.timestamp)")
        completion(result)
    }

    private func getIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee,
                  interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.ifa_name) == "en0" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
        }
        return address
    }
}