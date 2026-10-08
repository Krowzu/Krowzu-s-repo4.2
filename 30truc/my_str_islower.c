/*
** EPITECH PROJECT, 2026
** my_str_islower.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_str_islower(char const *str)
{
    int l = 0;

    for (; str[l] != '\0'; l++) {
        if (str[l] < 'a' || str[l] > 'z')
            return 0;
    }
    return 1;
}
