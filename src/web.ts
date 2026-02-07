import { WebPlugin } from '@capacitor/core';

import type {
  NetworkDiscoveryPlugin,
  AdvertisingOptions,
  DiscoveryOptions
} from './definitions';

export class NetworkDiscoveryWeb extends WebPlugin implements NetworkDiscoveryPlugin {
  async startAdvertising(options: AdvertisingOptions): Promise<{ success: boolean }> {
    console.log('startAdvertising', options);
    throw this.unimplemented('Not implemented on web.');
  }

  async stopAdvertising(): Promise<{ success: boolean }> {
    throw this.unimplemented('Not implemented on web.');
  }

  async startDiscovery(options: DiscoveryOptions): Promise<void> {
    console.log('startDiscovery', options);
    throw this.unimplemented('Not implemented on web.');
  }

  async stopDiscovery(): Promise<{ success: boolean }> {
    throw this.unimplemented('Not implemented on web.');
  }
}