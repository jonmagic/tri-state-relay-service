#!/usr/bin/env node
import { copyFileSync, existsSync, mkdirSync, rmSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { spawnSync } from 'node:child_process'

const profile = process.argv[2] ?? 'direct'

if (!['direct', 'app-store'].includes(profile)) {
  throw new Error(`unknown macOS build profile: ${profile}`)
}

const appName = 'Tri-State Relay Service.app'
const project = 'src/macos/TriStateRelayService.xcodeproj'
const target = 'Tri-State Relay Service'
const scheme = 'Tri-State Relay Service'
const distRoot = profile === 'app-store' ? 'dist/macos-app-store' : 'dist/macos'
const derivedData = profile === 'app-store' ? 'dist/xcode/app-store' : 'dist/xcode/direct'
const builtApp = join(derivedData, 'Build/Products/Release', appName)
const outputApp = join(distRoot, appName)
const outputMacOS = join(outputApp, 'Contents/MacOS')
const outputResources = join(outputApp, 'Contents/Resources')
const sourceAppIcon = 'src/macos/Assets/AppIcon.png'
const appIconName = 'AppIcon.icns'

run('npm', ['run', 'build:native:cli'])
rmSync(derivedData, { recursive: true, force: true })
rmSync(outputApp, { recursive: true, force: true })
mkdirSync(distRoot, { recursive: true })

const xcodebuildArgs = [
  '-project',
  project,
  '-scheme',
  scheme,
  '-configuration',
  'Release',
  '-derivedDataPath',
  derivedData,
  'CODE_SIGNING_ALLOWED=NO',
]

if (profile === 'app-store') {
  xcodebuildArgs.push('SWIFT_ACTIVE_COMPILATION_CONDITIONS=APP_STORE')
}

run('xcodebuild', xcodebuildArgs)
run('cp', ['-R', builtApp, distRoot])

copyFileSync('dist/native/relay', join(outputMacOS, 'relay'))
installAppIcon(outputResources)
verifyBundle(outputApp)

function run(command, args) {
  const result = spawnSync(command, args, { stdio: 'inherit' })

  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed`)
  }
}

function verifyBundle(appPath) {
  const infoPlist = join(appPath, 'Contents/Info.plist')
  const executable = plistValue(infoPlist, 'CFBundleExecutable')

  if (executable !== target) {
    throw new Error(`unexpected CFBundleExecutable: ${executable}`)
  }

  if (!existsSync(join(appPath, 'Contents/MacOS', executable))) {
    throw new Error(`bundle executable missing: ${executable}`)
  }

  if (!existsSync(join(appPath, 'Contents/MacOS/relay'))) {
    throw new Error('relay helper missing from bundle')
  }

  if (plistValue(infoPlist, 'CFBundleIconFile') !== 'AppIcon') {
    throw new Error('CFBundleIconFile was not preserved')
  }

  if (!existsSync(join(appPath, 'Contents/Resources', appIconName))) {
    throw new Error(`${appIconName} missing from bundle resources`)
  }

  if (existsSync(join(appPath, 'Contents/MacOS/relay-processor'))) {
    throw new Error('relay-processor must not be bundled in the macOS app')
  }

  if (!['1', 'true'].includes(plistValue(infoPlist, 'LSUIElement'))) {
    throw new Error('LSUIElement was not preserved')
  }
}

function plistValue(infoPlist, key) {
  const result = spawnSync('/usr/libexec/PlistBuddy', ['-c', `Print :${key}`, infoPlist], {
    encoding: 'utf8',
  })

  if (result.status !== 0) {
    throw new Error(`could not read ${key} from ${infoPlist}: ${result.stderr}`)
  }

  return result.stdout.trim()
}

function installAppIcon(resourcesPath) {
  if (!existsSync(sourceAppIcon)) {
    throw new Error(`source app icon missing: ${sourceAppIcon}`)
  }

  const iconsetPath = 'dist/macos-icon.iconset'
  rmSync(iconsetPath, { recursive: true, force: true })
  mkdirSync(iconsetPath, { recursive: true })
  mkdirSync(resourcesPath, { recursive: true })

  const iconSizes = [
    [16, 'icon_16x16.png'],
    [32, 'icon_16x16@2x.png'],
    [32, 'icon_32x32.png'],
    [64, 'icon_32x32@2x.png'],
    [128, 'icon_128x128.png'],
    [256, 'icon_128x128@2x.png'],
    [256, 'icon_256x256.png'],
    [512, 'icon_256x256@2x.png'],
    [512, 'icon_512x512.png'],
    [1024, 'icon_512x512@2x.png'],
  ]

  for (const [size, filename] of iconSizes) {
    run('sips', ['-z', String(size), String(size), sourceAppIcon, '--out', join(iconsetPath, filename)])
  }

  run('iconutil', ['-c', 'icns', iconsetPath, '-o', join(resourcesPath, appIconName)])
  rmSync(iconsetPath, { recursive: true, force: true })
}
