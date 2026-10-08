/*
** EPITECH PROJECT, 2026
** my_str_isupper.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_str_isupper(char const *str)
{
    int s = 0;

    for (; str[s] != '\0'; s++) {
        if (str[s] < 'A' || str[s] > 'Z')
            return 0;
    }
    return 1;
}
