/*
 * xorriso Alpha 0.15 - Linux init minimo
 * SPDX-License-Identifier: MIT
 * Plain Linux console is empty until user calls F1 or F2.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/reboot.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/reboot.h>
#include <sys/sysinfo.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <ctype.h>
#include <dirent.h>

#define MAX_CMD 767
static struct termios original, raw;
static int tty_fd = -1;
static int is_console = 0;
static int is_chat = 0;
static char shown_ai_state[192]={0};

static void print(const char *s) { if(s) (void)write(STDOUT_FILENO,s,strlen(s)); }
static void crlf(void) { print("\r\n"); }
static void clear_screen(void) { print("\033[0m\033[2J\033[H\033[?25l"); }

static void setup_fs(void) {
 (void)mount("proc","/proc","proc",MS_NOSUID|MS_NODEV|MS_NOEXEC,"");
 (void)mount("sysfs","/sys","sysfs",MS_NOSUID|MS_NODEV|MS_NOEXEC,"");
 (void)mount("devtmpfs","/dev","devtmpfs",MS_NOSUID,"mode=0755");
 (void)mount("tmpfs","/run","tmpfs",MS_NOSUID|MS_NODEV,"size=160M,mode=0755");
 (void)mount("tmpfs","/tmp","tmpfs",MS_NOSUID|MS_NODEV,"size=32M,mode=1777");
}
static void setup_tty(void) {
 int fd=open("/dev/tty0",O_RDWR|O_NOCTTY);
 if(fd<0) fd=open("/dev/console",O_RDWR|O_NOCTTY);
 if(fd>=0) {
  (void)dup2(fd,STDIN_FILENO);(void)dup2(fd,STDOUT_FILENO);(void)dup2(fd,STDERR_FILENO);
  if(fd>STDERR_FILENO)close(fd);
 }
 tty_fd=STDIN_FILENO;
 if(tcgetattr(tty_fd,&original)==0) {
  raw=original;cfmakeraw(&raw);raw.c_oflag|=OPOST;
  (void)tcsetattr(tty_fd,TCSANOW,&raw);
 }
}
static void status(void) {
 struct utsname uts;struct sysinfo sys;
 clear_screen();
 print("xorriso alpha 0.15 - Linux minimo\r\n\r\n");
 if(uname(&uts)==0) {print("Linux kernel: ");print(uts.release);crlf();}
 if(sysinfo(&sys)==0) {
  char buf[128];
  unsigned long long mb=((unsigned long long)sys.totalram*sys.mem_unit)/(1024*1024);
  snprintf(buf,sizeof(buf),"RAM: %llu MiB\r\n",mb);print(buf);
 }
 print("\r\nF2: console | F3: conversa | ESC: area vazia\r\n");
 print("MiniCPM: model status | runtime status (motor opcional em VDI).\r\n");
 is_console=0;is_chat=0;
}
static void console_header(void) {
 clear_screen();
 print("xorriso alpha 0.15 - console minimo\r\n");
 print("help: comandos | ESC: tela vazia\r\n\r\n");
 is_console=1;is_chat=0;
}
static int read_key(void) {
 unsigned char ch;
 struct pollfd pending={.fd=STDIN_FILENO,.events=POLLIN};
 if(poll(&pending,1,350)<=0)return -1;
 if(read(STDIN_FILENO,&ch,1)!=1) return -1;
 if(ch!=27) return (int)ch;
 char seq[10]={0};int n=0;
 while(n<9) {
  struct pollfd p={.fd=STDIN_FILENO,.events=POLLIN};
  if(poll(&p,1,75)<=0)break;
  if(read(STDIN_FILENO,&seq[n],1)!=1)break;
  n++;
  if(seq[n-1]=='~'||seq[n-1]=='A'||seq[n-1]=='B'||seq[n-1]=='P'||seq[n-1]=='Q'||seq[n-1]=='C'||seq[n-1]=='R')break;
 }
 if(!strcmp(seq,"[[A")||!strcmp(seq,"OP")||!strcmp(seq,"[11~"))return 0x1001;
 if(!strcmp(seq,"[[B")||!strcmp(seq,"OQ")||!strcmp(seq,"[12~"))return 0x1002;
 if(!strcmp(seq,"[[C")||!strcmp(seq,"OR")||!strcmp(seq,"[13~"))return 0x1003;
 return 27;
}
static void write_runtime(const char *name,const char *data) {
 char path[128];snprintf(path,sizeof(path),"/run/xorriso/%s",name);
 int fd=open(path,O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC,0600);
 if(fd<0){print("Erro ao salvar configuracao na RAM.\r\n");return;}
 (void)write(fd,data,strlen(data));close(fd);
}
static void read_runtime(const char *name,char *dst,size_t cap) {
 char path[128];snprintf(path,sizeof(path),"/run/xorriso/%s",name);
 int fd=open(path,O_RDONLY|O_CLOEXEC);dst[0]=0;
 if(fd<0)return;
 ssize_t n=read(fd,dst,cap-1);
 if(n>0){dst[n]=0;dst[strcspn(dst,"\r\n")]=0;}close(fd);
}
static void run_script(const char *script,const char *argument) {
 print("\033[?25h\r\n");
 (void)tcsetattr(tty_fd,TCSANOW,&original);
 pid_t pid=fork();
 if(pid==0) {
  setenv("PATH","/bin:/usr/bin:/sbin",1);setenv("TERM","linux",1);
  execl("/bin/sh","sh",script,argument?argument:"",(char*)NULL);_exit(127);
 }
 if(pid>0) {int st=0;while(waitpid(pid,&st,0)<0&&errno==EINTR){}}
 (void)tcsetattr(tty_fd,TCSANOW,&raw);crlf();
}
static void api_key_entry(void) {
 char secret[512];size_t n=0;int key;
 print("Chave de API (nao exibida): ");
 while((key=read_key())!=-2) {
  if(key<0)continue;
  if(key=='\n'||key=='\r')break;
  if(key==27){n=0;break;}
  if(key==127||key=='\b'){if(n)n--;continue;}
  if(key>31&&key<127&&n<sizeof(secret)-1)secret[n++]=(char)key;
 }
 secret[n]=0;crlf();
 if(n){write_runtime("api_key",secret);print("Chave temporaria armazenada na RAM.\r\n");}
 else print("Chave nao alterada.\r\n");
 memset(secret,0,sizeof(secret));
}
static void api_show(void) {
 char url[512],model[256],key[512];
 read_runtime("api_url",url,sizeof(url));
 read_runtime("api_model",model,sizeof(model));
 read_runtime("api_key",key,sizeof(key));
 print("URL: ");print(*url?url:"(ausente)");crlf();
 print("Modelo: ");print(*model?model:"(ausente)");crlf();
 print("Chave: ");print(*key?"configurada (oculta)":"ausente");crlf();
 memset(key,0,sizeof(key));
}
static void api_command(const char *args) {
 if(!*args||!strcmp(args,"help")){
  print("api show | api local | api host | api url https://host/v1 | api model ID | api key | api test\r\n");return;
 }
 if(!strcmp(args,"host")) {
  (void)unlink("/run/xorriso/chat-history.json");
  write_runtime("api_url","http://10.0.2.2:8080/v1");
  write_runtime("api_model","MiniCPM-V-4.7-1B");
  (void)unlink("/run/xorriso/api_key");
  (void)unlink("/run/xorriso/api-auth-header");
  print("MiniCPM no computador anfitriao (NAT): 10.0.2.2:8080.\r\n");
  print("Nao e inferencia dentro da VM. Nao envie chaves por HTTP.\r\n");
  return;
 }
 if(!strcmp(args,"local")) {
  (void)unlink("/run/xorriso/chat-history.json");
  write_runtime("api_url","http://127.0.0.1:8080/v1");
  write_runtime("api_model","MiniCPM-V-4.7-1B");
  (void)unlink("/run/xorriso/api_key");
  print("IA local selecionada: 127.0.0.1:8080. Use runtime status.\r\n");return;
 }
 if(!strcmp(args,"show")){api_show();return;}
 if(!strcmp(args,"key")){
  char base[400];read_runtime("api_url",base,sizeof(base));
  if(!strncmp(base,"http://10.0.2.2:",16)) {
   print("Chave proibida no HTTP do host virtual. Use HTTPS.\r\n");
   return;
  }
  api_key_entry();return;
 }
 if(!strcmp(args,"test")){run_script("/usr/lib/xorriso/ai-request.sh","--test");return;}
 if(!strncmp(args,"url ",4)){
  const char *v=args+4;
  if(strncmp(v,"https://",8)&&strncmp(v,"http://127.0.0.1:",17)&&strncmp(v,"http://localhost:",17)&&strncmp(v,"http://10.0.2.2:",16)){
   print("Use HTTPS ou HTTP em localhost.\r\n");return;
  }
  if(strlen(v)>360||strchr(v,' ')||strchr(v,'?')||strchr(v,'#')){
   print("URL invalida.\r\n");return;
  }
  char tmp[400];snprintf(tmp,sizeof(tmp),"%s",v);
  size_t n=strlen(tmp);while(n&&tmp[n-1]=='/')tmp[--n]=0;
  write_runtime("api_url",tmp);(void)unlink("/run/xorriso/chat-history.json");print("URL definida.\r\n");return;
 }
 if(!strncmp(args,"model ",6)){
  const char *v=args+6;
  if(!*v||strlen(v)>190){print("Modelo invalido.\r\n");return;}
  write_runtime("api_model",v);(void)unlink("/run/xorriso/chat-history.json");print("Modelo definido.\r\n");return;
 }
 print("Comando de API desconhecido.\r\n");
}
static void shell(void) {
 print("\033[?25h\r\nAbrindo BusyBox shell (exit para voltar).\r\n");
 (void)tcsetattr(tty_fd,TCSANOW,&original);
 pid_t pid=fork();
 if(pid==0) {
  setenv("PATH","/bin:/usr/bin:/sbin",1);setenv("TERM","linux",1);
  execl("/bin/sh","sh","-i",(char*)NULL);_exit(127);
 }
 if(pid>0)while(waitpid(pid,NULL,0)<0&&errno==EINTR){}
 (void)tcsetattr(tty_fd,TCSANOW,&raw);
 console_header();
}
/* Minimal full-screen text chat, invoked only on F3 or "chat open".
 * No icons, permanent shell, or background UI are created. */
static void chat_screen(void) {
 clear_screen();
 is_console=0;is_chat=1;
 print("\033[?25h");
 print("xorriso  |  IA PESSOAL\r\n");
 print("------------------------------------------------------------\r\n");
 print("F2 console  |  Esc tela vazia  |  F3 abrir conversa\r\n");
 print("Enter envia  |  /clear limpa  |  /last anterior\r\n");
 print("/status mostra historico  |  /exit fecha\r\n");
 print("Historico temporario em RAM. Nenhum texto sera salvo no VDI.\r\n");
 char state[192];read_runtime("boot-status",state,sizeof(state));
 if(!*state)snprintf(state,sizeof(state),"preparando");
 snprintf(shown_ai_state,sizeof(shown_ai_state),"%s",state);
 print("IA local: ");print(state);crlf();
 print("Digite o que deseja. Microfone sera integrado em versao futura.\r\n");
 print("------------------------------------------------------------\r\n\r\n");
}
static void chat_input(char *s) {
 while(isspace((unsigned char)*s))s++;
 size_t n=strlen(s);
 while(n&&isspace((unsigned char)s[n-1]))s[--n]=0;
 if(!*s)return;
 if(!strcmp(s,"/exit")) {is_chat=0;clear_screen();return;}
 if(!strcmp(s,"/clear")) {run_script("/usr/lib/xorriso/ai-request.sh","--clear");return;}
 if(!strcmp(s,"/last")) {run_script("/usr/lib/xorriso/ai-request.sh","--history-last");return;}
 if(!strcmp(s,"/status")) {run_script("/usr/lib/xorriso/ai-request.sh","--history-status");return;}
 if(!strcmp(s,"/ready")) {run_script("/usr/lib/xorriso/ai-boot.sh","status");return;}
 if(s[0]=='/') {
  print("Comandos: /last /status /clear /ready /exit\r\n");
  return;
 }
 if(!strncasecmp(s,"crie uma pasta chamada ",strlen("crie uma pasta chamada "))||
    !strncasecmp(s,"criar uma pasta chamada ",strlen("criar uma pasta chamada "))||
    !strncasecmp(s,"quero criar uma pasta chamada ",strlen("quero criar uma pasta chamada "))||
    !strncasecmp(s,"crie a pasta ",strlen("crie a pasta "))||
    !strcasecmp(s,"liste minhas pastas")||
    !strcasecmp(s,"mostre minhas pastas")) {
   print("Acao do xorriso:\r\n");
   run_script("/usr/lib/xorriso/actions.sh",s);
   return;
 }
 print("IA xorriso:");
 run_script("/usr/lib/xorriso/ai-request.sh",s);
}

static void list_root(void) {
 DIR *d=opendir("/");
 if(!d){print("Falha em /\r\n");return;}
 struct dirent *e;
 while((e=readdir(d))!=NULL) {
  if(!strcmp(e->d_name,".")||!strcmp(e->d_name,".."))continue;
  print(e->d_name);print("  ");
 }
 crlf();closedir(d);
}
static void cmd(char *s) {
 while(isspace((unsigned char)*s))s++;
 size_t n=strlen(s);
 while(n&&isspace((unsigned char)s[n-1]))s[--n]=0;
 if(!*s)return;
 if(!strcmp(s,"help"))print("help status ls uptime shell net api ask agent action notes storage model runtime chat local ai desktop reboot poweroff (F3: conversa)\r\n");
 else if(!strcmp(s,"status")||!strcmp(s,"version")){status();is_console=1;}
 else if(!strcmp(s,"ls"))list_root();
 else if(!strcmp(s,"uptime")){
  struct sysinfo si;char b[128];
  if(!sysinfo(&si)){snprintf(b,sizeof(b),"Uptime: %ld s\r\n",si.uptime);print(b);}
 }
 else if(!strcmp(s,"shell"))shell();
 else if(!strcmp(s,"desktop")||!strcmp(s,"clear")){is_console=0;is_chat=0;clear_screen();}
 else if(!strcmp(s,"ai status"))run_script("/usr/lib/xorriso/ai-boot.sh","status");
 else if(!strcmp(s,"ai")||!strcmp(s,"ai local")){
  print("MiniCPM automatico: ai status | runtime status.\r\n");
  print("Motor e pesos ficam em VDIs externos.\r\n");
 }
 else if(!strcmp(s,"local")||!strcmp(s,"local status"))run_script("/usr/lib/xorriso/local.sh","status");
 else if(!strcmp(s,"local help"))run_script("/usr/lib/xorriso/local.sh","help");
 else if(!strcmp(s,"net")||!strcmp(s,"net status"))run_script("/usr/lib/xorriso/network.sh","status");
 else if(!strcmp(s,"net up"))run_script("/usr/lib/xorriso/network.sh","up");
 else if(!strcmp(s,"net down"))run_script("/usr/lib/xorriso/network.sh","down");
 else if(!strncmp(s,"api",3)&&(s[3]==' '||!s[3]))api_command(s[3]==' '?s+4:"");
 else if(!strcmp(s,"chat open"))chat_screen();
 else if(!strcmp(s,"chat")||!strcmp(s,"chat status"))run_script("/usr/lib/xorriso/ai-request.sh","--history-status");
 else if(!strcmp(s,"chat last"))run_script("/usr/lib/xorriso/ai-request.sh","--history-last");
 else if(!strcmp(s,"chat clear"))run_script("/usr/lib/xorriso/ai-request.sh","--clear");
 else if(!strncmp(s,"chat ",5))print("Uso: chat open | chat status | chat last | chat clear\r\n");
 else if(!strncmp(s,"ask ",4))run_script("/usr/lib/xorriso/ai-request.sh",s+4);
 else if(!strcmp(s,"ask"))print("Uso: ask sua pergunta\r\n");
 else if(!strncmp(s,"action ",7))run_script("/usr/lib/xorriso/actions.sh",s+7);
 else if(!strncmp(s,"agent ",6))run_script("/usr/lib/xorriso/ai-agent.sh",s+6);
 else if(!strcmp(s,"agent"))print("Uso: agent seu pedido\r\n");
 else if(!strcmp(s,"notes"))run_script("/usr/lib/xorriso/ai-agent.sh","--notes");
 else if(!strcmp(s,"runtime")||!strcmp(s,"runtime status"))run_script("/usr/lib/xorriso/runtime.sh","status");
 else if(!strcmp(s,"runtime start"))run_script("/usr/lib/xorriso/runtime.sh","start");
 else if(!strcmp(s,"runtime stop"))run_script("/usr/lib/xorriso/runtime.sh","stop");
 else if(!strcmp(s,"runtime log"))run_script("/usr/lib/xorriso/runtime.sh","log");
 else if(!strcmp(s,"runtime help"))run_script("/usr/lib/xorriso/runtime.sh","help");
 else if(!strncmp(s,"runtime ",8))print("Uso: runtime status | runtime start | runtime stop | runtime log\r\n");
 else if(!strcmp(s,"model")||!strcmp(s,"model status"))run_script("/usr/lib/xorriso/model.sh","status");
 else if(!strcmp(s,"model install"))run_script("/usr/lib/xorriso/model.sh","install");
 else if(!strcmp(s,"model vision"))run_script("/usr/lib/xorriso/model.sh","vision");
 else if(!strcmp(s,"model verify"))run_script("/usr/lib/xorriso/model.sh","verify");
 else if(!strcmp(s,"model help"))run_script("/usr/lib/xorriso/model.sh","help");
 else if(!strncmp(s,"model ",6))print("Uso: model status | model install | model vision | model verify\r\n");
 else if(!strcmp(s,"storage")||!strcmp(s,"storage status"))run_script("/usr/lib/xorriso/storage.sh","status");
 else if(!strcmp(s,"storage mount"))run_script("/usr/lib/xorriso/storage.sh","mount");
 else if(!strcmp(s,"storage probe"))run_script("/usr/lib/xorriso/storage.sh","probe");
 else if(!strncmp(s,"storage ",8))print("Uso: storage status | storage mount | storage probe\r\n");
 else if(!strncmp(s,"install",7))print("Instalacao automatica de programas indisponivel nesta alpha.\r\n");
 else if(!strcmp(s,"reboot")){sync();reboot(LINUX_REBOOT_CMD_RESTART);}
 else if(!strcmp(s,"poweroff")){sync();reboot(LINUX_REBOOT_CMD_POWER_OFF);}
 else print("Comando desconhecido. Digite help.\r\n");
}
/* CI-only guest test of NAT connectivity to a simulated OpenAI-compatible host API. */
static int ci_exec_script(const char *path,const char *arg) {
 pid_t child=fork();
 if(child<0)return 127;
 if(child==0) {
  setenv("PATH","/bin:/usr/bin:/sbin",1);
  execl("/bin/sh","sh",path,arg,(char *)NULL);_exit(127);
 }
 int status=0;
 while(waitpid(child,&status,0)<0) {if(errno!=EINTR)return 127;}
 return WIFEXITED(status)?WEXITSTATUS(status):127;
}
static void ci_host_bridge_test(void) {
 char args[4096]={0};
 int f=open("/proc/cmdline",O_RDONLY|O_CLOEXEC);
 if(f<0)return;
 ssize_t n=read(f,args,sizeof(args)-1);close(f);
 if(n<=0||!strstr(args,"xorriso.ci=hostapi"))return;
 int serial=open("/dev/ttyS0",O_RDWR|O_NOCTTY);
 if(serial>=0) {
  (void)dup2(serial,STDOUT_FILENO);(void)dup2(serial,STDERR_FILENO);
  if(serial>STDERR_FILENO)close(serial);
 }
 print("xorriso CI: attempting DHCP and host-model API bridge\n");
 write_runtime("api_url","http://10.0.2.2:8080/v1");
 write_runtime("api_model","MiniCPM-V-4.7-1B");
 int net=ci_exec_script("/usr/lib/xorriso/network.sh","up");
 int api=net==0?ci_exec_script("/usr/lib/xorriso/ai-request.sh","Teste de rede do xorriso"):127;
 if(net==0&&api==0)print("xorriso: host api bridge PASS\n");
 else print("xorriso: host api bridge FAIL\n");
 for(;;)pause();
}
static void ci_persistent_test(void) {
 char args[4096]={0};
 int f=open("/proc/cmdline",O_RDONLY|O_CLOEXEC);
 if(f<0)return;
 ssize_t n=read(f,args,sizeof(args)-1);close(f);
 if(n<=0)return;
 int iswrite=strstr(args,"xorriso.ci=persist-write")!=NULL;
 int isread=strstr(args,"xorriso.ci=persist-read")!=NULL;
 if(!iswrite&&!isread)return;
 int serial=open("/dev/ttyS0",O_RDWR|O_NOCTTY);
 if(serial>=0) {
  (void)dup2(serial,STDOUT_FILENO);(void)dup2(serial,STDERR_FILENO);
  if(serial>STDERR_FILENO)close(serial);
 }
 if(ci_exec_script("/usr/lib/xorriso/storage.sh","mount")!=0) {
  print("xorriso: persistence FAIL (mount)\n");
  for(;;)pause();
 }
 const char *path="/data/notes/xorriso-ci-note.txt";
 if(iswrite) {
  f=open(path,O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC,0600);
  if(f>=0) {
   const char *msg="hello-persist-0.9\n";
   ssize_t len=(ssize_t)strlen(msg);
   if(write(f,msg,(size_t)len)==len)print("xorriso: persistence write PASS\n");
   else print("xorriso: persistence FAIL (write)\n");
   (void)fsync(f);close(f);
  }else print("xorriso: persistence FAIL (open)\n");
 }else{
  char buf[128]={0};
  f=open(path,O_RDONLY|O_CLOEXEC);
  if(f>=0) {
   ssize_t len=read(f,buf,sizeof(buf)-1);close(f);
   if(len>0&&!strcmp(buf,"hello-persist-0.9\n"))print("xorriso: persistence read PASS\n");
   else print("xorriso: persistence FAIL (content)\n");
  }else print("xorriso: persistence FAIL (missing)\n");
 }
 for(;;)pause();
}


/* CI: exercise two separate labeled SATA volumes across two Linux boots. */
static int ci_file_has(const char *path,const char *expected) {
 char content[128]={0};
 int fd=open(path,O_RDONLY|O_CLOEXEC);
 if(fd<0)return 0;
 ssize_t n=read(fd,content,sizeof(content)-1);close(fd);
 return n==(ssize_t)strlen(expected)&&!memcmp(content,expected,(size_t)n);
}
static void ci_dual_volume_test(void) {
 char args[4096]={0};
 int fd=open("/proc/cmdline",O_RDONLY|O_CLOEXEC);
 if(fd<0)return;
 ssize_t n=read(fd,args,sizeof(args)-1);close(fd);
 if(n<=0)return;
 int iswrite=strstr(args,"xorriso.ci=dual-write")!=NULL;
 int isread=strstr(args,"xorriso.ci=dual-read")!=NULL;
 if(!iswrite&&!isread)return;
 int serial=open("/dev/ttyS0",O_RDWR|O_NOCTTY);
 if(serial>=0) {
  (void)dup2(serial,STDOUT_FILENO);(void)dup2(serial,STDERR_FILENO);
  if(serial>STDERR_FILENO)close(serial);
 }
 if(ci_exec_script("/usr/lib/xorriso/storage.sh","mount")!=0) {
  print("xorriso: dual volume FAIL (mount)\n");
  for(;;)pause();
 }
 if(!ci_file_has("/data/models/ci-weight.txt","MODEL_STAYS\n")||
    !ci_file_has("/runtime-data/runtime/llama-server","RUNTIME_SEPARATE\n")) {
  print("xorriso: dual volume FAIL (contents)\n");
  for(;;)pause();
 }
 int writecheck=open("/runtime-data/runtime/should-not-write",O_CREAT|O_WRONLY|O_CLOEXEC,0600);
 if(writecheck>=0) {
  close(writecheck);
  print("xorriso: dual volume FAIL (runtime not readonly)\n");
  for(;;)pause();
 }
 const char *note="/data/notes/ci-dual-note.txt";
 if(iswrite) {
  fd=open(note,O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC,0600);
  if(fd<0||write(fd,"PERSIST_OK\n",11)!=11) {
   print("xorriso: dual volume FAIL (write)\n");
  }else{
   (void)fsync(fd);
   print("xorriso: dual volume write PASS\n");
  }
  if(fd>=0)close(fd);
 }else{
  if(ci_file_has(note,"PERSIST_OK\n"))print("xorriso: dual volume read PASS\n");
  else print("xorriso: dual volume FAIL (reboot)\n");
 }
 for(;;)pause();
}


/* CI: real guest TCP connection from 127.0.0.1 to 127.0.0.1 after initramfs boot. */
static void ci_loopback_tcp_test(void) {
 char bootargs[4096]={0};
 int f=open("/proc/cmdline",O_RDONLY|O_CLOEXEC);
 if(f<0)return;
 ssize_t n=read(f,bootargs,sizeof(bootargs)-1);close(f);
 if(n<=0||!strstr(bootargs,"xorriso.ci=loopback"))return;
 int serial=open("/dev/ttyS0",O_RDWR|O_NOCTTY);
 if(serial>=0) {
  (void)dup2(serial,STDOUT_FILENO);(void)dup2(serial,STDERR_FILENO);
  if(serial>STDERR_FILENO)close(serial);
 }
 int server=-1,client=-1,peer=-1;
 struct sockaddr_in addr={0};
 socklen_t size=sizeof(addr);
 addr.sin_family=AF_INET;
 addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
 addr.sin_port=htons(0);
 server=socket(AF_INET,SOCK_STREAM,0);
 client=socket(AF_INET,SOCK_STREAM,0);
 if(server<0||client<0)goto fail;
 if(bind(server,(struct sockaddr*)&addr,sizeof(addr))<0)goto fail;
 if(listen(server,1)<0)goto fail;
 if(getsockname(server,(struct sockaddr*)&addr,&size)<0)goto fail;
 if(connect(client,(struct sockaddr*)&addr,sizeof(addr))<0)goto fail;
 peer=accept(server,NULL,NULL);
 if(peer<0)goto fail;
 if(write(client,"ping",4)!=4)goto fail;
 char msg[5]={0};
 if(read(peer,msg,4)!=4||memcmp(msg,"ping",4))goto fail;
 print("xorriso: loopback TCP PASS\n");
 goto done;
 fail:
 print("xorriso: loopback TCP FAIL\n");
 done:
 if(peer>=0)close(peer);
 if(client>=0)close(client);
 if(server>=0)close(server);
 for(;;)pause();
}


/* Start local model loading in the background: no terminal commands visible. */
static void start_local_ai_background(void) {
 pid_t p=fork();
 if(p==0) {
  int fd=open("/dev/null",O_RDWR|O_CLOEXEC);
  if(fd>=0) {
   (void)dup2(fd,STDIN_FILENO);(void)dup2(fd,STDOUT_FILENO);
   (void)dup2(fd,STDERR_FILENO);
   if(fd>STDERR_FILENO)close(fd);
  }
  setenv("PATH","/bin:/usr/bin:/sbin",1);
  execl("/bin/sh","sh","/usr/lib/xorriso/ai-boot.sh","start",(char*)NULL);
  _exit(127);
 }
}

int main(void) {
 setup_fs();
 int bootlog=open("/dev/kmsg",O_WRONLY|O_CLOEXEC);
 if(bootlog>=0){
  const char *marker="<6>xorriso: init reached successfully\n";
  (void)write(bootlog,marker,strlen(marker));close(bootlog);
 }
 int fd=open("/proc/sys/kernel/printk",O_WRONLY|O_CLOEXEC);
 if(fd>=0){(void)write(fd,"0 0 0 0\n",8);close(fd);}
 (void)mkdir("/run/xorriso",0700);
 (void)ci_exec_script("/usr/lib/xorriso/loopback.sh","up");
 ci_loopback_tcp_test();
 (void)ci_exec_script("/usr/lib/xorriso/storage.sh","boot");
 ci_dual_volume_test();
 ci_persistent_test();
 ci_host_bridge_test();
 setup_tty();setenv("TERM","linux",1);clear_screen();
 start_local_ai_background();
 chat_screen();
 char line[MAX_CMD+1];size_t n=0;
 for(;;) {
  if(is_console)print("\033[?25hxorriso> ");
  else if(is_chat)print("\033[?25hvoce> ");
  for(;;) {
   int key=read_key();
   if(key<0){
    if(is_chat && n==0) {
     char state[192];read_runtime("boot-status",state,sizeof(state));
     if(*state && strcmp(state,shown_ai_state)) {
      snprintf(shown_ai_state,sizeof(shown_ai_state),"%s",state);
      print("\r\nIA local: ");print(state);print("\r\nvoce> ");
     }
    }
    continue;
   }
   if(key==0x1001){status();n=0;break;}
   if(key==0x1002){console_header();n=0;break;}
   if(key==0x1003){chat_screen();n=0;break;}
   if(key==27){is_console=0;is_chat=0;clear_screen();n=0;break;}
   if(!is_console&&!is_chat)continue;
   if(key=='\r'||key=='\n'){
    line[n]=0;crlf();if(is_chat)chat_input(line);else cmd(line);n=0;break;
   }
   if(key==127||key=='\b'){if(n){n--;print("\b \b");}}
   else if(key>=32&&key<=255&&n<MAX_CMD){
    line[n++]=(char)key;unsigned char z=key;(void)write(STDOUT_FILENO,&z,1);
   }
  }
 }
}
