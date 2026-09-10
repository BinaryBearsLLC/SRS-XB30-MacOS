// Preview choreography specified by Andrea, 10 September 2026.
// Colors/timing are a visual interpretation, not measured firmware waveforms.
export const presets = [
 {name:'Off',colors:['#657383'],strobe:false,description:'All illumination off.'},
 {name:'Rave',colors:['#aa26ff','#2455ff','#ff243a','#35ed65'],strobe:true,description:'Fast moving violet, blue, red and green. The music drives alternating white flashes.'},
 {name:'Chill',colors:['#ff384e','#c04b99','#933be5'],strobe:true,description:'One warm color at a time, with slow fades. Both white LEDs breathe together.'},
 {name:'No flash',colors:['#6ddfff','#56e7a1','#397dff','#f3ed98','#f5fcff'],strobe:false,description:'Quick color flashes on the strip. The two white LEDs stay off.'},
 {name:'Hot',colors:['#ff302c','#ff7733','#ffc25a'],strobe:true,description:'Changing warm reds, oranges and golds with blinking white LEDs.'},
 {name:'Cool',colors:['#245dff','#58dfff','#effaff'],strobe:true,description:'Changing cool blues, cyan and white with blinking white LEDs.'},
 {name:'Strobe',colors:['#f5faff','#fff0d8'],strobe:true,description:'The strip and both white LEDs strobe in neutral and warm white.'},
 {name:'Calm Magenta',colors:['#df59c7'],strobe:false,description:'Soft magenta breathing light. White LEDs off.'},
 {name:'Calm Cyan',colors:['#30d9e8'],strobe:false,description:'Soft cyan breathing light. White LEDs off.'},
 {name:'Calm Lime',colors:['#b3e755'],strobe:false,description:'Soft lime breathing light. White LEDs off.'},
 {name:'Calm Cinnabar',colors:['#e85439'],strobe:false,description:'Soft cinnabar breathing light. White LEDs off.'},
 {name:'Calm Daylight',colors:['#f1f6ff'],strobe:false,description:'Soft daylight breathing light. White LEDs off.'},
 {name:'Calm Light Bulb',colors:['#ffd39a'],strobe:false,description:'Soft warm white breathing light. White LEDs off.'},
] as const;
const wave=(t:number,period:number)=>.5-.5*Math.cos(t*Math.PI*2/period);
const pulse=(t:number,hz:number,width:number)=>((t*hz)%1)<width?1:0;
export function lightFrame(index:number,time:number,motion:boolean,brightness:number,stripEnabled:boolean,strobeEnabled:boolean,bass=0){
 const p=presets[index]??presets[0],t=Math.max(0,time),gain=Math.max(0,Math.min(1,brightness));
 let phase=0,intensity=1,left=0,right=0,spatial=false;
 if(motion){
  switch(index){
   case 1:{const beat=Math.max(0,Math.min(1,bass));phase=t*.72+beat*.28;spatial=true;intensity=.65+beat*1.3+pulse(t,5,.25)*.4;const hit=beat>.12?Math.min(1,beat*1.9):pulse(t,3.3,.14)*.55;const alternate=Math.floor(t*6)%2===0;left=alternate?hit:0;right=alternate?0:hit;break}
   case 2:phase=t/18;intensity=.65+.35*wave(t,6);left=right=wave(t,6)*.65;break;
   case 3:phase=Math.floor(t*3.4)/p.colors.length;intensity=.06+1.7*pulse(t,3.4,.48);break;
   case 4:case 5:phase=t/5;intensity=.8+.5*wave(t,1.8);left=pulse(t,2.6,.28);right=pulse(t+.19,2.6,.28);break;
   case 6:phase=Math.floor(t*4)/p.colors.length;intensity=.035+2*pulse(t,4,.2);left=right=pulse(t,4,.2);break;
   default:intensity=.3+.6*wave(t,5.5);break;
  }
 }
 if(index===0){intensity=left=right=0}
 return {palette:p.colors,phase,spatial,intensity:stripEnabled?intensity*gain:0,left:strobeEnabled?left*gain:0,right:strobeEnabled?right*gain:0};
}
