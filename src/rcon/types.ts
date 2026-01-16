export interface RCONConfig {
  host: string;
  port: number;
  password: string;
}

export interface RCONResponse {
  success: boolean;
  data: string;
  error?: string;
}
