import fs from 'node:fs';import crypto from 'node:crypto';
// Never pass the demo key on the command line, print it, or save it in the installation.
const [encrypted,output,expectedHash]=process.argv.slice(2);const secret=process.env.OYYO_DEMO_KEY||'';delete process.env.OYYO_DEMO_KEY;
try{
 if(!/^[a-fA-F0-9]{64}$/.test(secret))throw Error('Enter the 64-character OYYO demo key.');
 const bytes=fs.readFileSync(encrypted);if(crypto.createHash('sha256').update(bytes).digest('hex')!==expectedHash)throw Error('Download verification failed. Download the package again.');
 if(bytes.subarray(0,8).toString()!=='OYYOPKG1')throw Error('Unsupported OYYO package.');
 const key=Buffer.from(secret,'hex');let plaintext;
 try{const cipher=crypto.createDecipheriv('aes-256-gcm',key,bytes.subarray(8,20));cipher.setAAD(Buffer.from('OYYO Windows demo package v1'));cipher.setAuthTag(bytes.subarray(20,36));plaintext=Buffer.concat([cipher.update(bytes.subarray(36)),cipher.final()]);}catch{throw Error('The demo key is invalid or this package is damaged. Nothing was installed.');}finally{key.fill(0);}
 fs.writeFileSync(output,plaintext,{flag:'wx'});plaintext.fill(0);console.log('Demo key accepted. Package authenticated.');
}catch(e){console.error(e.message);process.exitCode=1;}
