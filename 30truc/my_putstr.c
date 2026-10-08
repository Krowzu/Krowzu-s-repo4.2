/*
** EPITECH PROJECT, 2026
** my_putstr.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_putstr(char const *str)
{
    int v = 0;

    for (v = 0; str[v] != '\0'; v++);
    write(1, str, v);
    return (v);
}
