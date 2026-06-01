import type { DistributionProfile } from './distribution-profile.ts'

export interface RelayCapabilities {
  profile: DistributionProfile
  lineLimit?: number
  nativeSpeech: boolean
  terminalEnqueue: boolean
  externalSpeechCommand: boolean
  externalInactiveLineCombiner: boolean
  nativeSourceActions: boolean
}

export function relayCapabilities(profile: DistributionProfile): RelayCapabilities {
  if (profile === 'app-store') {
    return {
      profile,
      lineLimit: 1,
      nativeSpeech: true,
      terminalEnqueue: false,
      externalSpeechCommand: false,
      externalInactiveLineCombiner: false,
      nativeSourceActions: true,
    }
  }

  return {
    profile,
    nativeSpeech: false,
    terminalEnqueue: true,
    externalSpeechCommand: true,
    externalInactiveLineCombiner: true,
    nativeSourceActions: false,
  }
}
