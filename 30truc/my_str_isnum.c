/*
** EPITECH PROJECT, 2026
** my_str_isnum.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_str_isnum(char const *str)
{
    int d = 0;

    for (; str[d] != '\0'; d++) {
        if (str[d] < '0' || str[d] > '9')
            return 0;
    }
    return 1;
}
