// Makes engine loops at higher (or lower) revs from one recorded loop, the way an engine
// actually changes: it fires more often, but each firing still rings the exhaust at much
// the same pitch. Simply playing the recording faster raises that ring too, which sounds
// like a chipmunk; here the loop is cut into its firing pulses (two firings long, centred
// on each), and the pulses are laid down closer together. A share of the change (`rate`,
// 0..1) is still made by playing faster, because a real engine does get brighter as it revs.
// The pulses mostly follow their recorded order, so the cylinders keep their pattern, but now
// and then the sequence jumps elsewhere in the loop, and each pulse comes a touch early or late
// and a touch louder or softer, as a real engine's do: the loop (6 s) has no short pattern in it.
// Usage: node pulses.js spec.json outDir   (run from the folder the spec's paths are relative to)
const fs=require('fs');const [,,specF,outDir]=process.argv;const spec=JSON.parse(fs.readFileSync(specF));const R=48000;
function readWav(path){const b=fs.readFileSync(path);let p=12,fmt,d;while(p<b.length){const id=b.toString('ascii',p,p+4),sz=b.readUInt32LE(p+4);if(id==='fmt ')fmt={ch:b.readUInt16LE(p+10),rate:b.readUInt32LE(p+12),bits:b.readUInt16LE(p+22)};if(id==='data'){d=b.slice(p+8,p+8+sz);break;}p+=8+sz;}
 if(fmt.rate!==R||fmt.bits!==16)throw new Error(path+': need 48 kHz 16-bit');const n=d.length/2/fmt.ch;const x=new Float32Array(n);for(let i=0;i<n;i++){let s=0;for(let c=0;c<fmt.ch;c++)s+=d.readInt16LE((i*fmt.ch+c)*2)/32768;x[i]=s/fmt.ch;}return x;}
function writeWav(path,data){let s=0;for(const v of data)s+=v*v;const rms=Math.sqrt(s/data.length);let peak=0;for(const v of data)peak=Math.max(peak,Math.abs(v));
 const g=Math.min(0.2/rms,0.95/peak);const pcm=Buffer.alloc(data.length*2);for(let i=0;i<data.length;i++)pcm.writeInt16LE(Math.round(Math.max(-1,Math.min(1,data[i]*g))*32767),i*2);
 const h=Buffer.alloc(44);h.write('RIFF',0);h.writeUInt32LE(36+pcm.length,4);h.write('WAVE',8);h.write('fmt ',12);h.writeUInt32LE(16,16);h.writeUInt16LE(1,20);h.writeUInt16LE(1,22);h.writeUInt32LE(R,24);h.writeUInt32LE(R*2,28);h.writeUInt16LE(2,32);h.writeUInt16LE(16,34);h.write('data',36);h.writeUInt32LE(pcm.length,40);fs.writeFileSync(path,Buffer.concat([h,pcm]));}
let seed=11;const rnd=()=>{seed=(seed*16807)%2147483647;return seed/2147483647;};
const JIT=+(process.env.JIT??0),JUMP=+(process.env.JUMP??3),GAIN=+(process.env.GAIN??0.1);
const at=(x,p)=>{const n=x.length;p=((p%n)+n)%n;const i=Math.floor(p),f=p-i;return x[i]*(1-f)+x[(i+1)%n]*f;};
for(const job of spec.jobs){
 const x=readWav(job.source);const n=x.length;const p0=R*60/job.rpm/(job.cylinders/2);
 // The firing pulses: peaks of the low-passed loudness, one firing apart (give or take 20%).
 const env=new Float32Array(n);let y=0;const a=1-Math.exp(-2*Math.PI*400/R);for(let k=0;k<2;k++)for(let i=0;i<n;i++){y+=a*(x[i]-y);env[i]=Math.abs(y);}
 const sm=new Float32Array(n);const w=Math.round(p0*0.25);let acc=0;for(let i=0;i<n+w;i++){acc+=env[i%n];if(i>=w)acc-=env[(i-w)%n];if(i>=w)sm[(i-(w>>1))%n]=acc/w;}
 let m=0;for(let i=0;i<p0;i++)if(sm[i]>sm[m])m=i;const marks=[m];
 for(;;){const lo=Math.round(m+p0*0.8),hi=Math.round(m+p0*1.2);if(hi>=marks[0]+n-p0*0.5)break;let b=lo;for(let i=lo;i<=hi;i++)if(sm[i%n]>sm[b%n])b=i;marks.push(b);m=b;}
 const W=Math.round(p0);
 const like=nx=>{let best=nx,bc=-2;for(let t=0;t<16;t++){const c=(nx+job.cylinders*Math.floor(rnd()*marks.length/job.cylinders))%marks.length;if(Math.abs(c-nx)<2)continue;let ab=0,aa=0,bb=0;
   for(let i=-W;i<W;i+=2){const u=at(x,marks[nx]+i),v=at(x,marks[c]+i);ab+=u*v;aa+=u*u;bb+=v*v;}const cc=ab/Math.sqrt(aa*bb+1e-12);if(cc>bc){bc=cc;best=c;}}return best;};
 for(const target of job.targets){
  const k=target/job.rpm,r=Math.pow(k,job.rate);
  // Each gap between pulses as recorded, shortened in proportion to the revs, so an
  // uneven (lumpy) engine stays uneven. One pass through all of them is the whole
  // recorded loop at the new revs; enough passes for about 1.2 s, so it ends where it began.
  const gaps=marks.map((c,i)=>(i+1<marks.length?marks[i+1]:marks[0]+n)-c);
  const M=marks.length;const len=Math.round((job.seconds||6)*R);
  // The sequence of pulses: on to the next, now and then a jump; each gap a little uneven.
  const seq=[],step=[];let j=0,total=0;
  while(total<len){seq.push(j);const gp=gaps[j]/k*(1+(rnd()-0.5)*2*JIT);step.push(gp);total+=gp;
   const nx=(j+1)%M;j=rnd()<JUMP*gp/R?like(nx):nx;}
  // Squeezed a hair so it comes out exactly the loop's length and wraps round without a seam.
  const fit=len/total;
  const out=new Float32Array(len),wsum=new Float32Array(len);const half=p0/r;const G=Math.ceil(2*half);
  let dst=0;
  for(let q=0;q<seq.length;q++){const c=marks[seq[q]];const gain=1+(rnd()-0.5)*GAIN;
   for(let i=0;i<G;i++){const u=(i-half)/half;if(u<=-1||u>=1)continue;const wv=0.5+0.5*Math.cos(Math.PI*u);
    const o=Math.round(dst+i-half);const idx=((o%len)+len)%len;out[idx]+=at(x,c+(i-half)*r)*wv*gain;wsum[idx]+=wv;}
   dst+=step[q]*fit;}
  for(let i=0;i<len;i++)out[i]/=Math.max(wsum[i],0.3);
  const name=job.prefix+'_'+String(target).padStart(4,'0');writeWav(outDir+'/'+name+'.wav',out);
  console.log(name.padEnd(22),'from',job.source.split('/').pop(),'at',job.rpm,'rpm:',k.toFixed(2)+'x revs =',(k/r).toFixed(2)+'x more pulses,',r.toFixed(2)+'x faster;',marks.length,'pulses in the source');
 }
}
