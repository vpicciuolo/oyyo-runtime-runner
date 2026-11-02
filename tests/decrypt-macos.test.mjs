import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const decryptor = path.resolve(import.meta.dirname, '..', 'decrypt-macos.mjs');
const AAD = Buffer.from('OYYO Windows demo package v1', 'utf8');

function envelope(plaintext, key = crypto.randomBytes(32)) {
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(AAD);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return {
    key,
    bytes: Buffer.concat([Buffer.from('OYYOPKG1'), nonce, cipher.getAuthTag(), ciphertext]),
  };
}

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function runDecrypt(root, bytes, keyInput, suffix = '') {
  const encrypted = path.join(root, `package${suffix}.oyyo`);
  const output = path.join(root, `package${suffix}.tar.gz`);
  fs.writeFileSync(encrypted, bytes, { mode: 0o600 });
  const result = spawnSync(process.execPath, [decryptor, encrypted, output, sha256(bytes)], {
    input: keyInput,
    encoding: 'utf8',
    env: { ...process.env, OYYO_DEMO_KEY: 'f'.repeat(64) },
  });
  return { ...result, output };
}

test('authenticates and writes an exact OYYOPKG1 plaintext', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'oyyo-decrypt-test-'));
  try {
    const plaintext = crypto.randomBytes(4096);
    const fixture = envelope(plaintext);
    const result = runDecrypt(root, fixture.bytes, `${fixture.key.toString('hex')}\n`);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(fs.readFileSync(result.output), plaintext);
    assert.match(result.stdout, /Package authenticated/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
test('rejects a wrong stdin key and ignores a key-shaped environment variable', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'oyyo-decrypt-test-'));
  try {
    const fixture = envelope(Buffer.from('private fixture'));
    const result = runDecrypt(root, fixture.bytes, `${'0'.repeat(64)}\n`, '-wrong');
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /invalid or this package is damaged/);
    assert.equal(fs.existsSync(result.output), false);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
test('rejects authenticated-envelope tampering even when the supplied SHA matches', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'oyyo-decrypt-test-'));
  try {
    const fixture = envelope(crypto.randomBytes(512));
    const tampered = Buffer.from(fixture.bytes);
    tampered[tampered.length - 1] ^= 0x01;
    const result = runDecrypt(root, tampered, `${fixture.key.toString('hex')}\n`, '-tampered');
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /invalid or this package is damaged/);
    assert.equal(fs.existsSync(result.output), false);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
test('never overwrites an existing plaintext destination', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'oyyo-decrypt-test-'));
  try {
    const fixture = envelope(Buffer.from('new plaintext'));
    const encrypted = path.join(root, 'existing.oyyo');
    const output = path.join(root, 'existing.tar.gz');
    fs.writeFileSync(encrypted, fixture.bytes);
    fs.writeFileSync(output, 'keep me');
    const result = spawnSync(process.execPath, [decryptor, encrypted, output, sha256(fixture.bytes)], {
      input: `${fixture.key.toString('hex')}\n`,
      encoding: 'utf8',
    });
    assert.notEqual(result.status, 0);
    assert.equal(fs.readFileSync(output, 'utf8'), 'keep me');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
