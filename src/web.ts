import { WebPlugin } from '@capacitor/core';

import type { NetworkDiscoveryPlugin } from './definitions';

export class NetworkDiscoveryWeb extends WebPlugin implements NetworkDiscoveryPlugin {
  async echo(options: { value: string }): Promise<{ value: string }> {
    console.log('ECHO', options);
    return options;
  }
}
