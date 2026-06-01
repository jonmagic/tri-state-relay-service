export type DistributionProfile = 'direct' | 'app-store'

export const distributionProfileEnv = 'TSRS_DISTRIBUTION_PROFILE'

export function distributionProfile(env: Record<string, string | undefined> = process.env): DistributionProfile {
  return env[distributionProfileEnv] === 'app-store' ? 'app-store' : 'direct'
}

export function isAppStoreProfile(env: Record<string, string | undefined> = process.env): boolean {
  return distributionProfile(env) === 'app-store'
}

