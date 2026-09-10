'use client';
/* oxlint-disable jsx-a11y/no-static-element-interactions -- This wrapper delegates hover, blur and Escape across its native button and credit links; it is not itself a focus target. */
import {useState} from 'react';
import {tracks} from './tracks';
export default function AudioCredits({track}:{track:number}){
 const [open,setOpen]=useState(false),t=tracks[track];
 return <div className="audio-info" onMouseEnter={()=>setOpen(true)} onMouseLeave={e=>{if(!e.currentTarget.contains(document.activeElement))setOpen(false)}} onBlur={e=>{if(!e.currentTarget.contains(e.relatedTarget))setOpen(false)}} onKeyDown={e=>{if(e.key==='Escape'){setOpen(false);(e.target as HTMLElement).blur()}}}>
 <button type="button" aria-label="Track credits" aria-expanded={open} aria-controls="track-credits" onFocus={()=>setOpen(true)} onClick={()=>setOpen(true)}>?</button>
 {open&&<div id="track-credits" className="audio-credits"><strong>{t.fullTitle}</strong><span>By <a href={t.url} target="_blank" rel="noreferrer">{t.artist} · Freesound</a></span><a href={t.licenseUrl} target="_blank" rel="noreferrer">{t.license}</a>{track===1&&<span>Vocal sample: <a href="https://freesound.org/people/Timbre/sounds/119064/" target="_blank" rel="noreferrer">Timbre · Freesound</a>. Non-commercial use only.</span>}<small>Converted to MP3, 192 kbps. Original arrangement unchanged.</small></div>}
 </div>
}
