import assert from 'node:assert/strict'
import test from 'node:test'

import { distributionProfile, isAppStoreProfile } from '../src/core/distribution-profile.ts'

test('distribution profile defaults direct unless app-store is explicit', () => {
  assert.equal(distributionProfile({}), 'direct')
  assert.equal(distributionProfile({ TSRS_DISTRIBUTION_PROFILE: 'direct' }), 'direct')
  assert.equal(distributionProfile({ TSRS_DISTRIBUTION_PROFILE: 'app-store' }), 'app-store')
  assert.equal(isAppStoreProfile({ TSRS_DISTRIBUTION_PROFILE: 'app-store' }), true)
})

