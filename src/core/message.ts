export const messageTypes = ['update', 'complete', 'blocked', 'needs-input'] as const
export const priorities = ['low', 'normal', 'high'] as const
export const messageStatuses = ['queued', 'speaking', 'heard', 'handled', 'skipped', 'expired', 'failed'] as const

export type MessageType = typeof messageTypes[number]
export type Priority = typeof priorities[number]
export type MessageStatus = typeof messageStatuses[number]

export interface NewVoicemailInput {
  project: string
  message: string
  type?: string
  priority?: string
  session?: string
  app?: string
  cwd?: string
  url?: string
}

export interface NewVoicemail {
  project: string
  message: string
  type: MessageType
  priority: Priority
  session?: string
  app?: string
  cwd?: string
  url?: string
}

export interface Voicemail extends NewVoicemail {
  id: number
  status: MessageStatus
  createdAt: string
  updatedAt: string
}

const maxMessageLength = 240
const tokenPatterns = [
  /gh[pousr]_[A-Za-z0-9_]{20,}/,
  /github_pat_[A-Za-z0-9_]{20,}/,
  /(?:api[_-]?key|token|secret)\s*[:=]\s*\S{8,}/i,
  /[A-Za-z0-9+/]{32,}={0,2}/,
]

export function normalizeVoicemail(input: NewVoicemailInput): NewVoicemail {
  const project = normalizeRequiredText(input.project, 'project', 80)
  const message = normalizeRequiredText(input.message, 'message', maxMessageLength)
  const type = normalizeEnum(input.type ?? 'update', messageTypes, 'type')
  const priority = normalizeEnum(input.priority ?? 'normal', priorities, 'priority')

  rejectUnsafeMessage(message)

  return stripUndefined({
    project,
    message,
    type,
    priority,
    session: normalizeOptionalText(input.session, 120),
    app: normalizeOptionalText(input.app, 80),
    cwd: normalizeOptionalText(input.cwd, 500),
    url: normalizeOptionalText(input.url, 500),
  })
}

export function spokenText(voicemail: Pick<Voicemail, 'project' | 'type' | 'message'>): string {
  const typePrefix = voicemail.type === 'update' ? '' : `${voicemail.type}. `
  return `${voicemail.project}. ${typePrefix}${voicemail.message}`
}

function normalizeRequiredText(value: string, field: string, maxLength: number): string {
  const normalized = value.trim().replace(/\s+/g, ' ')

  if (normalized.length === 0) {
    throw new Error(`${field} is required`)
  }

  if (normalized.length > maxLength) {
    throw new Error(`${field} must be ${maxLength} characters or fewer`)
  }

  return normalized
}

function normalizeOptionalText(value: string | undefined, maxLength: number): string | undefined {
  if (value === undefined) {
    return undefined
  }

  const normalized = value.trim().replace(/\s+/g, ' ')

  if (normalized.length === 0) {
    return undefined
  }

  if (normalized.length > maxLength) {
    throw new Error(`optional metadata must be ${maxLength} characters or fewer`)
  }

  return normalized
}

function normalizeEnum<T extends readonly string[]>(value: string, allowed: T, field: string): T[number] {
  if (allowed.includes(value)) {
    return value as T[number]
  }

  throw new Error(`${field} must be one of: ${allowed.join(', ')}`)
}

function rejectUnsafeMessage(message: string): void {
  for (const pattern of tokenPatterns) {
    if (pattern.test(message)) {
      throw new Error('message looks like it may contain a secret or token')
    }
  }
}

function stripUndefined<T extends Record<string, unknown>>(value: T): T {
  return Object.fromEntries(Object.entries(value).filter(([, entry]) => entry !== undefined)) as T
}
