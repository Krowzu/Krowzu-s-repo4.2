/*
** EPITECH PROJECT, 2026
** my_str_isprintable.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_str_isprintable(char const *str)
{
    int b = 0;

    for (; str[b] != '\0'; b++) {
        if (str[b] < 32 || str[b] > 126)
            return 0;
    }
    return 1;
}
