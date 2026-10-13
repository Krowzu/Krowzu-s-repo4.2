#include <stdarg.h>
#include <unistd.h>

int mini_printf(const char *format, ...)
{
    va_list args;
    int k = 0;
    int y = 0;
    int p = 0;

    va_start(args, format);
    for (; format[y] != '\0'; y++)
    {
        if (format[y] != '%')
        {
            write(1, &format[y], 1);
            k++;
        }
        else if (format[y + 1] == '\0')
        {
        }
        else
        {
            y++;
            if (format[y] == 'c')
            {
                char c = va_arg(args, int);
                write(1, &c, 1);
                k++;
            }
            else if (format[y] == 's')
            {
                char *s = va_arg(args, char *);
                if (s == NULL)
                    s = "(null)";
                for (; s[p] != '\0'; p++)
                {
                    write(1, &s[p], 1);
                    k++;
                }
            }
            else if (format[y] == 'd' || format[y] == 'i')
            {
                long nb = va_arg(args, int);
                char buf[11];
                int  l = 0;

                if (nb < 0)
                {
                    write(1, "-", 1);
                    k++;
                    nb = -nb;
                }
                if (nb == 0)
                {
                    buf[0] = '0';
                    l = 1;
                }
                for (; nb > 0; nb = nb / 10)
                {
                    buf[l] = (nb % 10) + '0';
                    l++;
                }
                for (p = l - 1; p >= 0; p--)
                {
                    write(1, &buf[p], 1);
                    k++;
                }
            }
            else if (format[y] == '%')
            {
                write(1, "%", 1);
                k++;
            }
        }
    }
    va_end(args);
    return (k);
}

int main(void)
{
    mini_printf("%d\n", 7789);
    mini_printf("%i\n", 676767);
    mini_printf("%c\n", 'b');
    mini_printf("%s\n", "az2erty");
    mini_printf("100%%\n");
    return (0);
}
