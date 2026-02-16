import { WebPlugin } from '@capacitor/core';

import type {
  NetworkDiscoveryPlugin,
  StartServerOptions,
  FindServerOptions,
  DiscoveryResult,
} from './definitions';

export class NetworkDiscoveryWeb
  extends WebPlugin
  implements NetworkDiscoveryPlugin {
  async startServer(options: StartServerOptions): Promise<void> {
    console.warn(
      '[NetworkDiscovery Web] startServer no está disponible en web',
      options
    );
    throw this.unavailable(
      'Network Discovery no está soportado en plataforma web. Use en iOS o Android.'
    );
  }

  async stopServer(): Promise<void> {
    console.warn('[NetworkDiscovery Web] stopServer no está disponible en web');
    throw this.unavailable(
      'Network Discovery no está soportado en plataforma web. Use en iOS o Android.'
    );
  }

  async findServer(options: FindServerOptions): Promise<DiscoveryResult> {
    console.warn(
      '[NetworkDiscovery Web] findServer no está disponible en web',
      options
    );
    throw this.unavailable(
      'Network Discovery no está soportado en plataforma web. Use en iOS o Android.'
    );
  }
}