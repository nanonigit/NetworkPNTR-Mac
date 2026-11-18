#!/usr/bin/env python3
"""Verify terminal MCP task data against the pinned real backend/database, without host ports."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import time
from compare_backend import POSTGRES_IMAGE
from prepare_backend import BACKEND_IMAGE, SOURCE_COMMIT
from mcp_task_seed_guest import SQL

DOCKER = ['/usr/local/bin/docker', '--context', 'desktop-linux']
DOCKER_ENV = {k: v for k, v in os.environ.items() if not k.startswith(('DOCKER_', 'BUILDKIT_'))}


def docker_run(arguments, **kwargs):
    if not arguments or arguments[0] != 'docker':
        raise RuntimeError('Fixed Docker command required')
    kwargs.setdefault('env', DOCKER_ENV)
    return subprocess.run([*DOCKER, *arguments[1:]], **kwargs)


OWNER_LABEL = 'com.nanonigit.networkpntr.fixture-owner'
SNAPSHOT = "SELECT json_build_object('tasks',count(*),'explorations',(SELECT count(*) FROM explorations),'activity',(SELECT count(*) FROM activity),'profiles',(SELECT count(*) FROM llm_profiles),'usage',(SELECT count(*) FROM llm_usage),'activitySequence',(SELECT json_build_array(last_value,is_called) FROM activity_id_seq),'taskSequence',(SELECT json_build_array(last_value,is_called) FROM tasks_id_seq),'explorationSequence',(SELECT json_build_array(last_value,is_called) FROM explorations_id_seq)) FROM tasks;"
API = r'''
import json,os,secrets,time,urllib.request,urllib.error
base='http://127.0.0.1:8787'
def request(method,path,body=None,token=None):
    data=json.dumps(body).encode() if body is not None else None
    headers={'Content-Type':'application/json','Accept-Language':'en'}
    if token: headers['Authorization']='Bearer '+token
    with urllib.request.urlopen(urllib.request.Request(base+path,data=data,method=method,headers=headers),timeout=10) as r:
        return json.load(r)
if os.environ.get('NETWORKPNTR_REFERENCE_PHASE')=='ready':
    for _ in range(120):
        try:
            request('GET','/api/auth/status');break
        except (OSError,ValueError):time.sleep(.5)
    else:raise RuntimeError('reference readiness failed')
else:
    stage='auth_init'
    try:
        session=request('POST','/api/auth/init',{'password':secrets.token_hex(24),'setup_token':os.environ['ARTEX_SETUP_TOKEN']})
        stage='task_read'
        details=[request('GET','/api/tasks/'+id,token=session['token']) for id in ['7201','7202']]
        listing=request('GET','/api/tasks',token=session['token'])['tasks']
        tasks=[next(t for t in listing if t['id']==id) for id in ['7201','7202']]
        fields=['id','status','paused','queued','tokens']
        print(json.dumps({'tasks':[{k:t[k] for k in fields} for t in tasks],'detailTokens':[t['tokens'] for t in details]}))
    except urllib.error.HTTPError as error:
        print(json.dumps({'failure':stage,'status':error.code}))
'''


def cleanup_owned(identity, network, containers):
    issues = []
    for kind, name in [('container', n) for n in containers] + [('network', network)]:
        try:
            inspect = ['docker','inspect'] if kind=='container' else ['docker','network','inspect']
            template = '{{ index .Config.Labels "'+OWNER_LABEL+'" }}' if kind=='container' else '{{ index .Labels "'+OWNER_LABEL+'" }}'
            owner = docker_run([*inspect,'--format',template,name],capture_output=True,text=True,timeout=10)
            if owner.returncode==0 and owner.stdout.strip()==identity:
                remove = ['docker','rm','-f',name] if kind=='container' else ['docker','network','rm',name]
                docker_run(remove,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=30)
        except (OSError, subprocess.SubprocessError) as error:
            issues.append({'resource':kind,'operation':'remove','errorType':type(error).__name__})
    for kind, command in [('containers',['docker','ps','-a','--filter','label='+OWNER_LABEL+'='+identity,'--format','{{.Names}}']),
                          ('networks',['docker','network','ls','--filter','label='+OWNER_LABEL+'='+identity,'--format','{{.Name}}'])]:
        try:
            result = docker_run(command,capture_output=True,text=True,check=True,timeout=10)
            if result.stdout.strip():issues.append({'resource':kind,'operation':'absence','errorType':'OwnedResourcesRemain'})
        except (OSError, subprocess.SubprocessError) as error:
            issues.append({'resource':kind,'operation':'absence','errorType':type(error).__name__})
    return {'verified':not issues,'issues':issues}


def verify(output):
    output.mkdir(mode=0o700, parents=False)
    identity = 'networkpntr-mcp-task-' + secrets.token_hex(10)
    network, db, app = identity+'-net', identity+'-db', identity+'-app'
    environment = dict(DOCKER_ENV, POSTGRES_PASSWORD=secrets.token_hex(32), ARTEX_SETUP_TOKEN=secrets.token_hex(32))
    environment['ARTEX_PG_DSN'] = 'postgres://artex:'+environment['POSTGRES_PASSWORD']+'@postgres:5432/artex?sslmode=disable'
    phase = 'local_cached_preflight'
    receipt = None

    def require(condition):
        if not condition:
            raise RuntimeError('Pinned fixture assertion failed')

    def run(*args, **kwargs):
        return docker_run(list(args), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=120, **kwargs)

    def psql(sql, check=True):
        return docker_run(['docker','exec','-i',db,'psql','-X','-q','-t','-A','-U','artex','-d','artex','-v','ON_ERROR_STOP=1'],
                              input=sql.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check, timeout=30)

    def snapshot():
        return json.loads(psql(SNAPSHOT).stdout)

    try:
        context = docker_run(['docker','context','inspect','desktop-linux','--format','{{.Endpoints.docker.Host}}'],capture_output=True,text=True,check=True,timeout=10)
        require(context.stdout.strip() == 'unix://' + str(Path.home()/'.docker/run/docker.sock'))
        for image in [BACKEND_IMAGE, POSTGRES_IMAGE]:
            inspected = docker_run(['docker','image','inspect',image],capture_output=True,text=True,check=True,timeout=10)
            metadata = json.loads(inspected.stdout)[0]
            require(metadata['Os']=='linux' and metadata['Architecture']=='arm64')
            if image.startswith('sha256:'):
                require(metadata['Id']==image)
            else:
                require(any(d.endswith('@'+image.split('@')[1]) for d in metadata.get('RepoDigests',[])))
        phase = 'create'
        run('docker','network','create','--internal','--label',OWNER_LABEL+'='+identity,network)
        common = ['--label',OWNER_LABEL+'='+identity,'--network',network,'--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true']
        run('docker','run','--pull=never','-d','--name',db,*common,'--network-alias','postgres','--user','999:999',
            '--tmpfs','/var/lib/postgresql/data:rw,noexec,nosuid,nodev,size=512m,uid=999,gid=999,mode=700',
            '--tmpfs','/var/run/postgresql:rw,noexec,nosuid,nodev,size=16m,uid=999,gid=999','--tmpfs','/tmp:rw,noexec,nosuid,nodev,size=16m',
            '-e','POSTGRES_PASSWORD','-e','POSTGRES_USER=artex','-e','POSTGRES_DB=artex',POSTGRES_IMAGE,env=environment)
        phase = 'database_readiness'
        for _ in range(120):
            if docker_run(['docker','exec',db,'pg_isready','-U','artex','-d','artex'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=5).returncode==0:break
            time.sleep(.5)
        else:raise RuntimeError('reference database unavailable')
        run('docker','run','--pull=never','-d','--name',app,*common,'--user','1000:1000',
            '--tmpfs','/state:rw,nosuid,nodev,size=256m,uid=1000,gid=1000,mode=700','--tmpfs','/tmp:rw,noexec,nosuid,nodev,size=64m','--workdir','/tmp',
            '-e','ARTEX_PG_DSN','-e','ARTEX_SETUP_TOKEN','--entrypoint','/bin/sh',BACKEND_IMAGE,'-c',
            'mkdir -p /state/home /state/data; exec /opt/artex/artex -addr 127.0.0.1:8787 -data /state/data -proxy ""',env=environment)
        phase = 'backend_readiness'
        run('docker','exec','-i','-e','NETWORKPNTR_REFERENCE_PHASE=ready',app,'python3','-',input=API.encode())
        phase = 'forced_rollback'
        before = snapshot()
        require(psql(SQL.replace('COMMIT;','SELECT 1/0;\nCOMMIT;'),check=False).returncode != 0)
        require(snapshot() == before)
        phase = 'seed'
        psql(SQL)
        seeded = snapshot()
        require(seeded['tasks']==2 and seeded['profiles']==0 and seeded['usage']==0)
        phase = 'repeated_seed'
        require(psql(SQL,check=False).returncode != 0)
        require(snapshot() == seeded)
        phase = 'reload_persisted_tasks'
        run('docker','restart',app)
        run('docker','exec','-i','-e','NETWORKPNTR_REFERENCE_PHASE=ready',app,'python3','-',input=API.encode())
        phase = 'api_read'
        api = docker_run(['docker','exec','-i',app,'python3','-'],input=API.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True,timeout=45)
        reply = json.loads(api.stdout)
        if 'failure' in reply:
            (output/'api-failure.json').write_text(json.dumps(reply,indent=2)+'\n')
            raise RuntimeError('reference API rejected fixture request')
        (output/'api-observation.json').write_text(json.dumps(reply,indent=2)+'\n')
        reference = reply['tasks']
        require([t['id'] for t in reference]==['7201','7202'])
        require([t['status'] for t in reference]==['done','failed'])
        require(all(not t['paused'] and not t['queued'] for t in reference))
        require(reference[0]['tokens']['input_tokens']==4294967294 and reference[0]['tokens']['output_tokens']==13)
        require(reference[1]['tokens']['input_tokens']==17 and reference[1]['tokens']['output_tokens']==5)
        receipt = {'baseline':SOURCE_COMMIT,'backendImage':BACKEND_IMAGE,'sqlSHA256':hashlib.sha256(SQL.encode()).hexdigest(),
                   'forcedRollbackRowsAndSequencesUnchanged':True,'repeatedSeedRejectedWithoutMutation':True,
                   'before':before,'seeded':seeded,'taskProjection':reference,'detailTokens':reply['detailTokens'],'renderedBrowserComparison':'pending','existingBrowserDataModified':False,'cleanupVerified':False,'dockerContext':'desktop-linux','localUnixSocketVerified':True,'cachedExactImagesVerified':True,'affectedSequenceNames':['tasks_id_seq','explorations_id_seq','activity_id_seq']}
        (output/'schema-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    except Exception as error:
        try:
            (output/'failure.json').write_text(json.dumps({'phase':phase,'errorType':type(error).__name__},indent=2)+'\n')
        except OSError:
            pass
        raise RuntimeError('Pinned MCP task fixture failed at '+phase+' ('+type(error).__name__+')') from None
    finally:
        cleanup = cleanup_owned(identity, network, [app, db])
        try:
            (output/'cleanup.json').write_text(json.dumps(cleanup,indent=2)+'\n')
        except OSError as error:
            cleanup['verified'] = False
            cleanup['issues'].append({'resource':'receipt','operation':'write','errorType':type(error).__name__})
    if not cleanup['verified']:
        raise RuntimeError('Owned reference cleanup incomplete; inspect private cleanup report')
    if receipt is not None:
        receipt['cleanupVerified'] = True
        (output/'schema-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
        print('PASS pinned schema rollback, seed, repeat rejection, real task API Int64 aggregate and owned cleanup')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('new_private_output',type=Path)
    verify(parser.parse_args().new_private_output)
