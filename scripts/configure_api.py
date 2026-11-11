"""Add the API location to the existing application server, preserving SSL/config."""
import argparse,os,subprocess,tempfile
from pathlib import Path

def configure(text,root,include):
 if include in text:return text
 result=[];inside=False;depth=0;block=[];changed=False
 for line in text.splitlines(keepends=True):
  if not inside and line.strip()=='server {':inside=True;depth=0;block=[]
  if inside:
   block.append(line);depth+=line.count('{')-line.count('}')
   if depth==0:
    content=''.join(block)
    if 'root '+root+';' in content:
     if 'location /api' in content or 'location ^~ /api' in content:raise ValueError('Já existe configuração /api manual. Confira antes de atualizar.')
     content=content.rsplit('}',1)[0]+'    include '+include+';\n}\n';changed=True
    result.append(content);inside=False
  else:result.append(line)
 if inside or not changed:raise ValueError('Não foi encontrado o server da aplicação no Nginx.')
 return ''.join(result)

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--app',default='/opt/apoiarcred');parser.add_argument('--conf',default='/etc/nginx/sites-available/apoiarcred-mvp.conf');parser.add_argument('--include',default='/etc/nginx/snippets/apoiarcred-api.conf');args=parser.parse_args()
 path=Path(args.conf);old=path.read_text();new=configure(old,args.app+'/dist',args.include)
 if new!=old:
  backup=path.with_suffix(path.suffix+'.before-api');backup.write_text(old);backup.chmod(0o600)
  path.write_text(new)
 try:subprocess.run(['nginx','-t'],check=True)
 except BaseException:
  path.write_text(old);raise
if __name__=='__main__':main()
