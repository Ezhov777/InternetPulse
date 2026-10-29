#!/usr/bin/env python3
"""Resolve published download links from public provider looking-glass pages."""
import concurrent.futures,html,json,pathlib,re,time,urllib.request,urllib.parse
root=pathlib.Path(__file__).resolve().parent.parent
catalog=json.loads((root/'Resources/Servers.json').read_text())
sources=[(s['country'],s['name'],s['source']) for s in catalog if s['country']!='RU']
sources += [('ES','GTHost','https://lg-mad.gthost.com/'),('ES','GINERNET','https://lg.ginernet.com/'),('FR','Hosteons','https://lg.fr.hosteons.com/'),('DE','Hosteons','https://lg.de.hosteons.com/'),('GB','INTROSERV','https://lg.uk.introserv.com/'),('FR','INTROSERV Strasbourg','https://lg.fr.introserv.com/'),('FR','INTROSERV Gravelines','https://lg2.fr.introserv.com/'),('DE','INTROSERV Frankfurt','https://lg.de.introserv.com/'),('DE','INTROSERV Limburg','https://lg2.de.introserv.com/'),('FR','RedSwitches','https://lg.pa6.redswitches.com/'),('GB','Valebyte','https://valebyte.com/en/looking-glass/'),('GB','Mythic Beasts','https://www.mythic-beasts.com/speedtest'),('GB','GTHost','https://lg-lon.gthost.com/'),('FR','GTHost','https://lg-par.gthost.com/'),('DE','GTHost','https://lg-fra.gthost.com/'),('ES','FDC primary','http://50.7.80.4/'),('GB','FDC primary','http://50.7.152.4/'),('DE','FDC primary','http://50.7.84.4/'),('FR','FDC primary','http://50.7.33.4/')]
sources=list(dict.fromkeys(sources))
def request(url):return urllib.request.Request(url,headers={'User-Agent':'InternetPulse-catalog-check/1.7','Range':'bytes=0-262143'})
def scan(item):
    country,name,url=item
    try:
        with urllib.request.urlopen(request(url),timeout=10) as r:text=r.read(262144).decode('utf-8',errors='replace');base=r.url
        paths=re.findall(r'''(?:href|data-url)\s*=\s*["']([^"']+)["']''',text,re.I)
        paths+=re.findall(r'''["']((?:https?://|/)[^"'<>\s]+\.(?:bin|dat|test|zip|file))(?:["'])''',text,re.I)
        links=list(dict.fromkeys(urllib.parse.urljoin(base,html.unescape(p)) for p in paths if re.search(r'\.(?:bin|dat|test|zip|file)(?:\?|$)',p,re.I)))
        return dict(country=country,name=name,source=url,links=links)
    except Exception as e:return dict(country=country,name=name,source=url,error=str(e))
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:pages=list(pool.map(scan,sources))
candidates=[]
for page in pages:
    links=page.get('links',[])
    # one bounded request per published link, not a bandwidth test
    for url in links[:6]:candidates.append(dict(country=page['country'],name=page['name'],source=page['source'],url=url))
def check(s):
    try:
        with urllib.request.urlopen(request(s['url']),timeout=8) as r:
            data=r.read(4096);s['type']=r.headers.get('Content-Type','');s['ok']=bool(data) and 'html' not in s['type'].lower();s['final_url']=r.url
    except Exception as e:s['ok']=False;s['error']=str(e)
    return s
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:results=list(pool.map(check,candidates))
output=root/'build/server-discovery.json';output.write_text(json.dumps(dict(pages=pages,candidates=results),indent=2,ensure_ascii=False)+'\n')
for s in results:
    if s['ok']:print('OK',s['country'],s['name'],s['url'])
