// Follows one harmonic line of an engine through a recording, from a starting time and frequency,
// forwards and backwards. Prints the line's frequency over time; the revs scale with it.
// Usage: node ridge.js in.f32 out.json startTime startHz [from to]
const fs=require('fs');const [,,inF,outJ,t0A,f0A,fromA,toA]=process.argv;
const buf=fs.readFileSync(inF);const x=new Float32Array(buf.buffer,buf.byteOffset,buf.length/4);const R=48000;
function fft(re,im){const n=re.length;for(let i=1,j=0;i<n;i++){let bit=n>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j){[re[i],re[j]]=[re[j],re[i]];[im[i],im[j]]=[im[j],im[i]];}}
 for(let len=2;len<=n;len<<=1){const a=-2*Math.PI/len,wr=Math.cos(a),wi=Math.sin(a);for(let i=0;i<n;i+=len){let cr=1,ci=0;for(let k=0;k<len/2;k++){const ur=re[i+k],ui=im[i+k],vr=re[i+k+len/2]*cr-im[i+k+len/2]*ci,vi=re[i+k+len/2]*ci+im[i+k+len/2]*cr;re[i+k]=ur+vr;im[i+k]=ui+vi;re[i+k+len/2]=ur-vr;im[i+k+len/2]=ui-vi;const t=cr*wr-ci*wi;ci=cr*wi+ci*wr;cr=t;}}}}
const N=6144,P=32768,hop=Math.round(0.02*R),binHz=R/P,maxBin=Math.round(1500/binHz);const win=new Float32Array(N);for(let i=0;i<N;i++)win[i]=0.5-0.5*Math.cos(2*Math.PI*i/(N-1));
const from=Number(fromA||0),to=Number(toA||x.length/R);const spec=[],times=[];
for(let o=Math.round(from*R);o+N<x.length&&o/R<to;o+=hop){const re=new Float64Array(P),im=new Float64Array(P);for(let i=0;i<N;i++)re[i]=x[o+i]*win[i];fft(re,im);const m=new Float32Array(maxBin);for(let k=0;k<maxBin;k++)m[k]=re[k]*re[k]+im[k]*im[k];spec.push(m);times.push((o+N/2)/R);}
// Peak near a frequency (parabolic refine).
function peak(m,f,tol){const lo=Math.max(1,Math.floor(f*(1-tol)/binHz)),hi=Math.min(maxBin-2,Math.ceil(f*(1+tol)/binHz));let k=lo;for(let j=lo;j<=hi;j++)if(m[j]>m[k])k=j;const a=Math.log(m[k-1]+1e-12),b=Math.log(m[k]+1e-12),c=Math.log(m[k+1]+1e-12);const d=0.5*(a-c)/(a-2*b+c||1);return (k+d)*binHz;}
let i0=0;while(i0<times.length-1&&times[i0]<Number(t0A))i0++;const fr=new Array(times.length);fr[i0]=peak(spec[i0],Number(f0A),0.08);
for(const dir of [1,-1]){let v=0;for(let i=i0+dir;i>=0&&i<times.length;i+=dir){const prev=fr[i-dir];const pred=prev*(1+v);const f=peak(spec[i],pred,0.025);v=0.7*v+0.3*(f/prev-1);fr[i]=f;}}
fs.writeFileSync(outJ,JSON.stringify(times.map((t,i)=>({t:+t.toFixed(3),hz:+fr[i].toFixed(2)}))));
for(let i=0;i<times.length;i+=Math.max(1,Math.round(times.length/40)))console.log(times[i].toFixed(2).padStart(6),'s',fr[i].toFixed(1).padStart(7),'Hz  x',(fr[i]/fr[i0]).toFixed(2));
