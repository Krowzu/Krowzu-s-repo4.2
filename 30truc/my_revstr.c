/*
** EPITECH PROJECT, 2026
** my_revstr.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

char *my_revstr(char *str)
{
    int a = 0;
    int b = 0;

    for (; str[b] != '\0'; b++);
        b--;
    for (; a < b; a++) {
        char tmp = str[a];

        str[a] = str[b];
        str[b] = tmp;
        b--;
    }
    return str;
}
