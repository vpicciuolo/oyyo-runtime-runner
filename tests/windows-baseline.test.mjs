import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '..');
const expected = new Map([
  ['release.json', 'a01dc3759f905362e56deceda8cd156c8c37f2c2e7ed8c496055575bc7c75851'],
  ['Install-OYYO.ps1', 'ca25abfef339359bbefe2204260f1c64b7867d9dd46d6009e01ea2bf981a19af'],
  ['decrypt.mjs', '366b3f56b8f0a32478104d40663dec12e8cd0465a364044803e09e324dc054cd'],
  ['oyyo.ico', '9b397582164bdf97d81881b143c0661621baf37e8fc9253f1140eeffbfc75dbb'],
]);

test('additive Mac support leaves every Windows payload file byte-for-byte unchanged', () => {
  for (const [name, digest] of expected) {
    const actual = crypto.createHash('sha256').update(fs.readFileSync(path.join(root, name))).digest('hex');
    assert.equal(actual, digest, `${name} changed unexpectedly`);
  }
  const release = JSON.parse(fs.readFileSync(path.join(root, 'release.json'), 'utf8'));
  assert.equal(release.platform, 'windows-x64');
  assert.equal(release.version, '0.1.10');
});

test('public Mac manifests remain deliberately non-ready until production encryption', () => {
  for (const arch of ['arm64', 'x64']) {
    const manifest = JSON.parse(fs.readFileSync(path.join(root, `release-macos-${arch}.json`), 'utf8'));
    assert.equal(manifest.status, 'awaiting-production-encryption');
    assert.equal(manifest.sha256, null);
    assert.equal(manifest.sizeBytes, 0);
    assert.equal(manifest.payloadArchive, 'tar.gz');
    assert.equal(manifest.platform, `macos-${arch}`);
  }
});
