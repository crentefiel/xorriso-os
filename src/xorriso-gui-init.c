/*
 * xorriso graphical PID1 wrapper: preserves the existing PID1 as /init-old.
 * SPDX-License-Identifier: MIT
 *
 * Do not ever format or partition the attached VDI disks.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/kd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static int spawn(const char *path,const char *argument,int wait_for){
 pid_t p=fork();
 if(p<0)return 127;
 if(p==0){
  if(!wait_for){
   int fd=open("/dev/null",O_RDWR);
   if(fd>=0){dup2(fd,0);dup2(fd,1);dup2(fd,2);if(fd>2)close(fd);}
  }
  setenv("PATH","/bin:/usr/bin:/sbin",1);
  execl(path,path,argument,(char*)NULL);
  _exit(127);
 }
 if(!wait_for)return 0;
 int status=0;
 while(waitpid(p,&status,0)<0){if(errno!=EINTR)return 127;}
 return WIFEXITED(status)?WEXITSTATUS(status):128;
}
static void log_text(const char *msg){
 int fd=open("/dev/ttyS0",O_WRONLY|O_NOCTTY|O_NONBLOCK);
 if(fd>=0){write(fd,msg,strlen(msg));close(fd);}
 fd=open("/dev/kmsg",O_WRONLY|O_CLOEXEC|O_NONBLOCK);
 if(fd>=0){write(fd,msg,strlen(msg));close(fd);}
}
static void old_console(void){
 log_text("xorriso: booting text console fallback\n");
 execl("/init-old","init-old",(char*)NULL);
 for(;;)pause();
}
static void load_module(const char *name){
 char path[160];
 snprintf(path,sizeof(path),"/lib/xorriso/modules/%s.ko",name);
 if(access(path,F_OK)==0)spawn("/bin/insmod",path,1);
}
static void keyboard(void){
 pid_t p=fork();
 if(p==0){
  execl("/usr/bin/loadkeys","loadkeys","-q","-u","-C","/dev/tty0",
        "/etc/xorriso/br-abnt2.map",(char*)NULL);
  _exit(127);
 }
 if(p>0){int status;while(waitpid(p,&status,0)<0 && errno==EINTR){}}
 int fd=open("/dev/tty0",O_RDWR|O_NOCTTY);
 if(fd>=0){ioctl(fd,KDSKBMODE,K_UNICODE);close(fd);}
}
int main(void){
 mount("proc","/proc","proc",MS_NOSUID|MS_NODEV|MS_NOEXEC,"");
 mount("sysfs","/sys","sysfs",MS_NOSUID|MS_NODEV|MS_NOEXEC,"");
 mount("devtmpfs","/dev","devtmpfs",MS_NOSUID,"mode=0755");
 mount("tmpfs","/run","tmpfs",MS_NOSUID|MS_NODEV,"size=160M,mode=0755");
 mount("tmpfs","/tmp","tmpfs",MS_NOSUID|MS_NODEV,"size=32M,mode=1777");
 mkdir("/run/xorriso",0700);
 // Existing QEMU console/storage tests must still execute the original PID1.
 char cmdline[4096]={0};
 int fd=open("/proc/cmdline",O_RDONLY);
 if(fd>=0){read(fd,cmdline,sizeof(cmdline)-1);close(fd);}
 if(strstr(cmdline,"xorriso.ci=")||strstr(cmdline,"xorriso.text=1"))old_console();
 log_text("xorriso: graphical PID1 started\n");
 // Explicitly load PS/2 mouse support (modules are optional on different kernels).
 load_module("libps2");load_module("serio");load_module("psmouse");
 load_module("evdev");load_module("mousedev");
 // Startup for the original AI scripts uses /bin/sh with one argument.
 pid_t setup=fork();
 if(setup==0){
  execl("/bin/sh","sh","/usr/lib/xorriso/loopback.sh","up",(char*)NULL);_exit(127);
 }
 if(setup>0){int s;while(waitpid(setup,&s,0)<0&&errno==EINTR){}}
 setup=fork();
 if(setup==0){
  execl("/bin/sh","sh","/usr/lib/xorriso/storage.sh","boot",(char*)NULL);_exit(127);
 }
 if(setup>0){int s;while(waitpid(setup,&s,0)<0&&errno==EINTR){}}
 setup=fork();
 if(setup==0){
  int null=open("/dev/null",O_RDWR);
  if(null>=0){dup2(null,0);dup2(null,1);dup2(null,2);if(null>2)close(null);}
  execl("/bin/sh","sh","/usr/lib/xorriso/ai-boot.sh","start",(char*)NULL);_exit(127);
 }
 keyboard();
 setenv("LANG","pt_BR.UTF-8",1);
 int ok=0;
 for(int i=0;i<30;i++){
  fd=open("/dev/fb0",O_RDWR|O_CLOEXEC);
  if(fd>=0){close(fd);ok=1;break;}
  usleep(200000);
 }
 if(!ok){log_text("xorriso: fb0 unavailable, switching to console\n");old_console();}
 log_text("xorriso: launching native desktop\n");
 pid_t desktop=fork();
 if(desktop==0){
  execl("/usr/bin/xorriso-desktop","xorriso-desktop",(char*)NULL);
  _exit(127);
 }
 if(desktop<0)old_console();
 int status=0;
 while(waitpid(desktop,&status,0)<0 && errno==EINTR){}
 char line[120];
 snprintf(line,sizeof(line),"xorriso: desktop exited status=%d signal=%d\n",
  WIFEXITED(status)?WEXITSTATUS(status):-1,WIFSIGNALED(status)?WTERMSIG(status):0);
 log_text(line);
 // Restore Linux VT text mode if desktop exits unexpectedly.
 fd=open("/dev/tty0",O_RDWR);
 if(fd>=0){ioctl(fd,KDSETMODE,KD_TEXT);close(fd);}
 old_console();
}
