'use client';
/* oxlint-disable next/no-img-element -- The exact supplied menubar SVG is used without image transformation. */
/* oxlint-disable jsx-a11y/media-has-caption -- Music demo without dialogue; track titles and creator credits are available beside the player. */
import Link from 'next/link';
import {useEffect,useRef,useState} from 'react';
import {Pause,Play,Rotate3D,Download,Code2} from 'lucide-react';
import {Slider} from '@/components/ui/slider';
import {Switch} from '@/components/ui/switch';
import Speaker from './Speaker';
import WebController,{type DemoControls} from './WebController';
import {useDemoAudio} from './useDemoAudio';
import {tracks} from './tracks';
import AudioCredits from './AudioCredits';
import BrandFlash from './BrandFlash';
export default function Page(){
 const [state,setState]=useState<DemoControls>({volume:50,bass:0,mid:0,treble:0,extra:false,light:1,lightOn:true,connected:true,autoStandby:true,btStandby:false,codec:'Auto'});
 const [playing,setPlaying]=useState(false),[motion,setMotion]=useState(true),[brightness,setBrightness]=useState(.7),[strip,setStrip]=useState(true),[strobes,setStrobes]=useState(true),[track,setTrack]=useState(1);
 const {mediaRef,play,stop,error,bassLevel,autoplayBlocked}=useDemoAudio(state.volume,state.bass,state.mid,state.treble,state.extra,state.extra);
 function set<K extends keyof DemoControls>(key:K,value:DemoControls[K]){setState(current=>({...current,[key]:value}))}
 const starter=useRef(play);
 useEffect(()=>{void starter.current(true)},[]);
 function toggleAudio(){if(playing)stop();else void play()}
 return <main><BrandFlash/><nav><Link href="/" className="brand"><img src="/favicon.svg" alt=""/>XB30 Controller</Link><div className="nav-actions"><a className="github-button" href="https://github.com/BinaryBearsLLC/SRS-XB30-MacOS" target="_blank" rel="noreferrer"><Code2 size={17}/><span>GitHub</span></a><a className="download-button" href="https://github.com/BinaryBearsLLC/SRS-XB30-MacOS/releases/latest/download/XB30-Controller.dmg"><Download size={17}/>Download for Mac</a></div></nav>
 <h1>Your speaker. <em>One touch closer.</em></h1><div className="experience"><section className="product"><Speaker bassLevel={bassLevel} state={{light:state.lightOn?state.light:0,volume:state.volume,bass:state.bass,playing,motion,brightness,strip,strobes}}/><div className="stage-footer"><span><Rotate3D size={17}/>Drag to explore</span><button className={autoplayBlocked&&!playing?"play-attention":""} onClick={toggleAudio}>{playing?<Pause size={14}/>:<Play size={14}/>} {playing?'Pause audio':'Play audio'}</button></div><div className="track-selector"><select aria-label="Demo track" value={track} onChange={e=>{stop();setPlaying(false);setTrack(Number(e.target.value))}}>{tracks.map((t,i)=><option key={t.src} value={i}>{t.title}</option>)}</select><AudioCredits track={track}/></div><audio ref={mediaRef} src={tracks[track].src} preload="none" loop onPlay={()=>setPlaying(true)} onPause={()=>setPlaying(false)} onError={()=>setPlaying(false)}/>{error&&<output className="audio-error">{error}</output>}
 <details className="preview-options"><summary>3D preview options</summary><div className="preview-light-controls"><div className="row"><span>Animation</span><Switch aria-label="Animation" checked={motion} onCheckedChange={setMotion}/></div><div className="row"><span>LED strip</span><Switch aria-label="LED strip" checked={strip} onCheckedChange={setStrip}/></div><div className="row"><span>White LEDs</span><Switch aria-label="White LEDs" checked={strobes} onCheckedChange={setStrobes}/></div><div className="brightness">Brightness <Slider aria-label="LED brightness" value={[brightness]} min={0} max={1} step={.01} onValueChange={v=>setBrightness(Array.isArray(v)?v[0]:v)}/></div></div></details></section>
 <section className="controls-area"><div className="menubar"><span/><span/><span/><img src="/favicon.svg" alt="Menu bar icon"/></div><WebController state={state} set={set}/></section></div>
 <footer className="bottom"><span>Made with care by <a href="https://binarybears.com" target="_blank" rel="noreferrer">BinaryBears ↗</a></span><span>Independent software. Not affiliated with Sony.</span></footer></main>
}
