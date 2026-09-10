'use client';
import {useEffect,useRef} from 'react';
// The original supplied PNG stays untouched; CSS blends away its white canvas.
export default function BrandFlash(){
 const mark=useRef<HTMLDivElement>(null);
 useEffect(()=>{
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');let timer:ReturnType<typeof setTimeout>;
  let animation:Animation|undefined;
  const schedule=()=>{timer=setTimeout(()=>{if(!document.hidden&&!reduced.matches){animation=mark.current?.animate([{opacity:0,filter:'invert(1) brightness(1)'},{opacity:.065,offset:.14,filter:'invert(1) brightness(1.8)'},{opacity:.015,offset:.23},{opacity:.085,offset:.34,filter:'invert(1) brightness(2)'},{opacity:0}],{duration:1150,easing:'ease-out'})}schedule()},20000+Math.random()*30000)};
  schedule();return()=>{clearTimeout(timer);animation?.cancel()};
 },[]);
 return <div ref={mark} className="brand-flash" aria-hidden="true"/>;
}
