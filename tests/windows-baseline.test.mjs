import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '..');
const expected = new Map([
  ['release.json', { digest: 'd4abef12be400b7ca31b66a35fe0444face0a79c6824d649bad5dbcb8def044e', text: true }],
  ['Install-OYYO.ps1', { digest: 'ca25abfef339359bbefe2204260f1c64b7867d9dd46d6009e01ea2bf981a19af', text: true }],
  ['decrypt.mjs', { digest: '366b3f56b8f0a32478104d40663dec12e8cd0465a364044803e09e324dc054cd', text: true }],
  ['oyyo.ico', { digest: '9b397582164bdf97d81881b143c0661621baf37e8fc9253f1140eeffbfc75dbb', text: false }],
]);

test('Windows bootstrap stays unchanged alongside the verified Windows testing feed', () => {
  for (const [name, expectation] of expected) {
    const bytes = fs.readFileSync(path.join(root, name));
    const canonical = expectation.text
      ? Buffer.from(bytes.toString('utf8').replaceAll('\r\n', '\n'), 'utf8')
      : bytes;
    const actual = crypto.createHash('sha256').update(canonical).digest('hex');
    const { digest } = expectation;
    assert.equal(actual, digest, `${name} changed unexpectedly`);
  }
  const release = JSON.parse(fs.readFileSync(path.join(root, 'release.json'), 'utf8'));
  assert.equal(release.platform, 'windows-x64');
  assert.equal(release.version, '0.1.15');
});

test('public Mac manifests expose only verified immutable releases', () => {
  const arm64 = JSON.parse(fs.readFileSync(path.join(root, 'release-macos-arm64.json'), 'utf8'));
  assert.equal(arm64.version, '0.1.10');
  assert.equal(arm64.platform, 'macos-arm64');
  assert.equal(arm64.format, 'OYYOPKG1');
  assert.equal(arm64.encryption, 'AES-256-GCM');
  assert.equal(arm64.payloadArchive, 'tar.gz');
  assert.equal(arm64.url, 'https://github.com/vpicciuolo/oyyo-runtime-runner/releases/download/v0.1.10/oyyo-macos-arm64-demo-0.1.10.oyyo');
  if (arm64.status === 'ready') {
    assert.match(arm64.sha256, /^[a-f0-9]{64}$/);
    assert.notEqual(arm64.sha256, '0'.repeat(64));
    assert.ok(Number.isSafeInteger(arm64.sizeBytes) && arm64.sizeBytes > 0);
  } else {
    assert.equal(arm64.status, 'awaiting-production-encryption');
    assert.equal(arm64.sha256, null);
    assert.equal(arm64.sizeBytes, 0);
  }

  const x64 = JSON.parse(fs.readFileSync(path.join(root, 'release-macos-x64.json'), 'utf8'));
  assert.equal(x64.version, '0.1.10');
  assert.equal(x64.platform, 'macos-x64');
  assert.equal(x64.format, 'OYYOPKG1');
  assert.equal(x64.encryption, 'AES-256-GCM');
  assert.equal(x64.payloadArchive, 'tar.gz');
  assert.equal(x64.url, 'https://github.com/vpicciuolo/oyyo-runtime-runner/releases/download/v0.1.10/oyyo-macos-x64-demo-0.1.10.oyyo');
  assert.equal(x64.status, 'awaiting-production-encryption');
  assert.equal(x64.sha256, null);
  assert.equal(x64.sizeBytes, 0);
});
