/*
** EPITECH PROJECT, 2026
** my_strncat.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

char *my_strncat(char *dest, char const *src, int nb)
{
    int z = 0;
    int a = 0;

    for (; dest[z] != '\0'; z++);
    for (; a < nb && src[a] != '\0'; a++)
        dest[z + a] = src[a];
    dest[z + a] = '\0';
    return dest;
}
