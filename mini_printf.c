/*
** EPITECH PROJECT, 2026
** mini_printf.c
** File description:
** No file there, just an epitech header example.
*/

#include <stdarg.h>
#include <unistd.h>

int mini_printf(const char *format, ...)
{
    int a = 0;

    for (int b = 0; format[b] != '\0'; format++)
    {
        if (*format != '%')
            write(1, format, 1);
        else if (*(format++) == '\0')	//rien
            write(1, &format, 1);
        else if (*(format++) == 'd' || *(format++) == 'i')	//décimal
            ;
        else if (*(format++) == 's') 	//string
            ;
        else if (*(format++) == 'c')	//char
            ;
        else if (*(format++) == '%')	//%
            ;
}

int main(void)
{
    mini_printf("%d\n", 7789); 
    mini_printf("%i\n", 676767);
    mini_printf("%c\n", 'b');
    mini_printf("%s\n", "az2erty");
    mini_printf("%%\n", 110%);
    return (0);
}
