import crypto from 'node:crypto';
import fs from 'node:fs';
import { pipeline } from 'node:stream/promises';

const MAGIC = Buffer.from('OYYOPKG1', 'ascii');
const AAD = Buffer.from('OYYO Windows demo package v1', 'utf8');
const [encryptedPath, outputPath, expectedHashRaw] = process.argv.slice(2);

let secretInput;
let key;
let header;
let outputFd;
let outputCreated = false;

function fail(message) {
  throw new Error(message);
}

function decodeHexKey(input) {
  let start = 0;
  let end = input.length;
  while (start < end && (input[start] === 0x0a || input[start] === 0x0d || input[start] === 0x20 || input[start] === 0x09)) start += 1;
  while (end > start && (input[end - 1] === 0x0a || input[end - 1] === 0x0d || input[end - 1] === 0x20 || input[end - 1] === 0x09)) end -= 1;
  if (end - start !== 64) fail('Enter the 64-character OYYO demo key.');

  const decoded = Buffer.alloc(32);
  const nibble = (byte) => {
    if (byte >= 0x30 && byte <= 0x39) return byte - 0x30;
    if (byte >= 0x41 && byte <= 0x46) return byte - 0x41 + 10;
    if (byte >= 0x61 && byte <= 0x66) return byte - 0x61 + 10;
    return -1;
  };
  for (let index = 0; index < decoded.length; index += 1) {
    const high = nibble(input[start + index * 2]);
    const low = nibble(input[start + index * 2 + 1]);
    if (high < 0 || low < 0) {
      decoded.fill(0);
      fail('Enter the 64-character OYYO demo key.');
    }
    decoded[index] = (high << 4) | low;
  }
  return decoded;
}

try {
  if (!encryptedPath || !outputPath || !expectedHashRaw) {
    fail('Usage: decrypt-macos.mjs <encrypted-package> <output-archive> <expected-sha256>.');
  }
  const expectedHash = expectedHashRaw.toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(expectedHash)) fail('The package manifest has an invalid SHA-256 value.');

  const chunks = [];
  let inputBytes = 0;
  for await (const chunk of process.stdin) {
    inputBytes += chunk.length;
    if (inputBytes > 256) fail('The OYYO demo key input is too long.');
    chunks.push(chunk);
  }
  secretInput = Buffer.concat(chunks);
  key = decodeHexKey(secretInput);

  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(encryptedPath)) hash.update(chunk);
  const actualHash = hash.digest('hex');
  if (actualHash !== expectedHash) fail('Download verification failed. Download the package again.');

  const stat = fs.statSync(encryptedPath);
  if (stat.size < 37) fail('Unsupported OYYO package.');
  header = Buffer.alloc(36);
  const inputFd = fs.openSync(encryptedPath, 'r');
  try {
    if (fs.readSync(inputFd, header, 0, header.length, 0) !== header.length) fail('Unsupported OYYO package.');
  } finally {
    fs.closeSync(inputFd);
  }
  if (!crypto.timingSafeEqual(header.subarray(0, 8), MAGIC)) {
    fail('Unsupported OYYO package.');
  }

  outputFd = fs.openSync(outputPath, 'wx', 0o600);
  outputCreated = true;
  try {
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, header.subarray(8, 20));
    decipher.setAAD(AAD);
    decipher.setAuthTag(header.subarray(20, 36));
    await pipeline(
      fs.createReadStream(encryptedPath, { start: 36 }),
      decipher,
      fs.createWriteStream(outputPath, { fd: outputFd, autoClose: false }),
    );
  } catch {
    fail('The demo key is invalid or this package is damaged. Nothing was installed.');
  }

  fs.fsyncSync(outputFd);
  fs.closeSync(outputFd);
  outputFd = undefined;
  process.stdout.write('Demo key accepted. Package authenticated.\n');
} catch (error) {
  if (outputFd !== undefined) {
    try { fs.closeSync(outputFd); } catch { /* best effort */ }
  }
  if (outputCreated) {
    try { fs.unlinkSync(outputPath); } catch { /* best effort */ }
  }
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
} finally {
  secretInput?.fill(0);
  key?.fill(0);
  header?.fill(0);
}
