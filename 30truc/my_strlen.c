/*
** EPITECH PROJECT, 2026
** my_strlen.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_strlen(char const *str)
{
    int c = 0;

    for (; str[c] != '\0'; c++);
    return c;
}
