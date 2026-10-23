/* Presentation only: never reads or changes game state, bets or wallet data. */
(()=>{
 if(window.soveraEnglishUI)return;window.soveraEnglishUI=true;
 document.documentElement.lang='en';
 const labels={
  '\u09b8\u09ac\u099c\u09bf':'Vegetables','\u09ae\u09be\u0982\u09b8':'Meat','\u09b8\u09be\u09b2\u09be\u09a6':'Salad','\u09aa\u09bf\u099c\u09cd\u099c\u09be':'Pizza',
  '\u09ac\u09c7\u099f \u0995\u09b0\u09cb':'Place bets','\u09ab\u09b2\u09be\u09ab\u09b2':'Results','\u09b6\u09c7\u09b7 \u099c\u09df':'Last win','\u0986\u099c\u0995\u09c7\u09b0 \u0986\u09df':'Today’s winnings',
  '\u0986\u09ac\u09be\u09b0':'Repeat','\u0985\u099f\u09cb':'Auto','\u09b0\u09be\u0989\u09a8\u09cd\u09a1':'Round','\u0987\u09a4\u09bf\u09b9\u09be\u09b8':'History','\u09a8\u09bf\u09df\u09ae':'Rules'
 };
 const translate=value=>{
  const trimmed=value.trim();if(labels[trimmed])return value.replace(trimmed,labels[trimmed]);
  if(/^\s*[\u09e6-\u09ef\d,.]+\s*$/.test(value))return value.replace(/[\u09e6-\u09ef]/g,c=>String(c.charCodeAt(0)-0x09e6));
  const patterns=[[/^(\s*)\u09b0\u09be\u0989\u09a8\u09cd\u09a1\s*([\d\u09e6-\u09ef,]+)(\s*)$/,'$1Round $2$3'],[/^(\s*)([\d\u09e6-\u09ef,]+)\s*\u099c\u09a8 \u0996\u09c7\u09b2\u09c7\u099b\u09c7(\s*)$/,'$1$2 players$3']];
  for(const [pattern,replacement] of patterns)if(pattern.test(value))return value.replace(pattern,replacement).replace(/[\u09e6-\u09ef]/g,c=>String(c.charCodeAt(0)-0x09e6));
  return value;
 };
 let queued=false;
 function update(){queued=false;const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);let node;while((node=walker.nextNode())){if(node.parentElement?.closest('script,style,input,textarea,[contenteditable]'))continue;const next=translate(node.data);if(next!==node.data)node.data=next;}}
 const observer=new MutationObserver(()=>{if(!queued){queued=true;requestAnimationFrame(update);}});
 if(document.body){update();observer.observe(document.body,{childList:true,subtree:true,characterData:true});}
})();
