import crypto from 'node:crypto';
import fs from 'node:fs';

const [archivePath, outputPath] = process.argv.slice(2);
const AAD = Buffer.from('OYYO Windows demo package v1', 'utf8');
let input;
let key;
let plaintext;
let encrypted;

try {
  if (!archivePath || !outputPath) throw new Error('Usage: make-test-package.mjs <archive> <output>.');
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  input = Buffer.concat(chunks);
  const value = input.toString('ascii').trim();
  if (!/^[a-fA-F0-9]{64}$/.test(value)) throw new Error('Test key must contain 64 hexadecimal characters.');
  key = Buffer.from(value, 'hex');
  plaintext = fs.readFileSync(archivePath);
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(AAD);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  encrypted = Buffer.concat([Buffer.from('OYYOPKG1'), nonce, cipher.getAuthTag(), ciphertext]);
  fs.writeFileSync(outputPath, encrypted, { flag: 'wx', mode: 0o600 });
  const result = {
    sha256: crypto.createHash('sha256').update(encrypted).digest('hex'),
    sizeBytes: encrypted.length,
  };
  process.stdout.write(`${JSON.stringify(result)}\n`);
} finally {
  input?.fill(0);
  key?.fill(0);
  plaintext?.fill(0);
  encrypted?.fill(0);
}
