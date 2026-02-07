export interface NetworkDiscoveryPlugin {
  echo(options: { value: string }): Promise<{ value: string }>;
}
