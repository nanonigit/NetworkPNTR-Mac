"""Independent captured-index API exercise, executed only inside an owned offline reference."""
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import time
from urllib.parse import parse_qsl, urlencode, urlsplit

import captured_fixture_guest as fixture
from evidence_export_reference import Client as BoundedClient, BACKEND_SHA256, SOURCE_COMMIT, digest_file

BASE = '/api/exploration/findings/9101/traffic'
NOTE = 'F5 edited \ufeffe\u0301 English Japanese \u65e5\u672c\u8a9e \u4e2d\u6587 \ud55c\uad6d\uc5b4\ufeff'


def require(value, reason):
    if not value: raise RuntimeError('Captured reference ' + reason)


def valid(method, path, body):
    try:
        parsed = urlsplit(path)
        if parsed.scheme or parsed.netloc or parsed.fragment or '%' in parsed.path: return False
        pairs = parse_qsl(parsed.query, keep_blank_values=True); query = dict(pairs)
        if len(query) != len(pairs): return False
        route = parsed.path
        if method == 'GET' and body is None:
            if route == '/api/auth/status': return not query
            if route == '/api/traffic':
                return (set(query) <= {'page','size','host','method','q'} and query.get('page') in ('0','1')
                        and query.get('size') in ('25','500') and query.get('host','') in ('','127.0.0.1','192.0.2.1')
                        and query.get('method','') in ('','GET','POST') and query.get('q','') in ('','ordinal 05','日本語'))
            if route == '/api/traffic/exchange': return set(query) == {'id'} and re.fullmatch(r'[0-9]{1,20}-[0-9]{4}',query['id']) is not None
            if route in (BASE, '/api/exploration/findings/9101'): return not query
            if re.fullmatch(re.escape(BASE)+r'/[1-9][0-9]{0,18}',route): return not query
            if re.fullmatch(re.escape(BASE)+r'/[1-9][0-9]{0,18}/body',route):
                return (query.get('side') in ('request','response') and
                        ((set(query)=={'side','download'} and query['download']=='1') or
                         (set(query)=={'side','offset'} and query['offset'].isdigit() and 0<=int(query['offset'])<=262401)))
            return False
        if method == 'POST' and route in ('/api/auth/init','/api/auth/login'):
            return not query and isinstance(body,dict) and set(body) <= {'password','setup_token'} and isinstance(body.get('password'),str) and 8 <= len(body['password']) <= 128
        if method == 'POST' and route == BASE:
            refs = body.get('traffic_refs') if isinstance(body,dict) and set(body)=={'traffic_refs'} else None
            return (not query and type(refs) is list and 1<=len(refs)<=2 and all(type(ref) is dict and set(ref)<= {'traffic_id','role','note'}
                    and isinstance(ref.get('traffic_id'),str) and re.fullmatch(r'[0-9]{1,20}-[0-9]{4}',ref['traffic_id'])
                    and ref.get('role','supporting') in ('baseline','proof','verification','supporting')
                    and type(ref.get('note','')) is str and len(ref.get('note','').encode())<=8192 for ref in refs))
        if method in ('PATCH','DELETE','PUT') and not query and isinstance(body,dict) and type(body.get('version')) is int and 0<=body['version']<100:
            if method == 'PUT': return route==BASE+'/order' and set(body)=={'version','binding_ids'} and type(body['binding_ids']) is list and len(body['binding_ids'])==2 and all(re.fullmatch(r'[1-9][0-9]{0,18}',v) for v in body['binding_ids'] if type(v) is str) and all(type(v) is str for v in body['binding_ids'])
            if not re.fullmatch(re.escape(BASE)+r'/[1-9][0-9]{0,18}',route): return False
            if method == 'DELETE': return set(body)=={'version'}
            return set(body)=={'version','role','note'} and body['role'] in ('baseline','proof','verification','supporting') and type(body['note']) is str and len(body['note'].encode())<=8192
    except (TypeError,ValueError,KeyError): return False
    return False


class Client(BoundedClient):
    def api(self, method, path, body=None, *, expected=200):
        require(valid(method,path,body) and expected in (200,401,403,409), 'fixed request contract')
        payload = None if body is None else json.dumps(body,allow_nan=False,separators=(',',':')).encode()
        require(payload is None or len(payload)<=32768, 'request body bound')
        connection,response = self.connection(method,path,payload)
        try:
            require(response.status==expected, 'API status')
            raw = bytearray()
            while True:
                self.check(); chunk=response.read(65536)
                require(len(chunk)<=65536 and len(raw)+len(chunk)<=4*1024*1024, 'JSON bound')
                if not chunk: break
                raw.extend(chunk)
            value=json.loads(raw);require(type(value) is dict,'JSON object');return value
        finally: connection.close()
    def download(self,binding,side,expected):
        path=BASE+'/'+binding+'/body?side='+side+'&download=1'
        require(valid('GET',path,None),'download route')
        connection,response=self.connection('GET',path)
        try:
            headers=response.getheaders()
            require(response.status==200 and [v for k,v in headers if k.lower()=='content-length']==[str(len(expected))]
                    and not any(k.lower() in ('transfer-encoding','content-encoding') for k,v in headers),'body framing')
            digest=hashlib.sha256();count=0
            while True:
                self.check();chunk=response.read(65536)
                require(len(chunk)<=65536 and count+len(chunk)<=len(expected),'body bound')
                if not chunk: break
                require(chunk==expected[count:count+len(chunk)],'complete body bytes');digest.update(chunk);count+=len(chunk)
            require(count==len(expected),'complete body size')
            return dict(bytes=count,sha256=digest.hexdigest(),full_byte_equal=True)
        finally:connection.close()


def preview_expected(data,offset):
    require(type(offset) is int and 0<=offset<=len(data),'preview offset')
    raw=data[offset:offset+8192]
    if offset+len(raw)<len(data) and len(raw)>=4:
        try:raw.decode('utf-8')
        except UnicodeDecodeError as error:
            if error.reason=='unexpected end of data' and error.start>=len(raw)-4:raw=raw[:error.start]
    binary=b'\0' in raw
    if offset==0:
        try:raw.decode('utf-8')
        except UnicodeDecodeError:binary=True
    # Fixed backend display contract, retained as data rather than translated fixture text.
    content=('[二进制正文，%d 字节；请下载查看]' % len(data)) if binary else raw.decode('utf-8',errors='replace')
    return dict(content=content,offset=offset,total=len(data),next_offset=offset+len(raw),truncated=offset+len(raw)<len(data),binary=binary)


def normalized(summary):
    urls={row['url']:row['ordinal'] for row in fixture.exchange_manifest()}
    return dict(version=summary['version'],report_version=summary['report_version'],bindings=[
        dict(ordinal=urls[row['snapshot']['url']],role=row['role'],note_sha256=hashlib.sha256(row['note'].encode()).hexdigest(),position=row['position'],
             req_len=row['snapshot']['req_len'],resp_len=row['snapshot']['resp_len'],req_hash=row['snapshot']['req_hash'],resp_hash=row['snapshot']['resp_hash']) for row in summary['bindings']])


def exercise(client,records):
    pages=[client.api('GET','/api/traffic?page='+str(page)+'&size=25') for page in (0,1)]
    require([len(page['exchanges']) for page in pages]==[25,4] and len({row['id'] for page in pages for row in page['exchanges']})==29,'actual paging')
    filters=[]
    for suffix,total in [('host=127.0.0.1',29),('host=192.0.2.1',0),('method=GET',15),('method=POST',14),('q=ordinal+05',1),('q='+urlencode({'q':'日本語'})[2:],14)]:
        page=client.api('GET','/api/traffic?page=0&size=500&'+suffix);require(page['total']==total,'filter count');filters.append(dict(query=suffix,total=total))
    raw=client.api('GET','/api/traffic/exchange?'+urlencode({'id':records[1]['id']}))
    require(fixture.LITERAL.decode() in raw['resp'],'literal captured preview')
    initial=client.api('GET',BASE);require(initial['bindings']==[],'fresh bindings')
    refs=[{'traffic_id':records[index]['id'],'role':'supporting','note':'F5 captured source '+str(index)} for index in (3,4)]
    bound=client.api('POST',BASE,{'traffic_refs':refs});require(len(bound['bindings'])==2 and bound['version']>initial['version'],'bind receipt')
    fixture.audit_activity(2,2)
    sources={row['url']:row for row in fixture.exchange_manifest()};body_proofs=[];previews=[]
    for binding in bound['bindings']:
        spec=sources[binding['snapshot']['url']];detail=client.api('GET',BASE+'/'+binding['id'])
        for side in ('request','response'):
            data=fixture.request_body(spec['ordinal']) if side=='request' else fixture.response_body(spec['ordinal'])
            require(binding['snapshot']['req_len' if side=='request' else 'resp_len']==len(data),'snapshot size')
            require(binding['snapshot']['req_hash' if side=='request' else 'resp_hash']==hashlib.sha256(data).hexdigest(),'snapshot hash')
            body_proofs.append(dict(ordinal=spec['ordinal'],side=side,**client.download(binding['id'],side,data)))
            offset=0;joined=''
            while True:
                expected=preview_expected(data,offset)
                value=client.api('GET',BASE+'/'+binding['id']+'/body?side='+side+'&offset='+str(offset))
                require(value==expected,'exact byte preview')
                if offset==0:require(detail[side]==value,'detail initial preview')
                previews.append(dict(ordinal=spec['ordinal'],side=side,offset=offset,next_offset=value['next_offset'],binary=value['binary'],truncated=value['truncated'],content_sha256=hashlib.sha256(value['content'].encode()).hexdigest()))
                joined+=value['content']
                if value['binary'] or not value['truncated']:break
                offset=value['next_offset']
            if not expected['binary']:require(joined.encode()==data,'joined text bytes')
    first,second=[row['id'] for row in bound['bindings']]
    edited=client.api('PATCH',BASE+'/'+first,{'version':bound['version'],'role':'verification','note':NOTE})
    require(edited['bindings'][0]['note']==NOTE and edited['bindings'][0]['role']=='verification' and edited['version']>bound['version'],'edit receipt')
    client.api('PATCH',BASE+'/'+first,{'version':bound['version'],'role':'baseline','note':'must not apply'},expected=409)
    require(client.api('GET',BASE)==edited,'conflict readback unchanged')
    ordered=client.api('PUT',BASE+'/order',{'version':edited['version'],'binding_ids':[second,first]})
    require([row['id'] for row in ordered['bindings']]==[second,first] and [row['position'] for row in ordered['bindings']]==[0,1],'ordered membership')
    removed=client.api('DELETE',BASE+'/'+first,{'version':ordered['version']})
    require([row['id'] for row in removed['bindings']]==[second] and removed['version']>ordered['version'],'remove receipt')
    metadata=client.api('GET','/api/exploration/findings/9101')
    require(metadata['evidence_version']==removed['version'] and metadata['traffic_count']==1 and metadata['report_stale'] is True,'finding report metadata')
    counts=fixture.audit_activity(1,2)
    return dict(metadata={key:metadata[key] for key in ['evidence_version','report_evidence_version','traffic_count','report_stale']},filters=filters,bodies=body_proofs,previews=previews,states={name:normalized(value) for name,value in [('bound',bound),('edited',edited),('ordered',ordered),('removed',removed)]},counts=counts),removed


def main():
    fixture.environment()
    require(os.environ.get('ARTEX_DISPOSABLE_REFERENCE')=='1','owned reference flag')
    require(digest_file(Path('/opt/artex/artex'))==BACKEND_SHA256,'pinned backend')
    client=Client();password=secrets.token_hex(32);tokens=[password];process=None;logs=[];stopped=0;records=None;final=None;result=None
    try:
        for boot in (1,2):
            child=dict(os.environ,ARTEX_SETUP_TOKEN=secrets.token_hex(32),ARTEX_LANG='en',ARTEX_SKILL_DIR='/opt/artex/skills')
            tokens.append(child['ARTEX_SETUP_TOKEN']);log=Path('/state/app/captured-reference-'+str(boot)+'.log');logs.append(log)
            with log.open('xb') as stream:
                process=subprocess.Popen(['/opt/artex/artex','-addr','127.0.0.1:8787','-data','/state/app/data','-proxy','127.0.0.1:8788'],cwd='/state/app/data',env=child,stdout=stream,stderr=subprocess.STDOUT)
            for attempt in range(200):
                require(process.poll() is None,'backend stayed live');client.check()
                try:client.api('GET','/api/auth/status');break
                except (ConnectionError,OSError):time.sleep(.1)
            else:raise RuntimeError('Captured reference readiness deadline')
            if boot==1:
                client.api('GET',BASE,expected=401)
                client.token=client.api('POST','/api/auth/init',{'password':password,'setup_token':child['ARTEX_SETUP_TOKEN']})['token'];tokens.append(client.token)
                proof=fixture.prepare(client);records=proof['records'];result,final=exercise(client,records)
            else:
                require(fixture.read_records(client)==records,'recorded index persisted')
                require(client.api('GET',BASE)==final,'bindings and version persisted')
                require(fixture.audit_activity(1,2)==result['counts'],'activity persisted')
            process.terminate();require(process.wait(timeout=20)==0,'cooperative backend exit');process=None;stopped+=1
        for path in logs:
            with path.open('rb') as stream:raw=stream.read(4*1024*1024+1)
            require(len(raw)<=4*1024*1024 and all(value.encode() not in raw for value in tokens),'private credential-free logs')
        fixture.environment()
        print(json.dumps(dict(passed=True,sourceCommit=SOURCE_COMMIT,backendSHA256=BACKEND_SHA256,backendStarts=2,cooperativeStops=stopped,
                              recordedExchanges=29,persistence=True,credentialsAbsent=True,uiAcceptance=False,nativeComparison=False,exercise=result),ensure_ascii=False))
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:process.wait(timeout=20)
            except subprocess.TimeoutExpired:process.kill();process.wait(timeout=5)


if __name__=='__main__':main()
