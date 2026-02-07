export interface NetworkDiscoveryPlugin {
  /**
   * Publica el servicio en la red local
   */
  startAdvertising(options: AdvertisingOptions): Promise<{ success: boolean }>;

  /**
   * Detiene la publicación del servicio
   */
  stopAdvertising(): Promise<{ success: boolean }>;

  /**
   * Busca servicios en la red local
   */
  startDiscovery(options: DiscoveryOptions): Promise<void>;

  /**
   * Detiene la búsqueda de servicios
   */
  stopDiscovery(): Promise<{ success: boolean }>;

  /**
   * Listener para cuando se descubre un servicio
   */
  addListener(
    eventName: 'serviceFound',
    listenerFunc: (service: ServiceInfo) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Listener para cuando se pierde un servicio
   */
  addListener(
    eventName: 'serviceLost',
    listenerFunc: (service: ServiceInfo) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Remueve todos los listeners
   */
  removeAllListeners(): Promise<void>;
}

export interface AdvertisingOptions {
  serviceName: string;
  serviceType: string; // e.g., "_http._tcp"
  port: number;
  txtRecord?: { [key: string]: string }; // Para pasar la IP u otros datos
}

export interface DiscoveryOptions {
  serviceType: string; // e.g., "_http._tcp"
  domain?: string; // default: "local."
}

export interface ServiceInfo {
  serviceName: string;
  serviceType: string;
  domain: string;
  hostName: string;
  port: number;
  addresses: string[]; // IPs del servicio
  txtRecord?: { [key: string]: string };
}

export interface PluginListenerHandle {
  remove: () => Promise<void>;
}