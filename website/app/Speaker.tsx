'use client';
/* oxlint-disable jsx-a11y/prefer-tag-over-role -- This labeled host contains an interactive WebGL canvas, not a static image. */
import {useEffect,useLayoutEffect,useRef,useState} from 'react';
import * as T from 'three';
import {OrbitControls} from 'three/examples/jsm/controls/OrbitControls.js';
import {GLTFLoader} from 'three/examples/jsm/loaders/GLTFLoader.js';
import {EffectComposer} from 'three/examples/jsm/postprocessing/EffectComposer.js';
import {RenderPass} from 'three/examples/jsm/postprocessing/RenderPass.js';
import {UnrealBloomPass} from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import {OutputPass} from 'three/examples/jsm/postprocessing/OutputPass.js';
import {lightFrame} from './lighting';
export type SpeakerState={light:number;volume:number;bass:number;playing:boolean;motion:boolean;brightness:number;strip:boolean;strobes:boolean};
export default function Speaker({state,bassLevel}:{state:SpeakerState;bassLevel:()=>number}){
 const host=useRef<HTMLDivElement>(null),live=useRef(state);
 const audioLevel=useRef(bassLevel);
 useLayoutEffect(()=>{live.current=state;audioLevel.current=bassLevel},[state,bassLevel]);
 const [load,setLoad]=useState<'loading'|'ready'|'error'>('loading');
 useEffect(()=>{
  const el=host.current!;let renderer:T.WebGLRenderer;let alive=true;
  try{renderer=new T.WebGLRenderer({antialias:true,alpha:true})}catch{queueMicrotask(()=>{if(alive)setLoad('error')});return()=>{alive=false}}
  renderer.setPixelRatio(Math.min(devicePixelRatio,1.75));renderer.toneMapping=T.ACESFilmicToneMapping;renderer.toneMappingExposure=1.1;el.appendChild(renderer.domElement);
  const scene=new T.Scene(),camera=new T.PerspectiveCamera(32,1,.01,30);camera.position.set(1.9,1.25,4.5);
  const controls=new OrbitControls(camera,renderer.domElement);controls.enablePan=false;controls.enableDamping=true;controls.minDistance=2.5;controls.maxDistance=6;controls.maxPolarAngle=Math.PI*.72;
  scene.add(new T.HemisphereLight(0xd7e3f2,0x172134,1.6));const key=new T.DirectionalLight(0xe5f6ff,2);key.position.set(-2,4,4);scene.add(key);const rim=new T.DirectionalLight(0x9b87ff,.8);rim.position.set(3,1,-2);scene.add(rim);
  const target=new T.WebGLRenderTarget(1,1,{type:T.HalfFloatType,samples:4});
  const composer=new EffectComposer(renderer,target);composer.addPass(new RenderPass(scene,camera));const bloom=new UnrealBloomPass(new T.Vector2(1,1),.42,.5,.3);composer.addPass(bloom);composer.addPass(new OutputPass());
  const root=new T.Group();scene.add(root);let frame=0;const strips:T.Mesh[]=[];const strobes:T.Mesh[]=[];const diaphragms:{mesh:T.Mesh;rest:number}[]=[];
  const color=new T.Color();
  const paletteColors=new Map<string,T.Color>();
  const paletteColor=(hex:string)=>{let c=paletteColors.get(hex);if(!c){c=new T.Color(hex);paletteColors.set(hex,c)}return c};
  const angles=new WeakMap<T.Mesh,Float32Array>();
  const dispose=(o:T.Object3D)=>{const m=o as T.Mesh;m.geometry?.dispose();if(m.material)for(const mat of Array.isArray(m.material)?m.material:[m.material]){for(const v of Object.values(mat))if(v instanceof T.Texture)v.dispose();mat.dispose()}};
  const loader=new GLTFLoader();
  const accept=(g:import('three/examples/jsm/loaders/GLTFLoader.js').GLTF)=>{
   if(!alive){g.scene.traverse(dispose);return}
   g.scene.traverse(o=>{const m=o as T.Mesh;if(!m.isMesh)return;
    if(m.name.startsWith('XB30_Neon_Strip')){const old=m.material as T.Material;old.dispose();m.material=new T.MeshBasicMaterial({vertexColors:true});m.geometry.setAttribute('color',new T.BufferAttribute(new Float32Array(m.geometry.attributes.position.count*3),3));angles.set(m,Float32Array.from({length:m.geometry.attributes.position.count},(_,i)=>Math.atan2(m.geometry.attributes.position.getY(i)/.31,m.geometry.attributes.position.getX(i)/1.035)/Math.PI/2));strips.push(m)}
    if(m.name.startsWith('XB30_Strobe_')){(m.material as T.Material).dispose();m.material=new T.MeshBasicMaterial({color:0x2b4357});strobes.push(m)}
    if(m.name.startsWith('XB30_Driver_Cone_')||m.name==='XB30_Passive_Membrane')diaphragms.push({mesh:m,rest:m.position.z});
   });root.add(g.scene);setLoad('ready');
  };
  const failed=()=>{if(alive)setLoad('error')};
  const plain=()=>{if(alive)loader.load('./models/xb30-v2-refined.glb',accept,undefined,failed)};
  // Exact original geometry, compressed only for transport (77% fewer bytes).
  const abort=new AbortController();
  if(typeof DecompressionStream==='undefined')plain();
  else void fetch('./models/xb30-v2-refined.glb.gz',{signal:abort.signal}).then(async response=>{
   if(!response.ok||!response.body)throw Error('Model download failed');
   // Some static hosts set Content-Encoding, so fetch has already decompressed.
   const buffer=response.headers.get('content-encoding')?.includes('gzip')
    ? await response.arrayBuffer()
    : await new Response(response.body.pipeThrough(new DecompressionStream('gzip'))).arrayBuffer();
   if(alive)loader.parse(buffer,'./models/',accept,failed);
  }).catch(()=>{if(alive)plain()});
  const resize=()=>{const {width,height}=el.getBoundingClientRect();if(!width||!height)return;renderer.setSize(width,height);composer.setSize(width,height);camera.aspect=width/height;camera.updateProjectionMatrix()};const ro=new ResizeObserver(resize);ro.observe(el);resize();let visible=true;const visibility=new IntersectionObserver(([entry])=>{visible=entry.isIntersecting});visibility.observe(el);const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  function draw(ms:number){if(!alive)return;if(!visible||document.hidden){frame=requestAnimationFrame(draw);return;}const s=live.current,animate=s.motion&&!reduced.matches,energy=s.playing?audioLevel.current():0,f=lightFrame(s.light,ms/1000,animate,s.brightness,s.strip,s.strobes,energy);
   for(const m of strips){const pos=m.geometry.attributes.position,colors=m.geometry.attributes.color;
    for(let i=0;i<pos.count;i++){const phase=(((f.spatial?angles.get(m)![i]:0)+1+f.phase)%1)*f.palette.length;const j=Math.floor(phase);color.copy(paletteColor(f.palette[j%f.palette.length])).lerp(paletteColor(f.palette[(j+1)%f.palette.length]),phase-j).multiplyScalar(f.intensity);if(!f.intensity)color.setRGB(.05,.07,.08);colors.setXYZ(i,color.r,color.g,color.b)}colors.needsUpdate=true;
   }
   strobes.forEach((m,i)=>{const flash=i===0?f.left:f.right;(m.material as T.MeshBasicMaterial).color.setRGB(.035+flash*5,.055+flash*5,.07+flash*5)});
   // A small visual excursion follows the actual low-frequency audio envelope.
   // The shell remains still; reduced motion and pause put every diaphragm at rest.
   const excursion=animate&&s.playing?Math.sin(ms*.085)*.004*energy:0;
   diaphragms.forEach(({mesh,rest})=>{mesh.position.z=rest+excursion});
   controls.update();composer.render();frame=requestAnimationFrame(draw);
  }frame=requestAnimationFrame(draw);
  return()=>{alive=false;abort.abort();cancelAnimationFrame(frame);ro.disconnect();visibility.disconnect();controls.dispose();scene.traverse(dispose);composer.dispose();renderer.dispose();renderer.domElement.remove()};
 },[]);
 return <div className="speaker-stage"><div className="stage-halo"/><div ref={host} className="webgl" role="img" aria-label="BinaryBears XB30 3D speaker. Drag to rotate and scroll to zoom."/>{load==='error'&&<img className="speaker-fallback" src="./speaker-refined.webp" alt="Refined blue XB30 with BinaryBears wordmark"/>}<span className="model-note">{load==='loading'?'Loading your speaker…':load==='error'?'3D unavailable · studio preview':''}</span></div>
}
