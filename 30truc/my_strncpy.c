/*
** EPITECH PROJECT, 2026
** my_strncpy.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

char *my_strncpy(char *dest, char const *src, int n)
{
    int z = 0;

    for (; z < n && src[z] != '\0'; z++)
        dest[z] = src[z];
    for (; z < n; z++)
        dest[z] = '\0';
    return dest;
}
