#if os(macOS) && !ASTRA_WEBSITE_APP_HELPER
import Foundation

/// DOM scripts execute in WKContentWorld.defaultClient; no globals or credentials are exposed to websites.
enum BrowserAgentPageScripts {
    private static let runtime = #"""

const clean = value => String(value || '').replace(/\s+/g, ' ').trim().slice(0, 500);
const error = (code, message) => { throw new Error(code + ': ' + message); };
const privateElement = n => n?.nodeType===1 && n.matches('input[type=hidden],input[type=password]');
const safeURL = value => {try{const u=new URL(value,location.href);u.username='';u.password='';return u.href;}catch{return '';}};
const safeText = n => {
 const pending=[n];let result='',visited=0;
 while(pending.length&&visited++<2000&&result.length<10000){const current=pending.pop();if(current.nodeType===3){result+=' '+current.textContent.slice(0,10000-result.length);continue;}if(current.nodeType!==1||privateElement(current)||current.matches('input,textarea,script,style'))continue;const children=current.childNodes;for(let i=Math.min(children.length,2000)-1;i>=0&&pending.length<2000;i--)pending.push(children[i]);}
 return clean(result);
};
const roleOf = n => n.getAttribute('role') || ({A:n.hasAttribute('href')?'link':'generic',BUTTON:'button',TEXTAREA:'textbox',SELECT:n.multiple?'listbox':'combobox',OPTION:'option',IMG:'img',H1:'heading',H2:'heading',H3:'heading',H4:'heading',H5:'heading',H6:'heading',NAV:'navigation',MAIN:'main',ASIDE:'complementary',UL:'list',OL:'list',LI:'listitem',TABLE:'table',TR:'row',TD:'cell',TH:'columnheader',FORM:'form',DIALOG:'dialog',PROGRESS:'progressbar',SUMMARY:'button'})[n.tagName] || (n.tagName==='INPUT'?({checkbox:'checkbox',radio:'radio',range:'slider',number:'spinbutton',button:'button',submit:'button',reset:'button'})[n.type] || 'textbox':n.isContentEditable?'textbox':'generic');
const referencedText = (n, attr) => clean((n.getAttribute(attr)||'').split(/\s+/).map(id => {const target=n.getRootNode().getElementById?.(id)||n.ownerDocument.getElementById(id);return target&&!privateElement(target)?safeText(target):'';}).join(' '));
const nameOf = (n, depth=0) => {
 if(depth>5) return '';
 if(privateElement(n)) return '';
 return referencedText(n,'aria-labelledby') || clean(n.getAttribute('aria-label')) || clean(Array.from(n.labels||[]).filter(l=>!privateElement(l)).map(safeText).join(' ')) || clean(n.getAttribute('alt')) || (n.matches('input[type=button],input[type=submit],input[type=reset]')?clean(n.value):'') || (n.matches('button,a,summary,option,[role],h1,h2,h3,h4,h5,h6')?safeText(n):'') || clean(n.getAttribute('title')) || clean(n.getAttribute('placeholder'));
};
const visible = n => {
 if(!n.isConnected || !n.getClientRects().length) return false;
 for(let p=n;p;p=p.parentElement||p.getRootNode()?.host) {
  if(p.hidden || p.matches('[inert],[aria-hidden="true"]')) return false;
  const style=p.ownerDocument.defaultView.getComputedStyle(p);
  if(style.display==='none'||style.visibility==='hidden'||style.visibility==='collapse'||Number(style.opacity)===0) return false;
 }
 return true;
};
const geometry = n => { const r=n.getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height,coordinateSpace:'frame-viewport'}; };
const disabled = n => !!n.disabled || n.matches(':disabled') || n.getAttribute('aria-disabled')==='true';
const semantic = n => roleOf(n)!=='generic' || n.isContentEditable || n.hasAttribute('tabindex');
const walk = (root, visit, frame='main', parent=null, budget={count:0,max:20000}, frames=[]) => {
 for(const n of root.children || []) {
  if(++budget.count>budget.max) return false;
  const next=visit(n,frame,parent)?n:parent;
  if(n.shadowRoot && !walk(n.shadowRoot,visit,frame,next,budget,frames)) return false;
  if(n.tagName==='IFRAME' || n.tagName==='FRAME') {
   const id=frame+'/frame-'+frames.length;
   try { if(!n.contentDocument) throw Error('origin boundary'); frames.push({id,url:safeURL(n.contentDocument.URL),status:'accessible'}); if(!walk(n.contentDocument,visit,id,next,budget,frames)) return false; }
   catch { frames.push({id,url:safeURL(n.src||''),status:'inaccessible',reason:'Cross-origin or unavailable frame; public frame-specific WebKit execution is required.'}); }
  }
  if(!walk(n,visit,frame,next,budget,frames)) return false;
 }
 return true;
};
const resolve = (state, ref) => {
 if(!state || state.snapshotID!==snapshotID) error('stale_snapshot','Take a new snapshot.');
 const record=state.nodes.get(ref); const n=record?.node.deref();
 if(!n || !n.isConnected || n.ownerDocument!==record.document || n.getRootNode()!==record.root) error('stale_reference','Element was removed, replaced, or moved; take a new snapshot.');
 let doc=n.ownerDocument;
 while(doc!==document) { const host=doc.defaultView?.frameElement; if(!host || !host.isConnected || host.contentDocument!==doc) error('stale_document','Frame navigated; take a new snapshot.'); doc=host.ownerDocument; }
 return n;
};
const describe = (n, ref, frame, parent, detailed=false) => {
 const result={ref,role:roleOf(n),name:nameOf(n),description:referencedText(n,'aria-describedby')||clean(n.getAttribute('aria-description')),type:n.tagName.toLowerCase(),frame,parent,visible:visible(n),disabled:disabled(n),editable:!n.readOnly&&(n.isContentEditable||n.matches('input,textarea')),readOnly:!!n.readOnly,required:!!n.required||n.getAttribute('aria-required')==='true'};
 for(const key of ['checked','selected','expanded','pressed','busy','invalid','level','valuemin','valuemax','valuenow','valuetext']) { const v=n.getAttribute('aria-'+key); if(v!==null) result[key]=v==='true'?true:v==='false'?false:v; }
 if(n.matches('input[type=checkbox],input[type=radio]')) result.checked=n.indeterminate?'mixed':n.checked;
 if(n.tagName==='OPTION') result.selected=n.selected;
 if(n.tagName==='INPUT') result.inputType=n.type;
 if(n.tagName==='A') result.href=safeURL(n.href);
 if(n.tagName==='SELECT') result.options=Array.from(n.options).slice(0,200).map(o=>({label:clean(o.label),value:o.value,selected:o.selected,disabled:o.disabled}));
 if(detailed) {result.geometry=geometry(n); result.text=n.matches('input,textarea')?'':safeText(n); result.scrollable={horizontal:n.scrollWidth>n.clientWidth,vertical:n.scrollHeight>n.clientHeight};}
 return result;
};

"""#
    static let snapshot = runtime + #"""

const config=typeof options==='object'&&options?options:{};
const start=performance.now(), offset=Math.max(0,Number(config.offset)||0), limit=Math.min(1000,Math.max(1,Number(config.limit)||300));
const prior=globalThis.__astraBrowserUse;
const continuing=offset>0&&prior?.snapshotID===snapshotID&&prior.document===document;
if(!continuing&&prior?.waits) for(const cancel of prior.waits.values()) cancel('snapshot_replaced');
const state=continuing?prior:{snapshotID,nodes:new Map(),reverse:new WeakMap(),waits:new Map(),visible,document};
const controls=[],frames=[{id:'main',url:safeURL(location.href),status:'accessible'}]; let total=0;
const budget={count:0,max:20000};
const complete=walk(document,(n,frame,parent)=>{
 if(privateElement(n)||!semantic(n)||(!config.includeHidden&&!visible(n))) return false;
 const index=total++;
 const ref=state.reverse.get(n)||snapshotID+':'+frame+':'+index;
 const priorNode=state.nodes.get(ref)?.node.deref();if(priorNode&&priorNode!==n)error('snapshot_changed','Document order changed during pagination; start a new snapshot.');
 state.nodes.set(ref,{node:new WeakRef(n),document:n.ownerDocument,root:n.getRootNode(),frame});state.reverse.set(n,ref);
 if(index<offset||controls.length>=limit)return true;
 controls.push(describe(n,ref,frame,state.reverse.get(parent)||null,config.mode==='detailed')); return true;
},'main',null,budget,frames);
globalThis.__astraBrowserUse=state;
return {title:document.title,url:safeURL(location.href),snapshotID,controls,frames,truncated:!complete||total>offset+controls.length,pagination:{offset,limit,total:complete?total:null,nextOffset:total>offset+controls.length?offset+controls.length:null,visited:budget.count,traversalLimit:budget.max},durationMs:performance.now()-start,frameSupport:'same-origin frames and open shadow roots; inaccessible frames explicitly reported',nameAlgorithm:'DOM accessibility approximation; not the platform accessibility tree'};

"""#
    static let action = runtime + #"""

const config=typeof options==='object'&&options?options:{};
const state=globalThis.__astraBrowserUse;
const synthetic={ok:true,inputSource:'synthetic',trusted:false};
if(operation==='get_selected_text') return {text:String(getSelection()||'').slice(0,10000)};
if(operation==='scroll' && !ref) { window.scrollBy({left:Number(config.dx)||0,top:Number(dy)||0,behavior:'instant'}); return {...synthetic,x:scrollX,y:scrollY}; }
if(operation==='find_elements') {
 if(!state||state.snapshotID!==snapshotID) error('stale_snapshot','Take a snapshot first.');
 if(!config.selector&&!config.role&&!config.name&&!config.text) error('invalid_arguments','A selector, role, name, or text filter is required.');
 const matches=[]; const frames=[];let total=0;
 walk(document,(n,frame)=>{
  let match=true;
  try {if(config.selector) match=n.matches(config.selector);} catch {error('invalid_selector','CSS selector is invalid.');}
  if(config.role) match=match&&roleOf(n)===config.role;
  if(config.name) match=match&&nameOf(n)===config.name;
  if(config.text) match=match&&safeText(n).includes(config.text);
  if(privateElement(n)) match=false;
  if(!config.includeHidden) match=match&&visible(n);
  if(!match) return false;
  total++; if(matches.length>=Math.min(1000,config.limit||100)) return false;
  let r=state.reverse.get(n); if(!r){r=snapshotID+':'+frame+':find-'+state.nodes.size;state.nodes.set(r,{node:new WeakRef(n),document:n.ownerDocument,root:n.getRootNode(),frame});state.reverse.set(n,r);}
  matches.push(describe(n,r,frame,null)); return true;
 },'main',null,{count:0,max:20000},frames);
 return {elements:matches,total,truncated:total>matches.length,frames};
}
let node;
if(ref) node=resolve(state,ref);
else if(config.selector||config.role||config.name) {const found=[];walk(document,n=>{let match=true;try{if(config.selector)match=n.matches(config.selector);}catch{error('invalid_selector','CSS selector is invalid.');}if(config.role)match=match&&roleOf(n)===config.role;if(config.name)match=match&&nameOf(n)===config.name;if(match&&!privateElement(n)&&visible(n))found.push(n);return false;});if(found.length!==1) error(found.length?'ambiguous_selector':'element_not_found','Expected exactly one matching element.');node=found[0];}
else if(Number.isFinite(config.x)&&Number.isFinite(config.y)) node=document.elementFromPoint(config.x,config.y);
else if(['press_key','key_down','key_up','type_text','blur_element'].includes(operation)) node=document.activeElement;
if(!node) error('element_not_found','Provide a current ref, unique selector, or coordinates.');
if(privateElement(node)) error('private_element','Hidden inputs are unavailable.');
if(operation==='inspect_element') return describe(node,ref||null,state?.nodes.get(ref)?.frame||'main',null,true);
if(operation==='get_element_geometry') return geometry(node);
if(operation==='get_element_text') return {text:node.matches('input,textarea')?'':safeText(node)};
if(operation==='get_element_state') return describe(node,ref||null,state?.nodes.get(ref)?.frame||'main',null);
if(operation==='get_element_attributes') {const attrs={};for(const a of node.attributes) if(!['value','srcdoc','nonce'].includes(a.name)&&!a.name.startsWith('on')) attrs[a.name]=(['href','src','action','formaction'].includes(a.name)?safeURL(a.value):a.value).slice(0,1000);return {attributes:attrs};}
if(operation==='get_dom_fragment') {
 let visited=0, truncated=false; const maxLength=Math.min(20000,Math.max(1,config.maxLength||5000));
 const copy=(source,depth)=>{
  if(++visited>200||depth>6){truncated=true;return node.ownerDocument.createTextNode('…');}
  if(source.nodeType===3)return node.ownerDocument.createTextNode(source.textContent.slice(0,500));
  if(source.nodeType!==1)return node.ownerDocument.createTextNode('');
  if(privateElement(source)||source.matches('input[type=password]'))return node.ownerDocument.createTextNode('[redacted]');
  const clone=source.cloneNode(false);
  for(const a of Array.from(clone.attributes))if(a.name.startsWith('on')||['value','nonce','srcdoc'].includes(a.name))clone.removeAttribute(a.name);else if(['href','src','action','formaction'].includes(a.name))clone.setAttribute(a.name,safeURL(a.value));
  if(!source.matches('input,textarea,script,style'))for(const child of source.childNodes){if(visited>=200){truncated=true;break;}clone.appendChild(copy(child,depth+1));}
  return clone;
 };
 const fragment=copy(node,0);const html=fragment.nodeType===1?fragment.outerHTML:fragment.textContent;
 return {html:html.slice(0,maxLength),truncated:truncated||html.length>maxLength};
}
if(disabled(node)) error('element_disabled','Target is disabled.');
const win=node.ownerDocument.defaultView;
const emit = (type,init={}) => node.dispatchEvent(new win.MouseEvent(type,{bubbles:true,cancelable:true,composed:true,...init}));
const hit = () => {
 if(!visible(node)) error('element_hidden','Target is hidden.');
 node.scrollIntoView({block:'center',inline:'center',behavior:'instant'});
 const r=node.getBoundingClientRect(), x=r.x+r.width/2,y=r.y+r.height/2;
 const hit=node.getRootNode().elementFromPoint?.(x,y)||node.ownerDocument.elementFromPoint(x,y);
 if(!hit||!(hit===node||node.contains(hit)||hit.contains(node)&&hit.shadowRoot)) error('element_obscured','Target is obscured; refresh the snapshot.');
 return {clientX:x,clientY:y,button:config.button==='right'?2:config.button==='middle'?1:0,ctrlKey:!!config.ctrlKey||(config.modifiers||[]).some(v=>['control','ctrl'].includes(String(v).toLowerCase())),shiftKey:!!config.shiftKey||(config.modifiers||[]).some(v=>String(v).toLowerCase()==='shift'),altKey:!!config.altKey||(config.modifiers||[]).some(v=>['alt','option'].includes(String(v).toLowerCase())),metaKey:!!config.metaKey||(config.modifiers||[]).some(v=>['meta','command','cmd'].includes(String(v).toLowerCase()))};
};
if(operation==='prepare_native_input'){if(config.requireFileInput&&!node.matches('input[type=file]'))error('wrong_element_type','Upload target must be a file input.');const point=hit();return {geometry:geometry(node),point:{x:point.clientX,y:point.clientY},frame:state?.nodes.get(ref)?.frame||'main'};}
const change = () => {node.dispatchEvent(new win.Event('input',{bubbles:true,composed:true}));node.dispatchEvent(new win.Event('change',{bubbles:true,composed:true}));};
const fill = text => {if(node.readOnly)error('element_readonly','Target is read-only.');node.focus();if(node.isContentEditable)node.textContent=text;else if(node.matches('input:not([type=file]):not([type=hidden]):not([type=checkbox]):not([type=radio]),textarea')) {const proto=node.tagName==='TEXTAREA'?win.HTMLTextAreaElement.prototype:win.HTMLInputElement.prototype;Object.getOwnPropertyDescriptor(proto,'value').set.call(node,text);}else error('not_editable','Target is not a text field.');change();if((node.isContentEditable?node.textContent:node.value)!==text)error('postcondition_failed','Text did not persist.');};
switch(operation) {
 case 'click': {const init=hit();emit('mousedown',init);node.focus();emit('mouseup',init);node.click();break;}
 case 'double_click': {const init=hit();node.click();node.click();emit('dblclick',{...init,detail:2});break;}
 case 'right_click': {const init=hit();emit('mousedown',{...init,button:2});emit('mouseup',{...init,button:2});emit('contextmenu',{...init,button:2});break;}
 case 'hover': case 'move_pointer': {const init=hit();emit('mouseover',init);emit('mouseenter',init);emit('mousemove',init);break;}
 case 'fill': fill(String(value));break;
 case 'clear_field':fill('');break;
 case 'type_text':fill(node.isContentEditable?node.textContent+String(value):String(node.value||'')+String(value));break;
 case 'select_option': {if(node.tagName!=='SELECT')error('wrong_element_type','Target must be a select.');const values=config.values||[String(value)];if(!node.multiple&&values.length!==1)error('invalid_arguments','Single select requires one value.');for(const v of values)if(!Array.from(node.options).some(o=>o.value===v&&!o.disabled))error('option_not_found','Requested option is unavailable.');for(const o of node.options)o.selected=values.includes(o.value);change();if(Array.from(node.selectedOptions).map(o=>o.value).sort().join('\0')!==[...values].sort().join('\0'))error('postcondition_failed','Selected options did not persist.');break;}
 case 'set_checked':case 'select_radio':{if(!node.matches('input[type=checkbox],input[type=radio]'))error('wrong_element_type','Target must be checkbox or radio.');const checked=operation==='select_radio'?true:config.checked!==false;if(node.checked!==checked){hit();node.click();}if(node.checked!==checked)error('postcondition_failed','Requested checked state did not persist.');break;}
 case 'submit_form':{const form=node.tagName==='FORM'?node:node.form||node.closest('form');if(!form)error('form_not_found','Target is not associated with a form.');if(!form.reportValidity())error('validation_failed','Form validation rejected submission.');form.requestSubmit();break;}
 case 'focus_element':node.focus();if(node.getRootNode().activeElement!==node&&node.ownerDocument.activeElement!==node)error('postcondition_failed','Element did not receive focus.');break;
 case 'blur_element':node.blur();break;
 case 'scroll_into_view':node.scrollIntoView({block:config.block||'center',inline:config.inline||'center',behavior:'instant'});break;
 case 'scroll_element':case 'scroll':node.scrollBy({left:Number(config.dx)||0,top:Number(dy)||0,behavior:'instant'});return {...synthetic,x:node.scrollLeft,y:node.scrollTop};
 case 'press_key':case 'key_down':case 'key_up':error('native_input_required','Synthetic keyboard events cannot execute editing or shortcuts; native keyboard input is unavailable.');
 case 'drag':case 'drag_and_drop':{const target=resolve(state,config.targetRef);if(!visible(target)||disabled(target))error('target_unavailable','Drop target is unavailable.');const init=hit(),transfer=new win.DataTransfer();const fire=(n,type)=>n.dispatchEvent(new win.DragEvent(type,{bubbles:true,cancelable:true,composed:true,dataTransfer:transfer,...init}));fire(node,'dragstart');fire(target,'dragenter');fire(target,'dragover');fire(target,'drop');fire(node,'dragend');break;}
 default:error('unsupported_operation','Unknown DOM operation.');
}
if(['right_click','hover','move_pointer','drag','drag_and_drop'].includes(operation))return {dispatched:true,inputSource:'synthetic',trusted:false,defaultActionPerformed:false,limitation:'Only DOM event handlers are invoked; native pointer behavior requires native input.'};
return synthetic;

"""#
    static let wait = runtime + #"""

const config=typeof options==='object'&&options?options:{};
const timeout=Math.min(300000,Math.max(1,Number(config.timeoutMs)||30000));
let state=globalThis.__astraBrowserUse;
if(!state) {
 if(config.ref) error('snapshot_required','Take a snapshot before waiting on a reference.');
 state={snapshotID,nodes:new Map(),reverse:new WeakMap(),waits:new Map(),visible,document};
 globalThis.__astraBrowserUse=state;
}
if(state.snapshotID!==snapshotID) error('stale_snapshot','Take a new snapshot.');
const operationID=config.operationID||crypto.randomUUID();
const check=()=>{
 let n=null;if(config.ref)n=resolve(state,config.ref);else if(config.selector||config.role||config.name){walk(document,candidate=>{if(n)return false;let matches=true;try{if(config.selector)matches=candidate.matches(config.selector);}catch{error('invalid_selector','CSS selector is invalid.');}if(config.role)matches=matches&&roleOf(candidate)===config.role;if(config.name)matches=matches&&nameOf(candidate)===config.name;if(matches&&!privateElement(candidate))n=candidate;return false;});}
 switch(config.condition){
 case 'element':case 'wait_for_element':return config.state==='hidden'?!n||!visible(n):config.state==='enabled'?!!n&&!disabled(n):config.state==='visible'?!!n&&visible(n):!!n;
 case 'text':case 'wait_for_text':{let exists=false;walk(document,candidate=>{if(!exists&&!privateElement(candidate)&&!candidate.matches('input,textarea,script,style'))exists=Array.from(candidate.childNodes).some(child=>child.nodeType===3&&child.textContent.includes(config.text||''));return false;});return config.state==='hidden'||config.state==='absent'?!exists:exists;}
 case 'url':case 'wait_for_url':return config.exact?location.href===config.url:safeURL(location.href).includes(config.url||'');
 case 'load':case 'wait_for_load_state':return config.state==='domcontentloaded'?document.readyState!=='loading':document.readyState==='complete';
 case 'navigation':case 'wait_for_navigation':return location.href!==config.url;
 default:error('invalid_condition','Unsupported wait condition.');
 }
};
if(check())return {ok:true,condition:config.condition,operationID};
return await new Promise((resolveWait,reject)=>{
 let done=false, fallback,deadline;const observers=[];const unloading=()=>finish('navigation');
 const finish=(reason)=>{if(done)return;done=true;for(const observer of observers)observer.disconnect();clearTimeout(deadline);clearInterval(fallback);for(const name of ['load','DOMContentLoaded','hashchange','popstate','resize'])window.removeEventListener(name,wake);window.removeEventListener('pagehide',unloading);state.waits.delete(operationID);reason?reject(new Error(reason+': Wait ended before its condition.')):resolveWait({ok:true,condition:config.condition,operationID});};
 const wake=()=>{try{if(check())finish();}catch(e){finish(e.message);}};
 const observe=root=>{const observer=new MutationObserver(wake);observer.observe(root,{subtree:true,childList:true,attributes:true,characterData:true});observers.push(observer);};
 observe(document);walk(document,n=>{if(n.shadowRoot)observe(n.shadowRoot);try{if(n.contentDocument)observe(n.contentDocument);}catch{}return false;});
 for(const name of ['load','DOMContentLoaded','hashchange','popstate','resize'])window.addEventListener(name,wake);
 window.addEventListener('pagehide',unloading,{once:true});
 state.waits.set(operationID,reason=>finish(reason||'cancelled'));
 deadline=setTimeout(()=>finish('wait_timeout'),timeout);
 // Slow fallback covers history.pushState and computed CSS changes without patching website APIs.
 fallback=setInterval(wake,1000);wake();
});

"""#
    static let cancelWait = #"""
globalThis.__astraBrowserUse?.waits.get(operationID)?.("cancelled");
return {ok: true};
"""#
}
#endif
