// Makes steady engine loops at given rpm from recordings whose revs are known over time.
// Each loop is built by overlap-adding short grains from where the recording is near that rpm
// (and steady in loudness), wandering through that stretch at random (mostly onwards, now and
// then jumping elsewhere in it), so that a long loop has no shorter pattern in it to be heard,
// each grain resampled to exactly that rpm and placed where it best lines up with what came
// before (WSOLA), wrapping round so the loop has no seam. Writes 16-bit mono 48 kHz .wav files.
// Usage: node layers.js spec.json outDir
const fs=require('fs');const [,,specF,outDir]=process.argv;const spec=JSON.parse(fs.readFileSync(specF));const R=48000;
const cache={};function load(f){if(!cache[f]){const b=fs.readFileSync(f);cache[f]=new Float32Array(b.buffer,b.byteOffset,b.length/4);}return cache[f];}
function rpmFn(src){ // rpm at time t: from a ridge json (hz * scale) or a straight line, or a constant
 if(src.ridge){const d=JSON.parse(fs.readFileSync(src.ridge));return t=>{let i=0;while(i<d.length-2&&d[i+1].t<t)i++;const a=d[i],b=d[i+1];const u=Math.max(0,Math.min(1,(t-a.t)/(b.t-a.t)));return (a.hz+(b.hz-a.hz)*u)*src.scale;};}
 if(src.line)return t=>src.line[1]+(src.line[3]-src.line[1])*(t-src.line[0])/(src.line[2]-src.line[0]);
 return ()=>src.rpm;}
function interp(x,p){const i=Math.floor(p);if(i<0||i+1>=x.length)return 0;const f=p-i;return x[i]*(1-f)+x[i+1]*f;}
function wav(path,data){let s=0;for(const v of data)s+=v*v;const rms=Math.sqrt(s/data.length);let peak=0;for(const v of data)peak=Math.max(peak,Math.abs(v));
 // Same loudness for every loop (car.gd sets the level), without clipping.
 const g=Math.min(0.2/rms,0.95/peak);const pcm=Buffer.alloc(data.length*2);for(let i=0;i<data.length;i++)pcm.writeInt16LE(Math.round(Math.max(-1,Math.min(1,data[i]*g))*32767),i*2);
 const h=Buffer.alloc(44);h.write('RIFF',0);h.writeUInt32LE(36+pcm.length,4);h.write('WAVE',8);h.write('fmt ',12);h.writeUInt32LE(16,16);h.writeUInt16LE(1,20);h.writeUInt16LE(1,22);h.writeUInt32LE(R,24);h.writeUInt32LE(R*2,28);h.writeUInt16LE(2,32);h.writeUInt16LE(16,34);h.write('data',36);h.writeUInt32LE(pcm.length,40);fs.writeFileSync(path,Buffer.concat([h,pcm]));return g;}
let seed=7;const rnd=()=>{seed=(seed*16807)%2147483647;return seed/2147483647;};
for(const L of spec.layers){
 const x=load(L.file);const rpm=rpmFn(L);const target=L.at;const tol=L.tol||0.05;
 // Where in the recording the revs are within tol of the target.
 const near=[];for(let t=L.from;t<=L.to;t+=0.005)if(Math.abs(rpm(t)/target-1)<=tol)near.push(t);
 // Only where it is about as loud as usual there, which leaves out a gear change or a cough.
 const level=t=>{const c=Math.round(t*R);let e=0;for(let i=-480;i<480;i++)e+=(x[c+i]||0)**2;return Math.sqrt(e/960);};
 const lv=near.map(level);const med=[...lv].sort((a,b)=>a-b)[lv.length>>1];
 const ok=near.filter((t,i)=>lv[i]>med*0.7&&lv[i]<med*1.4);
 if(ok.length<10){console.log('SKIP',L.name,'- revs never near',target);continue;}
 const len=Math.round((L.seconds||6)*R),G=Math.round((L.grain||0.08)*R),hop=G/2,seek=Math.round(0.012*R);
 const out=new Float32Array(len),win=new Float32Array(G);for(let i=0;i<G;i++)win[i]=0.5-0.5*Math.cos(2*Math.PI*i/G);
 const grains=Math.round(len/hop);let idx=0;const pace=hop/R/0.005;
 for(let g=0;g<grains;g++){
  // Wander through the near-target stretch: mostly on at the recording's own pace, a
  // little faster or slower, now and then somewhere else in it; turning back at its
  // ends rather than jumping from the end to the start.
  if(g>0){idx+=Math.round(pace*(0.5+rnd()));if(rnd()<0.06)idx=Math.floor(rnd()*ok.length);}
  const last=ok.length-1;while(idx<0||idx>last)idx=idx<0?-idx:2*last-idx;
  const st=ok[idx];
  const ratio=target/rpm(st);
  // Line it up with the tail already written: best match within +-12 ms.
  const dst=g*hop;let best=-1e9,bo=0;
  if(g>0)for(let o=-seek;o<=seek;o+=8){let c=0,a=0,b2=0;for(let i=0;i<hop;i+=4){const v=interp(x,st*R+o+(i-G/2)*ratio);const w=out[(dst+i)%len];c+=v*w;a+=v*v;b2+=w*w;}const r=c/Math.sqrt(a*b2+1e-12);if(r>best){best=r;bo=o;}}
  for(let i=0;i<G;i++){out[(dst+i)%len]+=interp(x,st*R+bo+(i-G/2)*ratio)*win[i];}
 }
 const gain=wav(outDir+'/'+L.name+'.wav',out);
 console.log(L.name.padEnd(28),'at',String(target).padStart(5),'rpm from',ok[0].toFixed(2)+'-'+ok[ok.length-1].toFixed(2),'s ('+ok.length*5+' ms near it), gain',gain.toFixed(1));
}
