/*
** EPITECH PROJECT, 2026
** my_isneg.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_isneg(int nb)
{
    if (nb < 0)
        write(1, "N", 1);
    else
        write(1, "P", 1);
    return (nb < 0) ? 1 : 0;
}
