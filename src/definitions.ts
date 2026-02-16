export interface NetworkDiscoveryPlugin {
  /**
   * Inicia el servidor de descubrimiento en la red local
   * @param options Opciones de configuración del servidor
   */
  startServer(options: StartServerOptions): Promise<void>;

  /**
   * Detiene el servidor de descubrimiento
   */
  stopServer(): Promise<void>;

  /**
   * Busca un servidor en la red local
   * @param options Opciones de búsqueda
   * @returns Información del servidor encontrado o null si no se encuentra
   */
  findServer(options: FindServerOptions): Promise<DiscoveryResult>;
}

export interface StartServerOptions {
  /**
   * Nombre del servicio (ej: 'SSSPOSServer')
   */
  serviceName: string;

  /**
   * Tipo de servicio (ej: '_ssspos._tcp')
   */
  serviceType: string;

  /**
   * Puerto en el que se publica el servicio de discovery (ej: 8081)
   */
  port: number;

  /**
   * IP del servidor (se incluirá en metadata y nombre)
   */
  ip: string;

  /**
   * Metadata adicional (ej: { httpPort: '8080', version: '1.0' })
   */
  metadata?: { [key: string]: string };
}

export interface FindServerOptions {
  /**
   * Nombre del servicio a buscar (ej: 'SSSPOSServer')
   */
  serviceName: string;

  /**
   * Tipo de servicio (ej: '_ssspos._tcp')
   */
  serviceType: string;

  /**
   * Timeout de búsqueda en milisegundos (default: 10000)
   */
  timeout?: number;
}

export interface DiscoveryResult {
  /**
   * Dirección IP del servidor encontrado
   */
  ip: string;

  /**
   * Puerto del servidor encontrado
   */
  port: number;

  /**
   * Metadata del servidor (incluye datos como httpPort, version, etc.)
   */
  metadata: { [key: string]: string };
}

// Alias para compatibilidad con tu código existente
export interface DiscoveryOptions extends StartServerOptions { }