'use client';
import {useEffect,useLayoutEffect,useRef,useState} from 'react';
export function useDemoAudio(volume:number,bass:number,mid:number,treble:number,extra:boolean,clear:boolean){
 const mediaRef=useRef<HTMLAudioElement>(null),epoch=useRef(0);
 const engine=useRef<{ctx:AudioContext;gain:GainNode;eq:BiquadFilterNode[];source:MediaElementAudioSourceNode;analyser:AnalyserNode;samples:Float32Array<ArrayBuffer>}|null>(null);
 const values=useRef({volume,bass,mid,treble,extra,clear});useLayoutEffect(()=>{values.current={volume,bass,mid,treble,extra,clear}},[volume,bass,mid,treble,extra,clear]);const [error,setError]=useState(''),[autoplayBlocked,setAutoplayBlocked]=useState(false);
 function apply(){const e=engine.current;if(!e)return;const v=values.current,t=e.ctx.currentTime;e.gain.gain.setTargetAtTime(v.volume/100*.65,t,.03);[v.clear?(v.extra?4:1):v.bass,v.clear?0:v.mid,v.clear?1:v.treble].forEach((gain,i)=>e.eq[i].gain.setTargetAtTime(gain,t,.03))}
 useEffect(apply,[volume,bass,mid,treble,extra,clear]);
 function stop(){epoch.current++;mediaRef.current?.pause()}
 useEffect(()=>()=>{epoch.current++;if(engine.current){engine.current.source.disconnect();void engine.current.ctx.close();engine.current=null}},[]);
 async function play(automatic=false){const token=++epoch.current;try{
  setError('');if(!automatic)setAutoplayBlocked(false);const media=mediaRef.current;if(!media)return false;
  if(!engine.current){const ctx=new AudioContext(),gain=ctx.createGain(),eq=[ctx.createBiquadFilter(),ctx.createBiquadFilter(),ctx.createBiquadFilter()];eq[0].type='lowshelf';eq[0].frequency.value=180;eq[1].type='peaking';eq[1].frequency.value=1100;eq[1].Q.value=.7;eq[2].type='highshelf';eq[2].frequency.value=4200;const limit=ctx.createDynamicsCompressor();limit.threshold.value=-10;limit.ratio.value=12;const source=ctx.createMediaElementSource(media);source.connect(eq[0]);eq[0].connect(eq[1]);eq[1].connect(eq[2]);eq[2].connect(gain);gain.connect(limit);limit.connect(ctx.destination);
   const lowpass=ctx.createBiquadFilter(),analyser=ctx.createAnalyser();lowpass.type='lowpass';lowpass.frequency.value=180;analyser.fftSize=512;limit.connect(lowpass);lowpass.connect(analyser);engine.current={ctx,gain,eq,source,analyser,samples:new Float32Array(analyser.fftSize)}}
  const resumed=engine.current.ctx.resume();
  if(automatic){
   await Promise.race([resumed,new Promise<void>(resolve=>setTimeout(resolve,700))]);
   if(engine.current.ctx.state!=='running'){if(token===epoch.current)setAutoplayBlocked(true);return false}
  }else{await resumed}
if(token!==epoch.current)return false;apply();await media.play();if(token!==epoch.current){media.pause();return false}setAutoplayBlocked(false);return true;
 }catch{if(token===epoch.current){if(automatic)setAutoplayBlocked(true);else setError('Audio could not start. Press Play to try again.')}return false}}
 function bassLevel(){const e=engine.current;if(!e||mediaRef.current?.paused)return 0;e.analyser.getFloatTimeDomainData(e.samples);let energy=0;for(const sample of e.samples)energy+=sample*sample;return Math.min(1,Math.sqrt(energy/e.samples.length)*5)}
 return {mediaRef,play,stop,error,bassLevel,autoplayBlocked};
}
