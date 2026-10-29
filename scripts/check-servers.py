#!/usr/bin/env python3
"""Read at most 4096 payload bytes per server; never run a bandwidth load."""
import concurrent.futures, json, pathlib, time, urllib.request, urllib.error
root=pathlib.Path(__file__).resolve().parent.parent
servers=json.loads((root/'Resources/Servers.json').read_text())
def check(s):
    start=time.monotonic()
    try:
        request=urllib.request.Request(s['download'],headers={'Range':'bytes=0-4095','User-Agent':'InternetPulse-catalog-check/1.7','Accept-Encoding':'identity'})
        with urllib.request.urlopen(request,timeout=12) as response:
            content=response.headers.get('Content-Type','');payload=response.read(4096)
            return dict(id=s['id'],country=s['country'],provider=s['name'],url=s['download'],status=response.status,bytes=len(payload),content_type=content,ok=bool(payload) and 'html' not in content.lower() and 'text/plain' not in content.lower(),seconds=round(time.monotonic()-start,2))
    except Exception as error:
        return dict(id=s['id'],country=s['country'],provider=s['name'],url=s['download'],ok=False,error=str(error),seconds=round(time.monotonic()-start,2))
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:results=list(pool.map(check,servers))
output=root/'build/server-check.json';output.parent.mkdir(exist_ok=True);output.write_text(json.dumps(results,indent=2,ensure_ascii=False)+'\n')
for country in ['RU','GB','US','FR','DE','ES']:
    matches=[s for s in results if s['country']==country]
    print(country,sum(s['ok'] for s in matches),'/',len(matches))
for s in results:
    if not s['ok']:print('UNAVAILABLE',s['id'],s['provider'],s.get('status',s.get('error')))
print('Availability is measured from the CI runner, not from the user’s ISP. See build/server-check.json.')
