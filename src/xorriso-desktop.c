/*
 * xorriso OS - native framebuffer desktop (alpha 0.15.5)
 * SPDX-License-Identifier: MIT
 * No X11/browser dependency. All Linux actions go through chat-actions.sh.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <linux/kd.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define MSGS 20
#define MAXTEXT 700
static struct fb_fix_screeninfo fi;
static struct fb_var_screeninfo vi;
static unsigned char *screen;
static size_t screen_size;
static int width,height,fb=-1,tty=-1,mouse=-1,shown=0,maxed=0,drag=0;
static int mx=120,my=170,down=0,offsetx,offsety;
static int winx,winy,winw,winh,dirty=1;
static unsigned char font[256][16];
static struct termios old_tty;
static int tty_saved=0;
static char typed[MAXTEXT+1],state[120]="preparando";
static char answers[MSGS][1400];
static int roles[MSGS],count=0;
static int channel=-1,pending=0;
static pid_t child=-1;
static time_t deadline=0;
static char result[4000];
static size_t result_len=0;
static unsigned long paint_ops=0;
static int quit=0;

static int min(int a,int b){return a<b?a:b;}
static int max(int a,int b){return a>b?a:b;}
static int cap(int a,int low,int high){return max(low,min(a,high));}
static unsigned pixel_value(unsigned c){
 unsigned r=(c>>16)&255,g=(c>>8)&255,b=c&255;
 unsigned x=0;
 if(vi.red.length) x|=(r>>max(0,8-(int)vi.red.length))<<vi.red.offset;
 if(vi.green.length) x|=(g>>max(0,8-(int)vi.green.length))<<vi.green.offset;
 if(vi.blue.length) x|=(b>>max(0,8-(int)vi.blue.length))<<vi.blue.offset;
 return x;
}
static void block(int x,int y,int w,int h,unsigned rgb){
 if(w<=0||h<=0||!screen)return;
 int ex=cap(x+w,0,width),ey=cap(y+h,0,height);
 x=cap(x,0,width);y=cap(y,0,height);
 if(x>=ex||y>=ey)return;
 int bpp=(int)vi.bits_per_pixel/8;
 unsigned p=pixel_value(rgb);
 for(int yy=y;yy<ey;yy++){
  size_t o=(size_t)(yy+vi.yoffset)*fi.line_length+(size_t)(x+vi.xoffset)*bpp;
  size_t bytes=(size_t)(ex-x)*bpp;
  if(o>screen_size||bytes>screen_size-o)continue;
  unsigned char *q=screen+o;
  for(int xx=x;xx<ex;xx++,q+=bpp){
   q[0]=p&255;q[1]=(p>>8)&255;
   if(bpp>=3)q[2]=(p>>16)&255;
   if(bpp>=4)q[3]=(p>>24)&255;
  }
  paint_ops++;
 }
}
static void outline(int x,int y,int w,int h,unsigned c){
 block(x,y,w,1,c);block(x,y+h-1,w,1,c);
 block(x,y,1,h,c);block(x+w-1,y,1,h,c);
}
static unsigned unicode(const unsigned char **s){
 unsigned c=*(*s)++;
 if(c<128)return c;
 if((c&0xe0)==0xc0&&(**s&0xc0)==0x80){unsigned n=(c&31)<<6|(**s&63);(*s)++;return n;}
 if((c&0xf0)==0xe0&&(**s&0xc0)==0x80){unsigned n=(c&15)<<12|(**s&63);(*s)++;if((**s&0xc0)==0x80){n=(n<<6)|(**s&63);(*s)++;}return n;}
 while((**s&0xc0)==0x80)(*s)++;
 return '?';
}
static void label(int x,int y,const char *str,unsigned c,int scale,int limit){
 if(!str)return;
 const unsigned char *q=(const unsigned char*)str;
 for(int z=0;*q && z<limit;z++){
  unsigned ch=unicode(&q);
  if(ch=='\n'||ch=='\r')break;
  if(ch>255)ch='?';
  for(int yy=0;yy<16;yy++)for(int xx=0;xx<8;xx++)
   if(font[ch][yy]&(1U<<(7-xx)))
    block(x+8*scale*z+xx*scale,y+yy*scale,scale,scale,c);
 }
}
static void paragraph(int x,int y,const char *str,unsigned c,int chars,int rows){
 if(!str||chars<1||rows<1)return;
 const unsigned char*q=(const unsigned char*)str;
 int col=0,row=0;
 while(*q && row<rows){
  unsigned ch=unicode(&q);
  if(ch=='\r')continue;
  if(ch=='\n'||col>=chars){row++;col=0;if(row>=rows)break;if(ch=='\n')continue;}
  if(ch>255)ch='?';
  for(int yy=0;yy<16;yy++)for(int xx=0;xx<8;xx++)
   if(font[ch][yy]&(1U<<(7-xx)))block(x+8*col+xx,y+16*row+yy,1,1,c);
  col++;
 }
}
static void message(int role,const char *s){
 if(count==MSGS){memmove(answers,answers+1,sizeof(answers[0])*(MSGS-1));memmove(roles,roles+1,sizeof(int)*(MSGS-1));count--;}
 roles[count]=role;
 snprintf(answers[count],sizeof(answers[count]),"%s",s?s:"");
 count++;dirty=1;
}
static void load_font(void){
 int fd=open("/usr/share/xorriso/font8x16.bin",O_RDONLY|O_CLOEXEC);
 if(fd>=0){size_t n=0;while(n<sizeof(font)){ssize_t k=read(fd,(char*)font+n,sizeof(font)-n);if(k<=0)break;n+=(size_t)k;}close(fd);}
}
static void dimensions(void){
 winw=cap(width-125,450,890);winh=cap(height-105,350,640);
 if(winw>width-14)winw=width-14;
 if(winh>height-55)winh=height-55;
 winx=(width-winw)/2;winy=(height-winh-42)/2;
}
static void wallpaper(void){
 for(int y=0;y<height;y+=6){int r=13+y*7/height,g=23+y*8/height,b=38+y*19/height;block(0,y,width,6,(r<<16)|(g<<8)|b);}
 for(int y=height/2;y<height-43;y+=6)block(0,y,width-(y-height/2)*width/(2*height),6,0x1f2c45);
 label(width/2-105,max(34,height/9),"xorriso OS",0xe6eef9,2,14);
 block(62,174,76,69,0x2276ac);outline(62,174,76,69,0x71d7f5);
 label(78,190,"IA",0xf4faff,2,2);label(90,249,"IA",0xe6e9fa,1,4);
 block(0,height-42,width,42,0x0e1928);
 label(14,height-28,"xorriso OS",0xdfe9f7,1,16);
 block(149,height-38,88,32,0x24405f);label(177,height-29,"IA",0xf7fbff,1,3);
}
static void window_paint(void){
 if(!shown)return;
 int side=cap(winw/4,126,180),mainx=winx+side,mainw=winw-side;
 block(winx+5,winy+6,winw,winh,0x070e19);
 block(winx,winy,winw,winh,0x141d2b);outline(winx,winy,winw,winh,0x64768a);
 block(winx,winy,winw,44,0x1d2d44);
 label(winx+18,winy+14,"xorriso IA",0xf4f8ff,1,20);
 block(winx+winw-104,winy+8,30,27,0x334b67);
 block(winx+winw-70,winy+8,30,27,0x334b67);
 block(winx+winw-36,winy+8,28,27,0x733245);
 label(winx+winw-94,winy+13,"-",0xffffff,1,1);
 label(winx+winw-60,winy+13,"+",0xffffff,1,1);
 label(winx+winw-26,winy+13,"x",0xffffff,1,1);
 block(winx,winy+44,side,winh-44,0x18283a);
 block(winx+8,winy+57,side-16,32,0x315477);
 label(winx+14,winy+65,"+ Nova conversa",0xf0f5ff,1,min(16,(side-20)/8));
 label(winx+14,winy+104,"HISTORICO",0xb2c7df,1,(side-18)/8);
 block(mainx,winy+44,mainw,35,0x242f42);
 char status[160];snprintf(status,sizeof(status),"IA local: %.90s",state);
 label(mainx+12,winy+54,status,0xe9c28c,1,(mainw-20)/8);
 int view_top=winy+92,view_end=winy+winh-102;
 int slots=max(1,(view_end-view_top)/55),start=max(0,count-slots);
 for(int i=start;i<count;i++){
  int y=view_top+(i-start)*55;
  block(mainx+12,y,mainw-26,49,roles[i]?0x295076:0x293a51);
  paragraph(mainx+19,y+6,answers[i],0xf3f7fe,max(1,(mainw-50)/8),2);
 }
 int iy=winy+winh-82;
 block(mainx+12,iy,mainw-111,48,0x273d57);
 outline(mainx+12,iy,mainw-111,48,0x5e84a7);
 if(typed[0])label(mainx+20,iy+15,typed,0xffffff,1,max(1,(mainw-140)/8));
 else label(mainx+20,iy+15,"Digite uma mensagem...",0xb0bdcd,1,max(1,(mainw-140)/8));
 block(mainx+mainw-90,iy+7,76,34,pending?0x455165:0x2b89bf);
 label(mainx+mainw-83,iy+16,"Enviar",0xffffff,1,7);
 label(mainx+14,winy+winh-23,"Respostas verificadas em acoes reais",0xa6bbd5,1,max(1,(mainw-30)/8));
}
static void cursor_paint(void){for(int i=0;i<14;i++){block(mx+i/3,my+i,2,2,0x000000);block(mx+i/3,my+i,1,2,0xffffff);}}
static void render(void){if(!dirty)return;wallpaper();window_paint();cursor_paint();dirty=0;}
static void request_send(void){
 if(pending||!typed[0])return;
 char cmd[MAXTEXT+1];snprintf(cmd,sizeof(cmd),"%s",typed);typed[0]=0;
 message(1,cmd);
 int fd[2];if(pipe(fd)<0){message(0,"Nao foi possivel abrir canal de resposta.");return;}
 pid_t p=fork();
 if(p<0){close(fd[0]);close(fd[1]);message(0,"Falha ao iniciar a consulta.");return;}
 if(p==0){
  close(fd[0]);dup2(fd[1],STDOUT_FILENO);dup2(fd[1],STDERR_FILENO);close(fd[1]);
  execl("/bin/sh","sh","/usr/lib/xorriso/chat-actions.sh",cmd,(char*)NULL);
  _exit(127);
 }
 close(fd[1]);fcntl(fd[0],F_SETFL,fcntl(fd[0],F_GETFL,0)|O_NONBLOCK);
 child=p;channel=fd[0];pending=1;deadline=time(NULL)+140;result_len=0;result[0]=0;dirty=1;
}
static void answer_poll(void){
 if(!pending)return;
 char buf[512];ssize_t n;
 while((n=read(channel,buf,sizeof(buf)))>0){
  size_t k=min((int)n,(int)(sizeof(result)-1-result_len));
  memcpy(result+result_len,buf,k);result_len+=k;result[result_len]=0;
 }
 if(n==0){
  close(channel);channel=-1;pending=0;
  if(child>0){int status;waitpid(child,&status,WNOHANG);}
  child=-1;message(0,result[0]?result:"Sem resposta da IA. Verifique o status.");
 }else if(time(NULL)>deadline){
  if(child>0)kill(child,SIGKILL);
  close(channel);channel=-1;pending=0;child=-1;
  message(0,"Tempo esgotado. Nao foi possivel confirmar o resultado.");
 }
}
static int hit(int x,int y,int w,int h){return mx>=x&&mx<x+w&&my>=y&&my<y+h;}
static void click(void){
 if(!shown){if(hit(58,170,94,104)||hit(146,height-42,92,42)){shown=1;dirty=1;}return;}
 if(hit(winx+winw-104,winy+8,30,27)){shown=0;dirty=1;return;}
 if(hit(winx+winw-70,winy+8,30,27)){
  maxed=!maxed;if(maxed){winx=8;winy=8;winw=width-16;winh=height-58;}else dimensions();
  dirty=1;return;
 }
 if(hit(winx+winw-36,winy+8,28,27)){shown=0;dirty=1;return;}
 int side=cap(winw/4,126,180);
 if(hit(winx+8,winy+57,side-16,32)){
  if(!pending){count=0;message(0,"Nova conversa. Como posso ajudar?");}
  return;
 }
 int mainx=winx+side,mainw=winw-side,iy=winy+winh-82;
 if(hit(mainx+mainw-90,iy+7,76,34)){request_send();return;}
 if(hit(winx,winy,winw-115,44)){drag=1;offsetx=mx-winx;offsety=my-winy;}
}
static void read_mouse(void){
 if(mouse<0)return;
 unsigned char p[3];
 while(read(mouse,p,3)==3){
  int pressed=(p[0]&1)!=0;
  mx=cap(mx+(int8_t)p[1],0,width-1);
  my=cap(my-(int8_t)p[2],0,height-1);
  if(pressed&&!down)click();
  if(!pressed)drag=0;
  down=pressed;
  if(drag&&!maxed){winx=cap(mx-offsetx,0,width-winw);winy=cap(my-offsety,0,height-winh-42);}
  dirty=1;
 }
}
static void read_keys(void){
 if(tty<0)return;
 unsigned char c[128];ssize_t n;
 while((n=read(tty,c,sizeof(c)))>0)for(ssize_t i=0;i<n;i++){
  unsigned k=c[i];
  if(k==27){shown=0;dirty=1;continue;}
  if(!shown){if(k=='i'||k=='I'||k=='\r'||k=='\n'){shown=1;dirty=1;}continue;}
  if(k==13||k==10){request_send();continue;}
  if(k==127||k==8){
   size_t len=strlen(typed);
   if(len){len--;while(len && ((unsigned char)typed[len]&0xc0)==0x80)len--;typed[len]=0;dirty=1;}
   continue;
  }
  if(k>=32&&!pending){size_t len=strlen(typed);if(len<MAXTEXT-4){typed[len]=(char)k;typed[len+1]=0;dirty=1;}}
 }
}
static void poll_status(void){
 char b[sizeof(state)]={0};
 int fd=open("/run/xorriso/boot-status",O_RDONLY|O_CLOEXEC);
 if(fd<0)return;
 ssize_t n=read(fd,b,sizeof(b)-1);close(fd);
 if(n>0){b[strcspn(b,"\r\n")]=0;if(strcmp(b,state)){snprintf(state,sizeof(state),"%s",b);dirty=1;}}
}
static int framebuffer(void){
 fb=open("/dev/fb0",O_RDWR|O_CLOEXEC);
 if(fb<0){perror("open /dev/fb0");return 1;}
 if(ioctl(fb,FBIOGET_VSCREENINFO,&vi)<0 || ioctl(fb,FBIOGET_FSCREENINFO,&fi)<0){perror("framebuffer ioctl");return 2;}
 width=(int)vi.xres;height=(int)vi.yres;
 int bytes=(int)vi.bits_per_pixel/8;
 if(width<640||height<480||width>8192||height>8192||(bytes!=2&&bytes!=3&&bytes!=4)){
  fprintf(stderr,"Unsupported framebuffer: %dx%d bpp=%u\n",width,height,vi.bits_per_pixel);return 3;
 }
 if((size_t)(vi.xoffset+vi.xres)*bytes>fi.line_length||
    (uint64_t)(vi.yoffset+vi.yres)*fi.line_length>fi.smem_len||
    !fi.smem_len){
  fprintf(stderr,"Unsafe framebuffer geometry (stride=%u, smem=%u)\n",fi.line_length,fi.smem_len);return 4;
 }
 screen_size=fi.smem_len;
 screen=mmap(NULL,screen_size,PROT_READ|PROT_WRITE,MAP_SHARED,fb,0);
 if(screen==MAP_FAILED){screen=NULL;perror("mmap fb0");return 5;}
 return 0;
}
static void input_setup(void){
 tty=open("/dev/tty0",O_RDWR|O_NONBLOCK|O_NOCTTY);
 if(tty>=0){
  if(tcgetattr(tty,&old_tty)==0){struct termios raw=old_tty;cfmakeraw(&raw);raw.c_oflag|=OPOST;
   if(tcsetattr(tty,TCSANOW,&raw)==0)tty_saved=1;
  }
  ioctl(tty,KDSKBMODE,K_UNICODE);
  ioctl(tty,KDSETMODE,KD_GRAPHICS);
 }
 mouse=open("/dev/input/mice",O_RDONLY|O_NONBLOCK|O_CLOEXEC);
}
static void input_restore(void){
 if(tty>=0){ioctl(tty,KDSETMODE,KD_TEXT);if(tty_saved)tcsetattr(tty,TCSANOW,&old_tty);close(tty);}
 if(mouse>=0)close(mouse);
 if(screen)munmap(screen,screen_size);
 if(fb>=0)close(fb);
}
static void serial(const char *line){
 int fd=open("/dev/ttyS0",O_WRONLY|O_NOCTTY|O_NONBLOCK|O_CLOEXEC);
 if(fd>=0){write(fd,line,strlen(line));close(fd);}
}
static int selftest(void){
 width=800;height=600;
 memset(&vi,0,sizeof(vi));memset(&fi,0,sizeof(fi));
 vi.xres=800;vi.yres=600;vi.bits_per_pixel=32;vi.red.length=8;vi.red.offset=16;
 vi.green.length=8;vi.green.offset=8;vi.blue.length=8;vi.blue.offset=0;
 fi.line_length=800*4;fi.smem_len=800*600*4;
 screen_size=fi.smem_len;screen=calloc(1,screen_size);
 if(!screen)return 1;
 dimensions();message(0,"Desktop grafico de teste.");shown=1;
 render();
 int changed=0;for(size_t i=0;i<screen_size;i++)if(screen[i]){changed=1;break;}
 free(screen);screen=NULL;
 if(!changed||paint_ops<200){fprintf(stderr,"Desktop selftest FAILED\n");return 1;}
 puts("xorriso: native desktop selftest PASS");
 return 0;
}
static void term(int signo){(void)signo;quit=1;}
int main(int argc,char **argv){
 if(argc>1&&!strcmp(argv[1],"--selftest"))return selftest();
 signal(SIGPIPE,SIG_IGN);signal(SIGTERM,term);signal(SIGINT,term);
 if(framebuffer())return 10;
 load_font();dimensions();mx=width/2;my=height/2;
 input_setup();message(0,"Ola! Sou a IA do xorriso. Digite um pedido e pressione Enter.");
 render();serial("xorriso: desktop framebuffer rendered PASS\n");
 time_t last=0;
 while(!quit){
  time_t now=time(NULL);
  if(now!=last){poll_status();last=now;}
  answer_poll();read_mouse();read_keys();render();usleep(25000);
 }
 input_restore();return 0;
}
