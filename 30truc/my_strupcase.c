/*
** EPITECH PROJECT, 2026
** my_strupcase.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

char *my_strupcase(char *str)
{
    int h = 0;

    for (; str[h] != '\0'; h++) {
        if (str[h] >= 'a' && str[h] <= 'z')
            str[h] = str[h] - 32;
    }
    return str;
}
