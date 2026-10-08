/*
** EPITECH PROJECT, 2026
** my_strstr.c
** File description:
** No file there, just an epitech header example.
*/

#include <unistd.h>

char *my_strstr(char *str, char const *to_find)
{
    int v = 0;
    int k = 0;

    if (to_find[0] == '\0')
        return str;
    for (; str[v] != '\0'; v++) {
        for (; str[v + k] == to_find[k] && to_find[k] != '\0'; k++);
        if (to_find[k] == '\0')
            return &str[v];
    }
    return 0;
}
