import { registerPlugin } from '@capacitor/core';

import type { NetworkDiscoveryPlugin } from './definitions';

const NetworkDiscovery = registerPlugin<NetworkDiscoveryPlugin>('NetworkDiscovery', {
  web: () => import('./web').then((m) => new m.NetworkDiscoveryWeb()),
});

export * from './definitions';
export { NetworkDiscovery };
