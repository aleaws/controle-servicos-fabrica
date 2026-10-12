/* Guarda apenas os arquivos do aplicativo, nunca respostas de sincronização. */
const ROOT=new URL('./',self.location.href);
const PREFIX='servicos-fabrica-'+encodeURIComponent(ROOT.pathname)+'-',CACHE=PREFIX+'15ce886dd5dc';
const FILES=['./','./index.html','./Controle_de_Servicos_da_Manutencao.html','./manifest.webmanifest','./icons/icon-192.png','./icons/icon-512.png'];
const URLS=FILES.map(path=>new URL(path,ROOT).href);
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(URLS))));
// A atualização aguarda o fechamento das abas; nunca recarrega um formulário em uso.
self.addEventListener('activate',event=>event.waitUntil((async()=>{for(const key of await caches.keys())if(key.startsWith(PREFIX)&&key!==CACHE)await caches.delete(key);await self.clients.claim()})()));
self.addEventListener('fetch',event=>{
  const request=event.request;if(request.method!=='GET')return;
  const url=new URL(request.url);if(url.origin!==ROOT.origin)return;
  url.search='';url.hash='';if(!URLS.includes(url.href))return;
  event.respondWith((async()=>{
    const cache=await caches.open(CACHE);
    try{const response=await fetch(request);if(response.ok&&response.type==='basic')await cache.put(url.href,response.clone());return response}
    catch(error){const cached=await cache.match(url.href);if(cached)return cached;throw error}
  })());
});
