"""Owned offline reference orchestration. No host mounts, external downloads or import side effects."""
import contextlib
import hashlib
import os
from pathlib import Path
import re
import stat


def compare_files(left, right, expected_size, expected_hash):
    if type(expected_size) is not int or not 0 <= expected_size <= 135266321 or re.fullmatch('[0-9a-f]{64}', expected_hash) is None:
        raise RuntimeError('Reference comparison expected identity failed')
    try:
        with contextlib.ExitStack() as stack:
            streams, stamps = [], []
            for path in (left, right):
                named = path.lstat()
                if not stat.S_ISREG(named.st_mode) or named.st_uid != os.getuid() or named.st_size != expected_size:
                    raise RuntimeError('Reference comparison regular file failed')
                fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
                try:
                    opened = os.fstat(fd)
                    if (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino):
                        raise RuntimeError('Reference comparison inode failed')
                    stream = os.fdopen(fd, 'rb')
                except BaseException:
                    os.close(fd)
                    raise
                streams.append(stack.enter_context(stream)); stamps.append(opened)
            digest, count = hashlib.sha256(), 0
            while True:
                first, second = (stream.read(65536) for stream in streams)
                if first != second or len(first) > expected_size - count:
                    raise RuntimeError('Reference comparison full bytes failed')
                if not first:
                    break
                digest.update(first); count += len(first)
            if count != expected_size or digest.hexdigest() != expected_hash:
                raise RuntimeError('Reference comparison full hash failed')
            for path, stream, before in zip((left, right), streams, stamps):
                after, named = os.fstat(stream.fileno()), path.lstat()
                if (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns) != (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns) or (named.st_dev, named.st_ino) != (before.st_dev, before.st_ino):
                    raise RuntimeError('Reference comparison file changed')
            return {'bytes': count, 'sha256': digest.hexdigest(), 'byte_equal': True}
    except OSError:
        raise RuntimeError('Reference comparison file read failed') from None


import textwrap

INSTALL = textwrap.dedent(r"""
    import base64,json,os,pathlib,sys
    bundle=json.load(sys.stdin)
    allowed={'evidence_export_reference.py','findings_seed_guest.py','findings_fixture_control.py','evidence_fixture_guest.py','check_network.py'}
    assert set(bundle)==allowed
    folder=pathlib.Path('/state/tools');folder.mkdir(mode=0o700)
    for name,value in bundle.items():
     data=base64.b64decode(value,validate=True);assert len(data)<=128*1024
     fd=os.open(folder/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
     with os.fdopen(fd,'wb') as stream:stream.write(data)
    print(json.dumps({'sources_installed':True,'uid':os.getuid()}))
""")

SETUP = textwrap.dedent(r"""
    import json,os,pathlib,secrets,subprocess
    root=pathlib.Path('/state')
    for name in ['app/data','auth','home','socket']: (root/name).mkdir(mode=0o700,parents=True)
    env={'PATH':'/usr/libexec/postgresql16:/usr/bin:/bin','PGHOST':'/state/socket','PGUSER':'postgres','PGDATABASE':'postgres','PGCONNECT_TIMEOUT':'2'}
    subprocess.run(['initdb','-D','/state/postgres','-U','postgres','--auth-local=trust','--auth-host=scram-sha-256'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=60)
    subprocess.run(['pg_ctl','-D','/state/postgres','-l','/state/postgres.log','-o','-h 127.0.0.1 -k /state/socket -c unix_socket_permissions=0700','-w','start'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=30)
    password=secrets.token_hex(32)
    sql="CREATE ROLE artex LOGIN PASSWORD '"+password+"';\nCREATE DATABASE artex OWNER artex;\n"
    subprocess.run(['psql','-X','--no-password','-v','ON_ERROR_STOP=1'],input=sql.encode(),env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=15)
    values={'ARTEX_PG_DSN':'postgres://artex:'+password+'@127.0.0.1:5432/artex?sslmode=disable','ARTEX_FINDINGS_FIXTURE':'1','ARTEX_DISPOSABLE_REFERENCE':'1','HOME':'/state/home'}
    fd=os.open('/state/environment.json',os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as stream:json.dump(values,stream)
    print(json.dumps({'postgres_started':True,'uid':os.getuid(),'external_network':False}))
""")

EXECUTE = textwrap.dedent(r"""
    import json,os,runpy,sys
    os.environ.update(json.load(open('/state/environment.json')))
    sys.path.insert(0,'/state/tools')
    import trace
    tracer=trace.Trace(count=True,trace=False)
    try:
     tracer.runfunc(runpy.run_path,'/state/tools/evidence_export_reference.py',run_name='__main__')
    finally:
     counts={}
     for (filename,line),count in tracer.results().counts.items():
      if filename.startswith('/state/tools/') and count:
       counts.setdefault(os.path.basename(filename),[]).append(line)
     with open('/state/executed-lines.json','w') as stream:json.dump({k:sorted(set(v)) for k,v in counts.items()},stream)
""")

DUMP = textwrap.dedent(r"""
        import json,os,subprocess,sys
        os.environ.update(json.load(open('/state/environment.json')));sys.path.insert(0,'/state/tools')
        from findings_seed_guest import validate_environment
        result=subprocess.run(['pg_dump','--no-password','-Fp'],env=validate_environment(),stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,timeout=20)
        assert result.returncode==0 and len(result.stdout)<=4*1024*1024
        sys.stdout.buffer.write(result.stdout)
        
""")

EXPORT = textwrap.dedent(r"""
    import json,pathlib,sys
    paths=['/state/postgres.log']+['/state/app/evidence-reference-'+str(i)+'.log' for i in [1,2]]
    values={}
    for name in paths:
     p=pathlib.Path(name)
     if p.exists():
      with p.open('rb') as stream:data=stream.read(4*1024*1024+1)
      assert len(data)<=4*1024*1024
      import base64;values[p.name]=base64.b64encode(data).decode()
    assert len(json.dumps(values))<=4*1024*1024
    print(json.dumps(values))
""")


def main():
    """Owned offline reference run; secrets remain inside the disposable container."""
    import base64
    import hashlib
    import json
    import re
    from pathlib import Path
    import subprocess
    import tempfile
    import uuid

    REPO = Path(__file__).resolve().parents[1]
    DOCKER = ['/usr/local/bin/docker', '--context', 'desktop-linux']
    BACKEND = 'sha256:46b3ce5d5f91cd05b9e3fd6834e33196be9626eb40d38e84b7fb398f00a172d0'
    RUNTIME = 'sha256:735d063ffd4290be40a870c4c77f6a6f9ad16ae306262e2e21e3865cd9c2b91d'
    EXPECTED = '0ebad83ddda276b03b415d64ce30af44e7a587860f3b660c12563462a0ac5e80'
    ROOT = Path(tempfile.mkdtemp(prefix='artex-evidence-reference-'))
    pointer=Path('/tmp/artex-evidence-reference-root.txt')
    previous=pointer.read_text().strip() if pointer.exists() else None
    (ROOT/'previous-root.json').write_text(json.dumps({'previous_root':previous})+'\n')
    pointer.write_text(str(ROOT)+'\n')
    (ROOT/'harness-inputs.json').write_text(json.dumps({'harness_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'repository_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()},indent=2)+'\n')
    OWNER = uuid.uuid4().hex
    NAME = 'artex-evidence-reference-'+OWNER[:12]
    TAG = 'artex-mac-evidence-reference:'+OWNER[:12]
    INPUT_TAGS = {'artex-mac-evidence-input-backend:'+OWNER[:12]:BACKEND,'artex-mac-evidence-input-runtime:'+OWNER[:12]:RUNTIME}
    original_tags = {}
    owned_tags = []
    container = image = None
    stage = 'preflight'
    summary = {'passed': False, 'exercise_passed': False, 'owner': OWNER, 'cleanup': {}, 'exports': {}}


    def require(value, message):
        if not value: raise RuntimeError('Reference harness '+message)


    def run(label, args, *, data=None, timeout=60, check=True, limit=4*1024*1024):
        result = subprocess.run(DOCKER+args, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        (ROOT/(label+'.stdout')).write_bytes(result.stdout); (ROOT/(label+'.stderr')).write_bytes(result.stderr)
        require(len(result.stdout) <= limit and len(result.stderr) <= limit, 'bounded '+label)
        if check: require(result.returncode == 0, label+' exit')
        return result


    def inspect_owned():
        result = run('owned-inspect', ['inspect', NAME], check=False)
        if result.returncode: return None
        record = json.loads(result.stdout)[0]
        require(record['Config']['Labels'].get('com.nanonigit.artex.fixture') == OWNER, 'ownership label')
        return record


    def isolation(record):
        host = record['HostConfig']
        return dict(networkMode=host['NetworkMode'], user=record['Config']['User'], readOnlyRootfs=host['ReadonlyRootfs'],
                    privileged=host['Privileged'], hostMounts=sum(m['Type'] in ('bind','volume') for m in record.get('Mounts', [])),
                    capDropAll='ALL' in (host.get('CapDrop') or []),
                    noNewPrivileges=any(s.startswith('no-new-privileges') for s in (host.get('SecurityOpt') or [])),
                    ports=len(host.get('PortBindings') or {}))


    try:
        print('reference_stage=preflight', flush=True)
        require(run('context', ['context','inspect','desktop-linux','--format','{{.Endpoints.docker.Host}}']).stdout.decode().strip().startswith('unix://'), 'local daemon')
        builder=run('builder',['buildx','inspect']).stdout.decode()
        require(re.search(r'^Driver:\s+docker$',builder,re.M) and re.findall(r'^Endpoint:\s+(\S+)',builder,re.M)==['desktop-linux'], 'local builder')
        for label,identifier in [('backend',BACKEND),('runtime',RUNTIME)]:
            record=json.loads(run(label+'-image',['image','inspect',identifier]).stdout)[0]
            require(record['Id']==identifier and record['Architecture']=='arm64' and record['Os']=='linux' and record['RepoTags'],'cached image')
            original_tags[identifier]=list(record['RepoTags'])
        for tag,identifier in INPUT_TAGS.items():
            require(run('input-tag-unused-'+str(len(owned_tags)),['image','inspect',tag],check=False).returncode != 0,'new input tag')
            run('input-tag-create-'+str(len(owned_tags)),['tag',identifier,tag]);owned_tags.append(tag)
            require(run('input-tag-verify-'+str(len(owned_tags)),['image','inspect',tag,'--format','{{.Id}}']).stdout.decode().strip()==identifier,'bound input tag')
        existing=run('existing-before',['ps','-aq','--no-trunc']).stdout.decode().split()
        require(run('name-unused',['inspect',NAME],check=False).returncode != 0,'new container name')
        backend_tag=next(t for t,i in INPUT_TAGS.items() if i==BACKEND)
        runtime_tag=next(t for t,i in INPUT_TAGS.items() if i==RUNTIME)
        recipe=f'''FROM {backend_tag} AS backend
    FROM {runtime_tag}
    USER 0
    RUN adduser -D -H -h /state/home -u 1000 evidencefixture && mkdir -p /opt/artex /state && ln -sf /state/auth/jwt.key /opt/artex/jwt.key
    COPY --from=backend --chown=1000:1000 /opt/artex/artex /opt/artex/artex
    COPY --from=backend --chown=1000:1000 /opt/artex/skills/ /opt/artex/skills/
    USER 1000:1000
    LABEL com.nanonigit.artex.fixture={OWNER}
    ENTRYPOINT ["/bin/sleep"]
    CMD ["3600"]
    '''
        build=ROOT/'build';build.mkdir();(build/'Dockerfile').write_text(recipe)
        stage='build';print('reference_stage=build',flush=True)
        run('build',['buildx','build','--builder','desktop-linux','--load','--platform','linux/arm64','--pull=false','--network=none','--tag',TAG,str(build)],timeout=180)
        image=run('built-id',['image','inspect',TAG,'--format','{{.Id}}']).stdout.decode().strip()
        stage='create';print('reference_stage=create',flush=True)
        result=run('run',['run','-d','--name',NAME,'--label','com.nanonigit.artex.fixture='+OWNER,'--network=none','--read-only','--cap-drop=ALL','--security-opt=no-new-privileges','--pids-limit=128','--memory=2g','--user=1000:1000',
                          '--tmpfs','/state:rw,nosuid,nodev,noexec,uid=1000,gid=1000,mode=0700,size=768m','--tmpfs','/tmp:rw,nosuid,nodev,noexec,uid=1000,gid=1000,mode=1777,size=64m',TAG],timeout=30)
        container=result.stdout.decode().strip();require(len(container)==64 and all(c in '0123456789abcdef' for c in container),'container ID')
        record=inspect_owned();guard=isolation(record)
        require(guard==dict(networkMode='none',user='1000:1000',readOnlyRootfs=True,privileged=False,hostMounts=0,capDropAll=True,noNewPrivileges=True,ports=0),'runtime isolation')
        actual=run('binary-hash',['exec',container,'sha256sum','/opt/artex/artex']).stdout.decode().split()[0];require(actual==EXPECTED,'backend binary hash')
        names=['evidence_export_reference.py','findings_seed_guest.py','findings_fixture_control.py','evidence_fixture_guest.py']
        sources={name:REPO/'script'/name for name in names};sources['check_network.py']=REPO/'guest/check_network.py'
        bundle={name:base64.b64encode(path.read_bytes()).decode() for name,path in sources.items()}
        run('install',['exec','-i',container,'python3','-c',INSTALL],data=json.dumps(bundle).encode())
        stage='database';print('reference_stage=database',flush=True)
        run('database',['exec',container,'python3','-c',SETUP],timeout=120)
        stage='exercise';print('reference_stage=exercise',flush=True)
        exercise=run('exercise',['exec',container,'python3','-c',EXECUTE],timeout=300)
        reference=json.loads(exercise.stdout);reference['hostIsolation']=guard
        native=json.loads((REPO/'evidence/findings/evidence-export-native.json').read_text())
        native_workspace=Path(Path('/tmp/artex-evidence-vm-workspace.txt').read_text().strip())
        native_private=json.loads((native_workspace/'inputs.json').read_text())
        require(native['observedExitCode']==0 and native['report']['nativeProbePassed'] and native_private['nativeHead']==native['nativeHead'] and native_private['probeSHA256']==native['nativeBinarySHA256'],'native executed identity')
        require(reference['passed'] and reference['backendSHA256']==native['artifactHashes']['backendSHA256']==EXPECTED and reference['sourceCommit']==native['baselineCommit'],'native backend/source binding')
        for name in ['findings_seed_guest.py','findings_fixture_control.py','evidence_fixture_guest.py']:
            require(reference['sourceSHA256'][name]==native['inputSourceSHA256']['script/'+name]==hashlib.sha256(sources[name].read_bytes()).hexdigest(),'native fixture binding')
        require(reference['sourceSHA256']['evidence_export_reference.py']==hashlib.sha256(sources['evidence_export_reference.py'].read_bytes()).hexdigest(),'reference source binding')
        require(reference['networkCheckerSHA256']==hashlib.sha256(sources['check_network.py'].read_bytes()).hexdigest(),'network checker binding')
        require(reference['backendStarts']==reference['cooperativeStops']==2 and reference['credentialsAbsent'] and len(reference['downloads'])==2,'reference terminal proof')
        run('copy-responses',['cp',container+':/state/evidence-downloads',str(ROOT/'reference-downloads')],timeout=120)
        copied=ROOT/'reference-downloads'
        require(not copied.is_symlink() and copied.is_dir() and sorted(p.name for p in copied.iterdir())==['boot-1','boot-2'],'export roots')
        comparisons=[]
        mapping={'literal':'17001-request.bin','binary':'17001-response.bin','empty':'17002-request.bin','large':'17002-response.bin'}
        for index in [1,2]:
            folder=copied/('boot-'+str(index))
            require(not folder.is_symlink() and folder.is_dir() and sorted(p.name for p in folder.iterdir())==sorted(name+'.bin' for name in mapping),'export exact paths')
            native_files={f['body']:f for f in native['report']['boots'][index-1]['files']}
            rows=reference['downloads'][index-1]
            require(len(rows)==4 and set(f['body'] for f in rows)==set(mapping),'reference body set')
            for result in rows:
                name=result['body'];expected=native_files[name]
                require(result['full_byte_equal'] and result['bytes']==expected['byteCount'] and result['sha256']==expected['sha256'],'native response metadata')
                comparison=compare_files(native_workspace/'run'/('downloads-'+str(index))/mapping[name],folder/(name+'.bin'),expected['byteCount'],expected['sha256'])
                comparisons.append(dict(comparison,body=name,boot=index))
        require(len(comparisons)==8,'full byte pairs')
        reference['nativeByteComparisons']=comparisons
        reference['nativeHead']=native['nativeHead']
        summary['source_bindings_verified']=True
        require(isolation(inspect_owned())==guard,'end isolation')
        (ROOT/'reference-result.json').write_text(json.dumps(reference,indent=2,ensure_ascii=False)+'\n')
        summary.update(exercise_passed=True,container=container,image=image,implementation_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip(),source_hashes={name:hashlib.sha256(path.read_bytes()).hexdigest() for name,path in sources.items()})
    except BaseException as error:
        summary['failure']={'stage':stage,'type':type(error).__name__}
    finally:
        try:
            owned=inspect_owned()
            if owned is not None:
                container=owned['Id']
                for label,code in [('database-dump',DUMP),('retained-logs',EXPORT),('executed-lines',"import pathlib,sys;data=pathlib.Path('/state/executed-lines.json').read_bytes();assert len(data)<=131072;sys.stdout.buffer.write(data)")]:
                    try:
                        result=run(label,['exec',container,'python3','-c',code],timeout=30)
                        summary['exports'][label]={'bytes':len(result.stdout),'sha256':hashlib.sha256(result.stdout).hexdigest()}
                    except BaseException as error: summary['exports'][label]={'error':type(error).__name__}
                try:
                    run('postgres-stop',['exec',container,'/usr/libexec/postgresql16/pg_ctl','-D','/state/postgres','-m','fast','-w','stop'],timeout=25,check=False)
                except BaseException: pass
                if all('bytes' in summary['exports'].get(key,{}) for key in ['database-dump','retained-logs']):
                    result=run('remove',['rm','-f',container],timeout=30,check=False)
                    summary['cleanup']['container_removed']=result.returncode==0
                else:
                    summary['cleanup']['container_retained_for_export']=True
        except BaseException as error: summary['cleanup']['error']=type(error).__name__
        if image:
            try:
                current=run('tag-current',['image','inspect',TAG,'--format','{{.Id}}'],check=False).stdout.decode().strip()
                if current==image:
                    summary['cleanup']['image_tag_removed']=run('untag',['image','rm',TAG],check=False).returncode==0
            except BaseException as error: summary['cleanup']['image_error']=type(error).__name__
        input_tags_removed = True; parents_preserved = True
        for tag in owned_tags:
            identifier=INPUT_TAGS[tag]
            try:
                # Never remove the last tag of an original input image.
                for original in original_tags[identifier]:
                    require(run('original-tag-'+hashlib.sha256(original.encode()).hexdigest()[:8],['image','inspect',original,'--format','{{.Id}}']).stdout.decode().strip()==identifier,'original tag preservation')
                current=run('alias-current-'+hashlib.sha256(tag.encode()).hexdigest()[:8],['image','inspect',tag,'--format','{{.Id}}']).stdout.decode().strip()
                require(current==identifier,'owned input alias')
                require(run('alias-remove-'+hashlib.sha256(tag.encode()).hexdigest()[:8],['image','rm',tag],check=False).returncode==0,'input alias cleanup')
                require(run('parent-preserved-'+identifier[7:15],['image','inspect',identifier,'--format','{{.Id}}']).stdout.decode().strip()==identifier,'input image preservation')
            except BaseException:
                input_tags_removed=False;parents_preserved=False
        summary['cleanup']['input_tags_removed']=input_tags_removed and len(owned_tags)==2
        summary['cleanup']['input_images_preserved']=parents_preserved and len(original_tags)==2
        try:
            after=run('existing-after',['ps','-aq','--no-trunc']).stdout.decode().split()
            summary['cleanup']['original_containers_preserved']=set(existing)<=set(after)
        except BaseException: summary['cleanup']['original_containers_preserved']=False
        exports_complete=all('bytes' in summary['exports'].get(k,{}) for k in ['database-dump','retained-logs'])
        cleanup=summary['cleanup']
        summary['passed']=summary['exercise_passed'] and summary.get('source_bindings_verified') is True and exports_complete and all(cleanup.get(k) is True for k in ['container_removed','image_tag_removed','input_tags_removed','input_images_preserved','original_containers_preserved'])
        if (ROOT/'reference-result.json').exists():
            result=json.loads((ROOT/'reference-result.json').read_text())
            result['harness']=dict(complete=summary['passed'],exportsComplete=exports_complete,
                originalContainersPreserved=cleanup.get('original_containers_preserved',False),inputImagesPreserved=cleanup.get('input_images_preserved',False),
                containerRemoved=cleanup.get('container_removed',False),imageTagRemoved=cleanup.get('image_tag_removed',False),inputTagsRemoved=cleanup.get('input_tags_removed',False))
            (ROOT/'reference-result.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
        (ROOT/'harness-result.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps({'reference_root':str(ROOT),'passed':summary['passed'],'failure':summary.get('failure'),'cleanup':summary['cleanup']}))
    raise SystemExit(0 if summary['passed'] else 1)


if __name__ == '__main__':
    main()
