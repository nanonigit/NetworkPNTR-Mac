"""Disposable local Docker reference for real captured traffic; never an app runtime dependency."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import uuid

from evidence_reference_host import SETUP, DUMP, builder_is_local

ROOT=Path(__file__).resolve().parents[1]
DOCKER=['/usr/local/bin/docker','--context','desktop-linux']
BACKEND='sha256:46b3ce5d5f91cd05b9e3fd6834e33196be9626eb40d38e84b7fb398f00a172d0'
RUNTIME='sha256:735d063ffd4290be40a870c4c77f6a6f9ad16ae306262e2e21e3865cd9c2b91d'


def local_context(value):
    return bool(isinstance(value,str) and value.startswith('unix:///') and not any(ord(c)<32 for c in value))


def require(value,reason):
    if not value:raise RuntimeError('Captured host '+reason)


def sources():
    names=['captured_reference.py','captured_fixture_guest.py','evidence_export_reference.py','evidence_fixture_guest.py','findings_seed_guest.py','findings_fixture_control.py']
    return {**{name:ROOT/'script'/name for name in names},'check_network.py':ROOT/'guest/check_network.py'}


def create_arguments(name,owner,tag):
    require(re.fullmatch(r'[a-z0-9][a-z0-9-]{0,63}',name) and re.fullmatch(r'[0-9a-f]{32}',owner) and re.fullmatch(r'[a-z0-9][a-z0-9:-]{0,127}',tag),'fixed generated identity')
    return ['create','--name',name,'--label','com.nanonigit.artex.fixture='+owner,'--platform','linux/arm64',
            '--user','1000:1000','--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges',
            '--pids-limit','128','--memory','2g','--tmpfs','/state:rw,nosuid,nodev,noexec,size=768m,mode=700,uid=1000,gid=1000',
            '--tmpfs','/tmp:rw,nosuid,nodev,noexec,size=64m,mode=1777',tag]


INSTALL=textwrap.dedent('''
import base64,json,os,pathlib,sys
bundle=json.load(sys.stdin)
allowed={'captured_reference.py','captured_fixture_guest.py','evidence_export_reference.py','evidence_fixture_guest.py','findings_seed_guest.py','findings_fixture_control.py','check_network.py'}
assert set(bundle)==allowed
folder=pathlib.Path('/state/tools');folder.mkdir(mode=0o700)
for name,value in bundle.items():
 data=base64.b64decode(value,validate=True);assert len(data)<=128*1024
 fd=os.open(folder/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
 with os.fdopen(fd,'wb') as stream:assert stream.write(data)==len(data)
print(json.dumps({'sources_installed':True,'uid':os.getuid()}))
''')
EXECUTE=textwrap.dedent('''
import json,os,runpy,sys,trace
os.environ.update(json.load(open('/state/environment.json')))
os.environ['ARTEX_CAPTURE_FIXTURE']='1'
sys.path.insert(0,'/state/tools')
tracer=trace.Trace(count=True,trace=False)
try:tracer.runfunc(runpy.run_path,'/state/tools/captured_reference.py',run_name='__main__')
finally:
 counts={}
 for (filename,line),count in tracer.results().counts.items():
  if filename.startswith('/state/tools/') and count:counts.setdefault(os.path.basename(filename),[]).append(line)
 with open('/state/executed-lines.json','x') as stream:json.dump({name:sorted(set(lines)) for name,lines in counts.items()},stream)
''')
EXPORT_LOGS=textwrap.dedent('''
import base64,json,pathlib
result={}
for name in ['postgres.log','app/captured-reference-1.log','app/captured-reference-2.log']:
 path=pathlib.Path('/state')/name
 if path.exists():
  with path.open('rb') as stream:data=stream.read(4*1024*1024+1)
  assert len(data)<=4*1024*1024
  result[path.name]=base64.b64encode(data).decode()
print(json.dumps(result))
''')


def main():
    os.umask(0o077)
    output=Path(tempfile.mkdtemp(prefix='artex-captured-reference-'))
    owner=uuid.uuid4().hex;name='artex-capture-'+owner[:12];tag='artex-mac-captured:'+owner[:12]
    aliases={label:'artex-mac-capture-input-'+label+':'+owner[:12] for label in ('backend','runtime')}
    summary=dict(passed=False,root=str(output),owner=owner,exercise_passed=False,exports={},cleanup={})
    original_tags={};existing=[];owned_tags=[];container=None;image=None;stage='preflight'
    def run(label,args,*,data=None,timeout=60,check=True):
        with (output/(label+'.stdout')).open('xb') as stdout,(output/(label+'.stderr')).open('xb') as stderr:
            result=subprocess.run(DOCKER+args,input=data,stdout=stdout,stderr=stderr,timeout=timeout)
        require((output/(label+'.stdout')).stat().st_size<=4*1024*1024 and (output/(label+'.stderr')).stat().st_size<=4*1024*1024,'private diagnostic output bound')
        if check:require(result.returncode==0,'command '+label)
        return result.returncode,(output/(label+'.stdout')).read_bytes()
    def inspect_owned(label):
        code,data=run(label,['inspect',name],check=False)
        if code:return None
        record=json.loads(data)[0]
        require(record['Config']['Labels'].get('com.nanonigit.artex.fixture')==owner,'container ownership')
        require(container is None or record['Id']==container,'container identity')
        return record
    def isolated(record):
        host=record['HostConfig']
        return (host['NetworkMode']=='none' and record['Config']['User']=='1000:1000' and host['ReadonlyRootfs']
                and not host['Privileged'] and host['CapDrop']==['ALL'] and 'no-new-privileges' in host['SecurityOpt']
                and not any(m['Type'] in ('bind','volume') for m in record.get('Mounts',[])) and not host['PortBindings'])
    try:
        _,context=run('context',['context','inspect','desktop-linux','--format','{{.Endpoints.docker.Host}}'])
        endpoint=context.decode().strip();require(local_context(endpoint) and Path(endpoint[7:]).is_socket(),'local unix Docker context')
        _,builder=run('builder',['buildx','inspect','desktop-linux']);require(builder_is_local(builder.decode()),'named local builder')
        for label,identifier in [('backend',BACKEND),('runtime',RUNTIME)]:
            _,raw=run('image-'+label,['image','inspect',identifier]);record=json.loads(raw)[0]
            require(record['Id']==identifier and record['Architecture']=='arm64' and record['Os']=='linux' and record['RepoTags'],'cached source image')
            original_tags[identifier]=record['RepoTags']
            code,_=run('unused-'+label,['image','inspect',aliases[label]],check=False);require(code!=0,'unused input alias')
            run('tag-'+label,['tag',identifier,aliases[label]]);owned_tags.append(aliases[label])
        _,before=run('containers-before',['ps','-aq','--no-trunc']);existing=before.decode().split()
        code,_=run('name-unused',['inspect',name],check=False);require(code!=0,'unused container name')
        code,_=run('tag-unused',['image','inspect',tag],check=False);require(code!=0,'unused output tag')
        build=output/'build';build.mkdir()
        recipe=f'''FROM {aliases['backend']} AS backend
FROM {aliases['runtime']}
USER 0
RUN adduser -D -H -h /state/home -u 1000 capturedfixture && mkdir -p /opt/artex /state && ln -sf /state/auth/jwt.key /opt/artex/jwt.key
COPY --from=backend --chown=1000:1000 /opt/artex/artex /opt/artex/artex
COPY --from=backend --chown=1000:1000 /opt/artex/skills/ /opt/artex/skills/
USER 1000:1000
LABEL com.nanonigit.artex.fixture={owner}
ENTRYPOINT ["/bin/sleep"]
CMD ["3600"]
'''
        (build/'Dockerfile').write_text(recipe);stage='build';print('captured_reference_stage=build',flush=True)
        run('build',['buildx','build','--builder','desktop-linux','--load','--platform','linux/arm64','--pull=false','--network','none','-t',tag,str(build)],timeout=180)
        _,raw=run('built-image',['image','inspect',tag]);record=json.loads(raw)[0];image=record['Id']
        require(record['Config']['Labels'].get('com.nanonigit.artex.fixture')==owner,'built image owner')
        stage='create';_,raw=run('create',create_arguments(name,owner,tag));container=raw.decode().strip()
        require(re.fullmatch('[0-9a-f]{64}',container),'created container id');run('start',['start',container])
        require(isolated(inspect_owned('isolation-start')),'initial isolation')
        stage='install';bundle={key:base64.b64encode(path.read_bytes()).decode() for key,path in sources().items()}
        run('install',['exec','-i',container,'python3','-c',INSTALL],data=json.dumps(bundle).encode())
        stage='database';run('setup',['exec',container,'python3','-c',SETUP],timeout=120)
        stage='exercise';print('captured_reference_stage=exercise',flush=True)
        _,raw=run('exercise',['exec',container,'python3','-c',EXECUTE],timeout=240)
        result=json.loads(raw)
        require(result['passed'] and result['recordedExchanges']==29 and result['backendStarts']==result['cooperativeStops']==2
                and result['persistence'] and result['credentialsAbsent'] and not result['uiAcceptance'] and not result['nativeComparison'],'exercise proof')
        require(isolated(inspect_owned('isolation-end')),'final isolation')
        (output/'reference-result.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
        summary.update(exercise_passed=True,implementation_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),source_hashes={key:hashlib.sha256(path.read_bytes()).hexdigest() for key,path in sources().items()})
    except BaseException as error:
        summary['failure']=dict(stage=stage,type=type(error).__name__)
    finally:
        try:
            record=inspect_owned('cleanup-owner')
            if record:
                for label,code in [('database',DUMP),('logs',EXPORT_LOGS),('executed-lines',"import pathlib,sys;data=pathlib.Path('/state/executed-lines.json').read_bytes();assert len(data)<=131072;sys.stdout.buffer.write(data)")]:
                    try:
                        _,data=run('export-'+label,['exec',record['Id'],'python3','-c',code],timeout=30)
                        summary['exports'][label]=dict(bytes=len(data),sha256=hashlib.sha256(data).hexdigest())
                    except BaseException as error:summary['exports'][label]=dict(failed=type(error).__name__)
                run('remove-container',['rm','-f',record['Id']])
            code,_=run('container-absent',['inspect',name],check=False);summary['cleanup']['container_removed']=code!=0
        except BaseException as error:summary['cleanup']['container_error']=type(error).__name__
        try:
            code,raw=run('cleanup-image-owner',['image','inspect',tag],check=False)
            if code==0:
                record=json.loads(raw)[0];require(record['Config']['Labels'].get('com.nanonigit.artex.fixture')==owner and (image is None or image==record['Id']),'cleanup image owner')
                run('remove-image-tag',['image','rm',tag])
            code,_=run('image-absent',['image','inspect',tag],check=False);summary['cleanup']['image_tag_removed']=code!=0
            for index,value in enumerate(owned_tags):run('remove-input-'+str(index),['image','rm',value])
            summary['cleanup']['input_tags_removed']=all(run('input-absent-'+str(index),['image','inspect',value],check=False)[0]!=0 for index,value in enumerate(owned_tags))
            preserved=True
            for index,(identifier,tags) in enumerate(original_tags.items()):
                _,raw=run('original-image-'+str(index),['image','inspect',identifier]);record=json.loads(raw)[0]
                preserved=preserved and record['Id']==identifier and set(tags)<=set(record['RepoTags'])
            summary['cleanup']['input_images_preserved']=preserved
            _,after=run('containers-after',['ps','-aq','--no-trunc']);summary['cleanup']['original_containers_preserved']=set(existing)<=set(after.decode().split())
        except BaseException as error:summary['cleanup']['image_error']=type(error).__name__
        summary['passed']=bool(summary['exercise_passed'] and len(summary['cleanup'])==5 and all(value is True for value in summary['cleanup'].values()) and set(summary['exports'])=={'database','logs','executed-lines'} and all('failed' not in value for value in summary['exports'].values()))
        (output/'harness-result.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary),flush=True)
    return summary


if __name__=='__main__':raise SystemExit(0 if main()['passed'] else 1)
