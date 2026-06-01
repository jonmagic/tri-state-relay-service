export const appProcessorAuthorization = 'app-owned-processor'
export const appProcessorAuthorizationEnv = 'TSRS_PROCESSOR_AUTH'

export function processorIsAppAuthorized(env: Record<string, string | undefined> = process.env): boolean {
  return env[appProcessorAuthorizationEnv] === appProcessorAuthorization
}

