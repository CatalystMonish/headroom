// Generates the app icon: the logo in white on a warm-orange macOS squircle.
// Renders an .iconset via sharp, then iconutil -> icon/AppIcon.icns.
//
//   npm install && npm run icon
//
import sharp from 'sharp'
import { execFileSync } from 'child_process'
import { mkdirSync, readFileSync, rmSync } from 'fs'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'

const HERE = dirname(fileURLToPath(import.meta.url))
const S = 1024
const M = 100, BG = S - M * 2, BR = Math.round(BG * 0.2237) // squircle inset + corner radius
const LOGO = 520 // logo box, centered

const logo = readFileSync(join(HERE, '..', 'assets', 'logo.svg'), 'utf8')
	.replaceAll('#D97757', '#ffffff')
	.replace('<svg ', `<svg x="${(S - LOGO) / 2}" y="${(S - LOGO) / 2}" width="${LOGO}" height="${LOGO}" `)

const svg = `<svg width="${S}" height="${S}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#e2876a"/>
      <stop offset="1" stop-color="#c9603f"/>
    </linearGradient>
  </defs>
  <rect x="${M}" y="${M}" width="${BG}" height="${BG}" rx="${BR}" ry="${BR}" fill="url(#bg)"/>
  ${logo}
</svg>`

const sizes = [
	[16, 'icon_16x16.png'], [32, 'icon_16x16@2x.png'],
	[32, 'icon_32x32.png'], [64, 'icon_32x32@2x.png'],
	[128, 'icon_128x128.png'], [256, 'icon_128x128@2x.png'],
	[256, 'icon_256x256.png'], [512, 'icon_256x256@2x.png'],
	[512, 'icon_512x512.png'], [1024, 'icon_512x512@2x.png'],
]

const setDir = join(HERE, 'AppIcon.iconset')
rmSync(setDir, { recursive: true, force: true })
mkdirSync(setDir, { recursive: true })
const master = await sharp(Buffer.from(svg)).png().toBuffer()
for (const [px, name] of sizes) await sharp(master).resize(px, px).png().toFile(join(setDir, name))
execFileSync('iconutil', ['-c', 'icns', setDir, '-o', join(HERE, 'AppIcon.icns')])
rmSync(setDir, { recursive: true, force: true })
// 512px PNG for the website / README
await sharp(master).resize(512, 512).png().toFile(join(HERE, '..', 'docs', 'app-icon.png'))
console.log('wrote icon/AppIcon.icns and docs/app-icon.png')
