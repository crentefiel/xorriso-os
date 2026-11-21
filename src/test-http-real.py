#!/usr/bin/env python3
"""Simulated OpenAI-compatible HTTP server, no internet needed."""
import json, os, pathlib, subprocess, tempfile, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
ROOT=pathlib.Path(__file__).resolve().parent.parent
class Handler(BaseHTTPRequestHandler):
    requests=[]
    def log_message(self,*args):pass
    def do_GET(self):
        content={'data':[{'id':'MiniCPM-V-4.7-1B'}]}
        b=json.dumps(content).encode()
        self.send_response(200);self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
    def do_POST(self):
        data=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert data['model']=='MiniCPM-V-4.7-1B'
        assert data['stream'] is False
        Handler.requests.append(data)
        system=data['messages'][0] if data['messages'][0]['role']=='system' else None
        if system and 'planejador' in system['content']:
            response=json.dumps({'action':'write_note','filename':'teste.txt','content':'Ola do agente','message':'teste'})
        else:
            assert system and 'portugues brasileiro' in system['content']
            response='Ola do servidor local!'
        b=json.dumps({'choices':[{'message':{'content':response}}]}).encode()
        self.send_response(200);self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
serv=ThreadingHTTPServer(('127.0.0.1',0),Handler)
thread=threading.Thread(target=serv.serve_forever,daemon=True);thread.start()
try:
    with tempfile.TemporaryDirectory() as tmp:
        c=pathlib.Path(tmp)/'conf';n=pathlib.Path(tmp)/'notas';c.mkdir();n.mkdir()
        (c/'api_url').write_text(f'http://127.0.0.1:{serv.server_port}/v1')
        (c/'api_model').write_text('MiniCPM-V-4.7-1B')
        env={**os.environ,'XORRISO_CONF_DIR':str(c),'XORRISO_NOTES_DIR':str(n),
             'XORRISO_CURL_BIN':'/usr/bin/curl','XORRISO_JQ_BIN':'/usr/bin/jq'}
        def run(cmd,stdin=None):
            p=subprocess.run(cmd,input=stdin,text=True,capture_output=True,env=env,timeout=15)
            if p.returncode:raise AssertionError((cmd,p.returncode,p.stdout,p.stderr))
            return p.stdout
        assert 'Ola do servidor local!' in run(['sh',str(ROOT/'src/ai-request.sh'),'Ola'])
        assert 'Ola do servidor local!' in run(['sh',str(ROOT/'src/ai-request.sh'),'Voce lembra?'])
        assert [m['role'] for m in Handler.requests[-1]['messages']] == ['system','user','assistant','user']
        assert Handler.requests[-1]['messages'][1]['content']=='Ola'
        assert Handler.requests[-1]['messages'][2]['content']=='Ola do servidor local!'
        assert '2' in run(['sh',str(ROOT/'src/ai-request.sh'),'--history-status'])
        assert 'MiniCPM-V-4.7-1B' in run(['sh',str(ROOT/'src/ai-request.sh'),'--test'])
        run(['sh',str(ROOT/'src/ai-agent.sh'),'criar uma nota de teste'],'s\n')
        assert (n/'teste.txt').read_text().strip()=='Ola do agente'
        print('PASSOU: HTTP local, prompt PT-BR, historico RAM, modelos e nota autorizada.')
finally:
    serv.shutdown();serv.server_close()
