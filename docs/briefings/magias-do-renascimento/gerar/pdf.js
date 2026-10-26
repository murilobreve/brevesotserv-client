const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const dir = process.argv[2];
  const shots = process.argv[3];
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1100, height: 1400 } });
  await page.goto('file://' + path.join(dir, 'LEIA-ME.html'));
  await page.waitForLoadState('networkidle');
  if (shots) {
    const h = await page.evaluate(() => document.body.scrollHeight);
    for (let i = 0, y = 0; y < h && i < 40; i++, y += 1400) {
      await page.evaluate(v => window.scrollTo(0, v), y);
      await page.screenshot({ path: path.join(shots, `p${String(i).padStart(2, '0')}.png`) });
    }
    console.log('height', h);
  }
  await page.pdf({ path: path.join(dir, 'LEIA-ME.pdf'), format: 'A4', printBackground: true,
    margin: { top: '14mm', bottom: '14mm', left: '12mm', right: '12mm' } });
  await browser.close();
})();
