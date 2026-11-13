import{a as E}from"./chunk-2GWS2I6U.js";import{a as j,b as q,c as x,d as N,e as W,f as w,g as Z,h as u,i as f}from"./chunk-4NOHUTGO.js";import{c as b,d as D,e as F,f as A}from"./chunk-DZQX2M6T.js";import"./chunk-3RNHDNP5.js";var S=e=>e.replace(/&/g,"&amp;").replace(/"/g,"&quot;").replace(/</g,"&lt;").replace(/>/g,"&gt;"),C={WHOLE_DOCUMENT:!0,USE_PROFILES:{html:!0,svg:!0,svgFilters:!0,mathMl:!0},ADD_TAGS:["use"],ADD_ATTR:["target","rel","download"],FORBID_TAGS:["script","iframe","object","embed","base","form","link"],FORBID_ATTR:["srcdoc"]},k=e=>e||globalThis.document||null,y=e=>/[A-Za-z0-9_-]/.test(e),X=(e,n)=>{let r=n+1,i=e[r]||"";if(!i)return{value:"",nextIndex:r};if(i==="\r"||i===`
`||i==="\f")return i==="\r"&&e[r+1]===`
`&&(r+=1),{value:"",nextIndex:r+1};let t="";for(;r<e.length&&t.length<6&&/[0-9a-f]/i.test(e[r]||"");)t+=e[r],r+=1;if(t){/\s/.test(e[r]||"")&&(r+=1);let a=Number.parseInt(t,16);return{value:a===0||a>1114111?"\uFFFD":String.fromCodePoint(a),nextIndex:r}}return{value:i,nextIndex:r+1}},Y=e=>{let n="",r="",i=0;for(;i<e.length;){let t=e[i]||"";if(r){if(n+=t,t==="\\"){n+=e[i+1]||"",i+=2;continue}t===r&&(r=""),i+=1;continue}if(t==="/"&&e[i+1]==="*"){let o=e.indexOf("*/",i+2);i=o<0?e.length:o+2;continue}if(t==='"'||t==="'"){r=t,n+=t,i+=1;continue}if(t==="\\"){let o=X(e,i);n+=o.value,i=o.nextIndex;continue}let a=t.charCodeAt(0);n+=a<32&&t!=="	"&&t!==`
`&&t!=="\r"?" ":t,i+=1}return n},T=/^data:(?:image\/(?:avif|bmp|gif|jpeg|png|webp|x-icon)|font\/(?:collection|otf|sfnt|ttf|woff2?)|application\/(?:font-sfnt|font-woff|vnd\.ms-fontobject|x-font-opentype|x-font-ttf|x-font-woff));/i,G=e=>{let n=/^data:image\/svg\+xml(?:;charset=[A-Za-z0-9._-]+)?,([\s\S]*)$/i.exec(e);if(!n||n[1].length>1024*1024)return!1;let r;try{r=decodeURIComponent(n[1])}catch{return!1}if(!/^\s*<svg(?:\s|>)/i.test(r)||/<\/?(?:script|style|foreignObject|iframe|object|embed|form|link)\b/i.test(r)||/<!\s*(?:doctype|entity)\b/i.test(r)||/\son[a-z0-9_-]+\s*=/i.test(r)||/@import\b/i.test(r)||/url\s*\(\s*(?!["']?#)/i.test(r))return!1;for(let i of r.matchAll(/\s(?:href|xlink:href|src)\s*=\s*(["'])([\s\S]*?)\1/gi)){let t=K(i[2]||"");if(!/^#[A-Za-z0-9_.:-]+$/.test(t)&&!T.test(t))return!1}return!0},h=e=>{let n="";for(let r of e){let i=r.charCodeAt(0);i<=32||i>=127&&i<=159||(n+=r)}return n.trim()},K=h,J=/^data:(?:image\/(?:avif|bmp|gif|jpeg|png|webp|x-icon)|audio\/[a-z0-9.+-]+|video\/[a-z0-9.+-]+|text\/vtt)(?:;[^,]*)?,/i,Q=e=>{let n=h(e);return n?n.startsWith("#")||/^blob:/i.test(n)?!0:J.test(n):!1},d=(e,n,r={})=>{if(!e.hasAttribute(n))return;let i=h(e.getAttribute(n)||"");(r.fragmentOnly?/^#[A-Za-z0-9_.:-]+$/.test(i):Q(i))?e.setAttribute(n,i):e.removeAttribute(n)},ee=e=>{let n=e.trim(),r=n[0];return(r==='"'||r==="'")&&n[n.length-1]===r&&(n=n.slice(1,-1).trim()),h(n)},te=e=>{let n=ee(e);return n?n.startsWith("#")||/^blob:/i.test(n)?!0:T.test(n)||G(n):!1},re=(e,n)=>{let r="";for(let i=n;i<e.length;i+=1){let t=e[i]||"";if(r){t==="\\"?i+=1:t===r&&(r="");continue}if(t==='"'||t==="'")r=t;else if(t===")")return i}return-1},R=e=>{let n=!1,r=!1,i="",t=0;for(;t<e.length;){let a=e[t]||"";if(i){if(a==="\\"){t+=2;continue}a===i&&(i=""),t+=1;continue}if(a==="/"&&e[t+1]==="*"){let o=e.indexOf("*/",t+2);t=o<0?e.length:o+2;continue}if(a==='"'||a==="'"){i=a,t+=1;continue}if(a==="\\"){t+=2;continue}if(a==="@"&&e.slice(t+1,t+7).toLowerCase()==="import"){let o=e[t+7]||"";(!o||!y(o))&&(n=!0)}if(e.slice(t,t+3).toLowerCase()==="url"&&!y(e[t-1]||"")){let o=t+3;for(;/\s/.test(e[o]||"");)o+=1;e[o]==="("&&(r=!0)}t+=1}return{hasImport:n,hasUrl:r}},H=e=>{let n=Y(e),r=R(n),i=R(e);if(r.hasImport||r.hasUrl&&!i.hasUrl)return"";if(!i.hasUrl)return e;let t="",a="",o=0;for(;o<e.length;){let l=e[o]||"";if(a){if(t+=l,l==="\\"){t+=e[o+1]||"",o+=2;continue}l===a&&(a=""),o+=1;continue}if(l==='"'||l==="'"){a=l,t+=l,o+=1;continue}if(l==="/"&&e[o+1]==="*"){let p=e.indexOf("*/",o+2);if(p<0){t+=e.slice(o);break}t+=e.slice(o,p+2),o=p+2;continue}if(l==="\\"){t+=l,t+=e[o+1]||"",o+=2;continue}if(e.slice(o,o+3).toLowerCase()==="url"&&!y(e[o-1]||"")){let p=o+3;for(;/\s/.test(e[p]||"");)p+=1;if(e[p]==="("){let s=re(e,p+1);if(s<0)return"";let c=e.slice(p+1,s);t+=te(c)?e.slice(o,s+1):"none",o=s+1;continue}}t+=l,o+=1}return t},V=e=>{let n=e.defaultView;if(!n)return null;let r=E(n);return r.isSupported?(r.addHook("afterSanitizeElements",i=>{let t=i;if(t.localName?.toLowerCase()!=="style")return;let a=H(t.textContent||"");a?t.textContent=a:t.remove()}),r.addHook("afterSanitizeAttributes",i=>{let t=i,a=t.localName?.toLowerCase();if(a==="a"&&(t.getAttribute("target")||"").trim().toLowerCase()==="_blank"&&t.setAttribute("rel","noopener noreferrer"),(a==="a"||a==="area")&&t.removeAttribute("ping"),t.hasAttribute("srcset")&&t.removeAttribute("srcset"),["img","audio","video","source","track","input"].includes(a||"")&&d(t,"src"),a==="video"&&d(t,"poster"),t.hasAttribute("background")&&d(t,"background"),t.namespaceURI==="http://www.w3.org/2000/svg"&&a!=="a"){let o=a==="use"||a==="mpath";d(t,"href",{fragmentOnly:o}),d(t,"xlink:href",{fragmentOnly:o})}if(t.hasAttribute("style")){let o=H(t.getAttribute("style")||"");o?t.setAttribute("style",o):t.removeAttribute("style")}}),r):null},ne=['<meta charset="utf-8" />','<meta name="viewport" content="width=device-width,initial-scale=1" />'].join(`
  `),z=(e,n)=>{let r=k(n),i=r?V(r):null;return i?`<!doctype html>
${String(i.sanitize(e,C)).replace("<head>",`<head>
  ${ne}`)}`:`<!doctype html>
<html lang="en"><head><meta charset="utf-8" /></head><body></body></html>`},O=e=>{let n=e.createElement("html");n.lang="en";let r=e.createElement("head"),i=e.createElement("meta");return i.setAttribute("charset","utf-8"),r.append(i),n.append(r,e.createElement("body")),n},ie=e=>{let n=e.querySelector(":scope > head");if(!n)return e;if(!n.querySelector("meta[charset]")){let r=e.ownerDocument.createElement("meta");r.setAttribute("charset","utf-8"),n.prepend(r)}if(!n.querySelector('meta[name="viewport"]')){let r=e.ownerDocument.createElement("meta");r.setAttribute("name","viewport"),r.setAttribute("content","width=device-width,initial-scale=1"),n.querySelector("meta[charset]")?.after(r)}return e},M=(e,n)=>{let r=k(n);if(!r)throw new Error("A browser document is required to build printable DOM.");let i=V(r);if(!i)return O(r);let t=i.sanitize(e,{...C,RETURN_DOM:!0});return!t||t.nodeType!==1||t.localName.toLowerCase()!=="html"?O(r):ie(t)},oe=`
  * { box-sizing: border-box; }
  html, body { margin: 0; min-height: 100%; background: #f2f4f7; color: #172033; font-family: Aptos, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif; print-color-adjust: exact; -webkit-print-color-adjust: exact; }
  body { padding: 24px; }
  .viewer-export-shell { position: relative; min-height: calc(100vh - 48px); overflow: visible; background: #f2f4f7; }
  .viewer-export-content { position: relative; z-index: 1; contain: none; width: 100%; min-height: 100%; overflow: visible; }
  .viewer-export-watermark { position: absolute; inset: 0; pointer-events: none; z-index: 20; background-repeat: repeat; print-color-adjust: exact; -webkit-print-color-adjust: exact; }
  .viewer-export-content .file-render,
  .viewer-export-content .file-viewer,
  .viewer-export-content .viewer-stage,
  .viewer-export-content .content,
  .viewer-export-content .pdf-shell,
  .viewer-export-content .pdf-content,
  .viewer-export-content .pdf-viewport,
  .viewer-export-content .pdf-wrapper,
  .viewer-export-content .docx-fit-viewer,
  .viewer-export-content .docx-wrapper,
  .viewer-export-content .docx-canvas-wrapper,
  .viewer-export-content .msdoc-stage,
  .viewer-export-content .msdoc-paged-view,
  .viewer-export-content .code-viewer,
  .viewer-export-content .markdown-viewer,
  .viewer-export-content .email-shell,
  .viewer-export-content .archive-shell,
  .viewer-export-content .eda-shell,
  .viewer-export-content .ebook-shell,
  .viewer-export-content .umd-shell,
  .viewer-export-content .drawing-shell,
  .viewer-export-content .audio-shell,
  .viewer-export-content .cad-shell,
  .viewer-export-content .cad-body,
  .viewer-export-content .cad-canvas-wrap,
  .viewer-export-content .dwg-preview-frame {
    position: relative !important;
    inset: auto !important;
    contain: none !important;
    width: 100% !important;
    height: auto !important;
    min-height: 0 !important;
    max-height: none !important;
    overflow: visible !important;
  }
  .viewer-export-content .docx-wrapper {
    display: block !important;
    padding: 0 !important;
    background: transparent !important;
  }
  .viewer-export-content .docx-canvas-wrapper {
    display: block !important;
    padding: 0 !important;
    background: transparent !important;
  }
  .viewer-export-content .docx-print-document {
    display: block !important;
    width: fit-content !important;
    max-width: 100% !important;
    height: auto !important;
    overflow: visible !important;
    margin: 0 auto !important;
  }
  .viewer-export-content .docx-page-frame {
    position: relative !important;
    width: var(--viewer-print-page-width, fit-content) !important;
    height: var(--viewer-print-page-height, auto) !important;
    min-height: var(--viewer-print-page-height, 0) !important;
    max-width: 100% !important;
    margin: 0 auto 18px !important;
    overflow: hidden !important;
    break-inside: avoid;
    page-break-inside: avoid;
    break-after: page;
    page-break-after: always;
  }
  .viewer-export-content .docx-canvas-sheet {
    position: relative !important;
    contain: none !important;
    width: var(--viewer-print-page-width, 794px) !important;
    height: var(--viewer-print-page-height, 1123px) !important;
    min-height: var(--viewer-print-page-height, 1123px) !important;
    max-width: 100% !important;
    margin: 0 auto 18px !important;
    overflow: hidden !important;
    box-shadow: none !important;
    break-inside: avoid;
    page-break-inside: avoid;
    break-after: page;
    page-break-after: always;
  }
  .viewer-export-content .docx-canvas-sheet > img {
    display: block !important;
    width: 100% !important;
    height: 100% !important;
    max-width: none !important;
    object-fit: fill;
  }
  .viewer-export-content .msdoc-page {
    position: relative !important;
    width: var(--viewer-print-page-width, 794px) !important;
    min-height: var(--viewer-print-page-height, 1123px) !important;
    max-width: 100% !important;
    height: auto !important;
    margin: 0 auto 18px !important;
    overflow: visible !important;
    break-after: page;
    page-break-after: always;
  }
  .viewer-export-content .docx-page-frame:last-child,
  .viewer-export-content .docx-canvas-sheet:last-child,
  .viewer-export-content .msdoc-page:last-child {
    break-after: auto;
    page-break-after: auto;
  }
  .viewer-export-content .docx-page-frame > section.docx {
    position: relative !important;
    top: auto !important;
    left: auto !important;
    width: var(--viewer-print-page-width, auto) !important;
    min-height: var(--viewer-print-page-height, auto) !important;
    max-width: none !important;
    margin: 0 auto !important;
    overflow: visible !important;
    transform: none !important;
    box-shadow: none !important;
    break-inside: avoid;
    page-break-inside: avoid;
  }
  .viewer-export-content .msdoc-stage {
    display: block !important;
    padding: 0 !important;
    background: transparent !important;
  }
  .viewer-export-content .msdoc-paged-view {
    display: block !important;
    gap: 0 !important;
    padding: 0 !important;
    background: transparent !important;
  }
  .viewer-export-content .msdoc-page > .msdoc-root {
    margin: 0 auto !important;
    box-shadow: none !important;
    overflow: visible !important;
  }
  .viewer-export-content .pdf-toolbar,
  .viewer-export-content .pdf-nav-pane,
  .viewer-export-content .viewer-actions,
  .viewer-export-content .code-toolbar,
  .viewer-export-content .umd-toolbar,
  .viewer-export-content .drawing-toolbar,
  .viewer-export-content .cad-toolbar {
    display: none !important;
  }
  .viewer-export-content .pdf-content,
  .viewer-export-content .pdf-shell--nav-hidden .pdf-content,
  .viewer-export-content .cad-body.without-layers {
    display: block !important;
    grid-template-columns: none !important;
  }
  .viewer-export-content .pdfViewer { padding: 0 !important; }
  .viewer-export-content .pdfViewer .page {
    margin: 0 auto 16px !important;
    border: 0 !important;
    box-shadow: none !important;
    break-after: page;
    page-break-after: always;
  }
  .viewer-export-content .pdfViewer .page:last-child {
    break-after: auto;
    page-break-after: auto;
  }
  .viewer-export-content .pdf-export-document {
    display: grid;
    justify-items: center;
    gap: 18px;
    padding: 4px 0;
  }
  .viewer-export-content .pdf-export-page {
    width: var(--viewer-print-page-width, auto);
    height: var(--viewer-print-page-height, auto);
    max-width: 100%;
    overflow: hidden;
    background: #ffffff;
    box-shadow: 0 12px 32px rgba(15, 23, 42, 0.12);
    break-inside: avoid;
    page-break-inside: avoid;
    break-after: page;
    page-break-after: always;
  }
  .viewer-export-content .pdf-export-page:last-child {
    break-after: auto;
    page-break-after: auto;
  }
  .viewer-export-content .pdf-export-page img {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: contain;
  }
  .viewer-export-content .pptx-wrapper {
    width: 100% !important;
    max-width: 100% !important;
    height: auto !important;
    overflow: visible !important;
    transform: none !important;
  }
  .viewer-export-content .pptx-wrapper .slide {
    margin: 0 auto 18px !important;
    break-inside: avoid;
    page-break-inside: avoid;
    break-after: page;
    page-break-after: always;
    box-shadow: none !important;
  }
  .viewer-export-content .pptx-wrapper .slide:last-child {
    break-after: auto;
    page-break-after: auto;
  }
  .viewer-export-content .ofd-stage {
    padding: 0 !important;
    overflow: visible !important;
  }
  .viewer-export-content .ofd-page,
  .viewer-export-content .drawing-svg,
  .viewer-export-content .cad-canvas-wrap,
  .viewer-export-content .dwg-preview-frame {
    break-inside: avoid;
    page-break-inside: avoid;
    break-after: page;
    page-break-after: always;
    box-shadow: none !important;
  }
  .viewer-export-content .ofd-page:last-child,
  .viewer-export-content .drawing-svg:last-child,
  .viewer-export-content .cad-canvas-wrap:last-child,
  .viewer-export-content .dwg-preview-frame:last-child {
    break-after: auto;
    page-break-after: auto;
  }
  .viewer-export-content .code-area {
    overflow: visible !important;
    white-space: pre-wrap !important;
    word-break: break-word !important;
  }
  .viewer-export-content .umd-body,
  .viewer-export-content .umd-stage-wrap,
  .viewer-export-content .umd-stage {
    display: block !important;
    height: auto !important;
    max-height: none !important;
    overflow: visible !important;
  }
  .viewer-export-content .umd-toc {
    display: none !important;
  }
  img, canvas, svg, video { max-width: 100%; }
  @media print {
    @page { margin: 12mm; }
    html, body { min-height: auto; background: #ffffff; }
    body { padding: 0; }
    .viewer-export-shell,
    .viewer-export-content {
      min-height: 0;
      overflow: visible;
      background: #ffffff;
    }
    .viewer-export-content .docx-print-document {
      width: auto !important;
      max-width: none !important;
      margin: 0 !important;
    }
    .viewer-export-content .pdf-export-document {
      display: block;
      padding: 0;
    }
    .viewer-export-content .pdf-export-page {
      width: var(--viewer-print-page-width, auto) !important;
      height: var(--viewer-print-page-height, auto) !important;
      max-width: none !important;
      margin: 0;
      overflow: hidden;
      box-shadow: none;
    }
    .viewer-export-content .docx-page-frame {
      width: var(--viewer-print-page-width, auto) !important;
      height: var(--viewer-print-page-height, auto) !important;
      min-height: var(--viewer-print-page-height, 0) !important;
      max-width: none !important;
      margin: 0 !important;
      overflow: hidden !important;
    }
    .viewer-export-content .docx-canvas-sheet {
      contain: none !important;
      width: var(--viewer-print-page-width, 794px) !important;
      height: var(--viewer-print-page-height, 1123px) !important;
      min-height: var(--viewer-print-page-height, 1123px) !important;
      max-width: none !important;
      margin: 0 !important;
      overflow: hidden !important;
      box-shadow: none !important;
    }
    .viewer-export-content .msdoc-page {
      width: var(--viewer-print-page-width, 794px) !important;
      min-height: var(--viewer-print-page-height, 1123px) !important;
      max-width: none !important;
      margin: 0 !important;
      overflow: visible !important;
    }
    .viewer-export-content .docx-page-frame > section.docx,
    .viewer-export-content .msdoc-page > .msdoc-root {
      width: var(--viewer-print-page-width, 100%) !important;
      max-width: none !important;
      border: 0 !important;
    }
    .viewer-export-content .pptx-wrapper .slide,
    .viewer-export-content .ofd-page,
    .viewer-export-content .drawing-svg,
    .viewer-export-content .cad-canvas-wrap,
    .viewer-export-content .dwg-preview-frame {
      box-shadow: none !important;
    }
  }
`,_=e=>{let n=k(e);return n?Array.from(n.querySelectorAll('style, link[rel="stylesheet"]')).map(r=>{if(r.localName.toLowerCase()==="style")return`<style>${r.textContent||""}</style>`;let i=r;try{let t=Array.from(i.sheet?.cssRules||[]).map(a=>a.cssText).join(`
`);return t?`<style data-viewer-inlined-stylesheet>${t}</style>`:""}catch{return""}}).filter(Boolean).join(`
`):""},I=({contentHtml:e,includeDocumentStyles:n=!0,printStyle:r="",title:i,watermarkInlineStyle:t="",mask:a=null,documentRef:o})=>{let l=t?`<div class="viewer-export-watermark" style="${S(t)}"></div>`:"",p=b(a),s=p?{...p,regions:p.regions?.filter(g=>g.pageIndex===void 0),stamps:p.stamps?.filter(g=>g.pageIndex===void 0)}:null,c=D(s),m=A(e,p),v=n?_(o):"",B=r?`<style data-viewer-print-style>${r}</style>`:"",$=p?`<style data-viewer-print-mask-style>${F}</style>`:"";return`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>${S(i)}</title>
  ${v}
  <style>${oe}</style>
  ${$}
</head>
<body>
  <main class="viewer-export-shell">
    <div class="viewer-export-content">${m}</div>
    ${c}
    ${l}
  </main>
  ${B}
</body>
</html>`},P=e=>z(I(e),e.documentRef),L=e=>M(I(e),e.documentRef),U=async({source:e,mode:n="export",title:r,adapter:i=null,watermarkInlineStyle:t="",mask:a=null})=>{let o={mode:n,title:r},l=i?.toHtml,p=b(a);if(l){await f(e,i);let m=await w(await l(o)),v=await u(i,o);return{contentHtml:m,includeDocumentStyles:i.includeDocumentStyles!==!1,printStyle:v,title:r,watermarkInlineStyle:t,mask:p,documentRef:e.ownerDocument}}await f(e,i);let s=e.cloneNode(!0);s.querySelectorAll(".viewer-watermark").forEach(m=>m.remove()),x(e,s);let c=await u(i,o);return{contentHtml:await w(s.innerHTML),printStyle:c,title:r,watermarkInlineStyle:t,mask:p,documentRef:e.ownerDocument}},ae=async e=>P(await U(e)),pe=async e=>L(await U(e));export{L as buildExportDomDocument,P as buildExportHtmlDocument,pe as buildFileViewerRenderedDomDocument,ae as buildFileViewerRenderedHtmlDocument,_ as collectDocumentStyles,w as inlineFileViewerBlobUrlsInHtml,f as prepareFileViewerRenderedContentForSnapshot,x as replaceFileViewerCanvasWithImages,u as resolveFileViewerPrintStyle,M as sanitizeFileViewerExportDocumentDom,z as sanitizeFileViewerExportDocumentHtml,j as triggerFileViewerBlobDownload,q as triggerFileViewerUrlDownload,W as waitForFileViewerImages,N as waitForFileViewerNextPaint,Z as waitForFileViewerPrintWindowReady};
