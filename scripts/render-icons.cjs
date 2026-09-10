// npm ci --prefix scripts/icon-tools
const {Resvg}=require('./icon-tools/node_modules/@resvg/resvg-js');
const fs=require('fs');
fs.mkdirSync('build/icons',{recursive:true});
for(const [input,output,width] of [['assets/xb30.svg','AppIcon.png',1024],['assets/menubar-template.svg','MenuBarTemplate.png',312]]) {
 fs.writeFileSync('build/icons/'+output,new Resvg(fs.readFileSync(input),{fitTo:{mode:'width',value:width}}).render().asPng());
}
