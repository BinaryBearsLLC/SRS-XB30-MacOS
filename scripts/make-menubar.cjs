// The menu-bar artwork is the exact xb30.svg artwork, converted to an alpha mask.
const fs=require('fs');
const {Resvg}=require('./icon-tools/node_modules/@resvg/resvg-js');
const source=fs.readFileSync('assets/xb30.svg','utf8');
const box=source.match(/viewBox="([^"]+)"/)[1];
let inner=source.slice(source.indexOf('>',source.indexOf('<svg'))+1,source.lastIndexOf('</svg>'));
inner=inner.replaceAll('white','__PAPER__').replaceAll('#000','white').replaceAll('__PAPER__','black');
const svg=`<svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd" viewBox="${box}"><defs><mask id="artwork" maskUnits="userSpaceOnUse" x="100" y="325" width="1390" height="970"><g fill="none">${inner}</g></mask></defs><rect x="100" y="325" width="1390" height="970" fill="black" mask="url(#artwork)"/></svg>`;
fs.writeFileSync('assets/menubar-template.svg',svg);
fs.writeFileSync('assets/menubar-light.svg',svg);
fs.writeFileSync('assets/menubar-dark.svg',svg.replace('fill="black" mask=', 'fill="white" mask='));
fs.mkdirSync('build/icons',{recursive:true});
fs.writeFileSync('build/icons/MenuBarTemplate.png',new Resvg(svg,{fitTo:{mode:'width',value:312}}).render().asPng());

// Review both polarities on their intended backgrounds at 2x menu-bar size.
for(const [name,bg,fg] of [['light','white','black'],['dark','#202124','white']]) {
 const artwork=svg.replace('fill="black" mask=',`fill="${fg}" mask=`);
 const proof=`<svg xmlns="http://www.w3.org/2000/svg" width="208" height="64" viewBox="0 0 104 32"><rect width="104" height="32" fill="${bg}"/><svg x="39" y="7" width="26" height="18">${artwork}</svg></svg>`;
 fs.writeFileSync(`build/icons/menubar-${name}-review.png`,new Resvg(proof).render().asPng());
}
