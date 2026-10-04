// Composes the website images from the offscreen renders (see scripts/screens.sh):
//   docs/preview.png     menubar strip (Dial style) + the popup under it
//   docs/bar-styles.png  the five menubar styles
import sharp from 'sharp'

const [, , out, docs] = process.argv
const meta = (f) => sharp(f).metadata()

const bg = (W, H) => `<defs>
  <radialGradient id="glow" cx="0.85" cy="0" r="0.9"><stop offset="0" stop-color="#d97757" stop-opacity="0.55"/><stop offset="1" stop-color="#d97757" stop-opacity="0"/></radialGradient>
  <linearGradient id="base" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1a1517"/><stop offset="1" stop-color="#0f0f12"/></linearGradient>
  <filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="22"/></filter>
</defs>
<rect width="${W}" height="${H}" fill="url(#base)"/><rect width="${W}" height="${H}" fill="url(#glow)"/>`

// the popup on a dark panel (the popover background)
const p = `${out}/popup-dark.png`, pm = await meta(p)
const panel = await sharp(Buffer.from(`<svg width="${pm.width}" height="${pm.height}" xmlns="http://www.w3.org/2000/svg"><rect x="1" y="1" width="${pm.width - 2}" height="${pm.height - 2}" rx="24" fill="#2a2a2d" stroke="#ffffff" stroke-opacity="0.12" stroke-width="2"/></svg>`))
	.composite([{ input: p }]).png().toBuffer()

// screenshot: menubar strip with the Dial style + the popup under it
{
	const bar = `${out}/bar-dark-dial.png`, bm = await meta(bar)
	const W = 1600, stripH = 48, H = stripH + 24 + pm.height + 70
	const barX = W - 40 - bm.width, barY = Math.round((stripH - bm.height) / 2)
	const px = Math.min(W - 24 - pm.width, Math.round(barX + bm.width / 2 - pm.width / 2)), py = stripH + 24
	const svg = `<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">${bg(W, H)}
  <rect width="${W}" height="${stripH}" fill="#000" fill-opacity="0.45"/>
  <rect x="${barX - 12}" y="5" width="${bm.width + 24}" height="${stripH - 10}" rx="10" fill="#fff" fill-opacity="0.14"/>
  <rect x="${px + 10}" y="${py + 26}" width="${pm.width - 20}" height="${pm.height - 10}" rx="24" fill="#000" fill-opacity="0.6" filter="url(#sh)"/>
</svg>`
	await sharp(Buffer.from(svg)).composite([{ input: bar, left: barX, top: barY }, { input: panel, left: px, top: py }])
		.png({ compressionLevel: 9 }).toFile(`${docs}/preview.png`)
	console.log('wrote docs/preview.png', W, H)
}

// the five menubar styles, as labeled dark strips
{
	const styles = [['text', 'Text'], ['coloredText', 'Color'], ['meter', 'Meter'], ['meterText', 'Meter + %'], ['dial', 'Dial']]
	const ms = await Promise.all(styles.map(([s]) => meta(`${out}/bar-dark-${s}.png`)))
	const labelW = 240, W = labelW + Math.max(...ms.map((m) => m.width)) + 60, rowH = 72, gap = 10, H = styles.length * (rowH + gap) - gap
	let rows = ''
	const comps = []
	styles.forEach(([s, name], i) => {
		const y = i * (rowH + gap)
		rows += `<rect y="${y}" width="${W}" height="${rowH}" rx="14" fill="#1c1c1f"/><text x="28" y="${y + rowH / 2 + 9}" font-family="Helvetica, Arial, sans-serif" font-size="26" fill="#a1a1aa">${name}</text>`
		comps.push({ input: `${out}/bar-dark-${s}.png`, left: labelW, top: y + Math.round((rowH - ms[i].height) / 2) })
	})
	await sharp(Buffer.from(`<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">${rows}</svg>`)).composite(comps)
		.png({ compressionLevel: 9 }).toFile(`${docs}/bar-styles.png`)
	console.log('wrote docs/bar-styles.png', W, H)
}
