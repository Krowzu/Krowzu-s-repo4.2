/*
** EPITECH PROJECT, 2026
** my_str_isalpha.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

int my_str_isalpha(char const *str)
{
    int a = 0;

    for (; str[a] != '\0'; a++) {
        if (!((str[a] >= 'a' && str[a] <= 'z')
              || (str[a] >= 'A' && str[a] <= 'Z')))
            return 0;
    }
    return 1;
}
