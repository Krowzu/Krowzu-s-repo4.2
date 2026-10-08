/*
** EPITECH PROJECT, 2026
** my_strlowcase.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

char *my_strlowcase(char *str)
{
    int a = 0;

    for (; str[a] != '\0'; a++) {
        if (str[a] >= 'A' && str[a] <= 'Z')
            str[a] = str[a] + 32;
    }
    return str;
}
