/*
** EPITECH PROJECT, 2026
** my_strcat.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

char *my_strcat(char *dest, char const *src)
{
    int x = 0;
    int y = 0;

    for (; dest[x] != '\0'; x++);
    for (; src[y] != '\0'; y++)
        dest[x + y] = src[y];
    dest[x + y] = '\0';
    return dest;
}
