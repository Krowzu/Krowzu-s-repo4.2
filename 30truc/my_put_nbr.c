/*
** EPITECH PROJECT, 2026
** my_put_nbr.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_put_nbr(int nb)
{
    int len = 0;
    char c;

    if (nb < 0) {
        len += write(1, "-", 1);
        if (nb <= -10)
            len += my_put_nbr(nb / 10);
        c = -(nb % 10) + '0';
    } else {
        if (nb >= 10)
            len += my_put_nbr(nb / 10);
        c = nb % 10 + '0';
    }
    len += write(1, &c, 1);
    return len;
}
