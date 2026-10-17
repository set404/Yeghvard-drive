// Tilts engine loops' tone: a low shelf (bass) and a high shelf, both in dB, run twice
// (forward then backward) so nothing shifts in time and the loop still wraps without a seam.
// The loop is run round once first so the filters start settled. Writes back in place at
// the same loudness as before.
// Usage: node eq.js bassDb bassHz trebleDb trebleHz file.wav [file.wav ...]
const fs=require('fs');const [,,bdb,bhz,tdb,thz,...files]=process.argv;const R=48000;
function shelf(kind,db,f0){const A=Math.pow(10,db/40),w=2*Math.PI*f0/R,c=Math.cos(w),s=Math.sin(w),al=s/2*Math.SQRT2,q=2*Math.sqrt(A)*al;
 let b0,b1,b2,a0,a1,a2;
 if(kind==='low'){b0=A*((A+1)-(A-1)*c+q);b1=2*A*((A-1)-(A+1)*c);b2=A*((A+1)-(A-1)*c-q);a0=(A+1)+(A-1)*c+q;a1=-2*((A-1)+(A+1)*c);a2=(A+1)+(A-1)*c-q;}
 else{b0=A*((A+1)+(A-1)*c+q);b1=-2*A*((A-1)+(A+1)*c);b2=A*((A+1)+(A-1)*c-q);a0=(A+1)-(A-1)*c+q;a1=2*((A-1)-(A+1)*c);a2=(A+1)-(A-1)*c-q;}
 return [b0/a0,b1/a0,b2/a0,a1/a0,a2/a0];}
function run(x,k,rev){const n=x.length,out=new Float32Array(n);let x1=0,x2=0,y1=0,y2=0;
 for(let pass=0;pass<2;pass++)for(let j=0;j<n;j++){const i=rev?n-1-j:j;const v=x[i];const y=k[0]*v+k[1]*x1+k[2]*x2-k[3]*y1-k[4]*y2;x2=x1;x1=v;y2=y1;y1=y;if(pass)out[i]=y;}
 return out;}
for(const f of files){const b=fs.readFileSync(f);const n=(b.length-44)/2;let x=new Float32Array(n);let e0=0;
 for(let i=0;i<n;i++){x[i]=b.readInt16LE(44+i*2)/32768;e0+=x[i]*x[i];}
 for(const k of [shelf('low',+bdb/2,+bhz),shelf('high',+tdb/2,+thz)]){x=run(x,k,false);x=run(x,k,true);}
 let e1=0,peak=0;for(const v of x){e1+=v*v;peak=Math.max(peak,Math.abs(v));}const g=Math.min(Math.sqrt(e0/e1),0.97/peak);
 for(let i=0;i<n;i++)b.writeInt16LE(Math.round(Math.max(-1,Math.min(1,x[i]*g))*32767),44+i*2);fs.writeFileSync(f,b);
 console.log(f.split('/').pop(),'gain',g.toFixed(2));}
