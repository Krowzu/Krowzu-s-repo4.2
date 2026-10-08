/*
** EPITECH PROJECT, 2026
** my_strcpy.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

char *my_strcpy(char *dest, char const *src)
{
    int s = 0;

    for (s = 0; src[s] != '\0'; s++)
        dest[s] = src[s];
    dest[s] = '\0';
    return dest;
}
