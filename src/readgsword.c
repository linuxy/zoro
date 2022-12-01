#include <intrin.h>
#include <windows.h>

int APIENTRY WinMain(HINSTANCE hInst, HINSTANCE hInstPrev, PSTR cmdline, int cmdshow)
{
}

/* for __x86_64 only */
unsigned __int64 __readgsqword(unsigned long Offset)
{
   void *ret;
   __asm__ volatile ("movq	%%gs:%1,%0"
     : "=r" (ret) ,"=m" ((*(volatile long *) (unsigned __int64) Offset)));
   return (unsigned __int64) ret;
}

