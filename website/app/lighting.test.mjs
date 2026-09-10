import assert from 'node:assert/strict';
import {lightFrame,presets} from './lighting.ts';
const frame=(i,t,bass=0)=>lightFrame(i,t,true,.7,true,true,bass);
for(let i=0;i<presets.length;i++){
 for(let t=0;t<8;t+=.031){const f=frame(i,t);assert.ok(Number.isFinite(f.intensity)&&f.intensity>=0);assert.ok(f.left>=0&&f.right>=0);if(i>=7||i===3||i===0)assert.equal(f.left+f.right,0);if(i===2)assert.equal(f.left,f.right)}
 const still=lightFrame(i,2,false,.7,true,true,1);assert.equal(still.left+still.right,0);
 assert.equal(lightFrame(i,2,true,.7,false,true).intensity,0);
 const noLED=lightFrame(i,2,true,.7,true,false);assert.equal(noLED.left+noLED.right,0);
}
assert.ok(frame(1,.2,.8).intensity>frame(1,.2,0).intensity,'Rave must react to actual bass');
assert.notEqual(frame(1,.2,.8).left,frame(1,.2,.8).right,'Rave alternates LEDs');
assert.equal(frame(2,2).spatial,false,'Chill must be uniform around the strip');
assert.notEqual(frame(2,0).intensity,frame(2,3).intensity,'Chill fades');
assert.ok(frame(3,0).intensity>frame(3,.2).intensity*10,'No flash pulses the color strip');
assert.ok(frame(6,0).left>0 && frame(6,.1).left===0,'Strobe has on and off phases');
for(let i=7;i<13;i++){assert.equal(presets[i].colors.length,1);assert.notEqual(frame(i,0).intensity,frame(i,2).intensity)}
console.log('13 lighting modes: palette, fading, strip/LED isolation, reduced motion and music response PASS');
