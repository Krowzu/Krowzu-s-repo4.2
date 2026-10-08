/*
** EPITECH PROJECT, 2026
** my_getnbr.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_getnbr(char const *str)
{
    int i = 0;
    int s = 1;
    int n = 0;

    for (; str[i] == '+' || str[i] == '-'; i++) {
        if (str[i] == '-')
            s = -s;
    }
    for (; str[i] >= '0' && str[i] <= '9'; i++)
        n = n * 10 + (str[i] - '0');
    return (n * s);
}
