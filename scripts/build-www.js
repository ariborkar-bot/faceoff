// Copies the website files into www/ so Capacitor can bundle them into the iOS app.
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..'), out = path.join(root, 'www');
const items = ['index.html', 'privacy.html', 'manifest.webmanifest', 'sw.js', 'icons', 'brand', 'fonts'];
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
for (const it of items) fs.cpSync(path.join(root, it), path.join(out, it), { recursive: true });
console.log('www/ ready:', items.join(', '));
